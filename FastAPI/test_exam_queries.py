import unittest
from unittest.mock import Mock, patch
from urllib.parse import urlencode

from fastapi.testclient import TestClient

from FastAPI.exam_queries import exam_cas_url, exam_launch_url, normalize_exam_data
from FastAPI.jwxt_automation import _pipeline_process_entry, login_browser
from FastAPI.main import app
from FastAPI.service_common import ServiceError


class ExamParsingTests(unittest.TestCase):
    def row(self, **kwargs):
        return {"kcmc": "高等数学", "kscs": "2026-12-20(09:00-11:00)",
                "xqmc": "两江", "ldmc": "教学楼", "cdmc": "A101", **kwargs}

    def parse(self, *rows):
        return normalize_exam_data({"IsSuccessful": True, "Data": list(rows)})

    def test_dates_and_all_location_fields(self):
        row = self.parse(self.row())[0]
        self.assertEqual("2026-12-20T09:00:00+08:00", row["start_at"])
        self.assertEqual("2026-12-20T11:00:00+08:00", row["end_at"])
        self.assertEqual(("两江", "教学楼", "A101"), (row["campus"], row["building"], row["room"]))

    def test_normalized_keys_are_stable_and_duplicates_collapse(self):
        first, second = self.row(), self.row(kcmc=" 高等数学 ", cdmc="Ａ１０１")
        self.assertEqual(self.parse(first)[0]["key"], self.parse(second)[0]["key"])
        self.assertEqual(1, len(self.parse(first, second)))
        self.assertNotEqual(self.parse(first)[0]["key"], self.parse(self.row(cdmc="A102"))[0]["key"])

    def test_unknown_or_invalid_times_retain_text_without_dates(self):
        for text in ("待安排", "", "2026-02-30(09:00-11:00)", "2026-12-20(11:00-09:00)"):
            with self.subTest(text=text):
                row = self.parse(self.row(kscs=text))[0]
                self.assertEqual(text, row["time_text"])
                self.assertIsNone(row["start_at"])
                self.assertIsNone(row["end_at"])

    def test_empty_success_and_malformed_response_are_distinct(self):
        self.assertEqual([], self.parse())
        invalid = [{}, {"IsSuccessful": "true", "Data": []}, {"IsSuccessful": False, "Data": []},
                   {"IsSuccessful": True, "Data": None}, {"IsSuccessful": True, "Data": [None]},
                   {"IsSuccessful": True, "Data": [self.row(cdmc=None)]},
                   {"IsSuccessful": True, "Data": [self.row(kcmc=" ")]}]
        for body in invalid:
            with self.subTest(body=body), self.assertRaises(ServiceError):
                normalize_exam_data(body)


class ExamAuthenticationTests(unittest.TestCase):
    def test_cas_url_has_generic_mobile_callback(self):
        service = "https://uis.cqut.edu.cn/ump/common/login/authSourceAuth/auth"
        url = "https://uis.cqut.edu.cn/center-auth-server/officeHallApplicationCode/cas/login?" + urlencode({"service": service})
        session = Mock()
        session.get.return_value.json.return_value = {"code": "40001", "content": {"authSource": "CAS_PLUS", "redirectUri": url}}
        self.assertEqual(url, exam_cas_url(session, 20))
        self.assertNotIn("applicationCode", session.get.call_args.kwargs["params"])
        self.assertNotIn("sign", session.get.call_args.kwargs["params"])
        session.get.return_value.json.return_value["content"]["redirectUri"] = "https://wrong.example/login"
        with self.assertRaises(ServiceError):
            exam_cas_url(session, 20)

    def test_mobile_launch_uses_fresh_native_and_mic_tokens_without_duplicate_oauth(self):
        session = Mock()
        session.headers = {}
        contents = [{"ticket": "fresh-oauth"}, {"token": "fresh-mic"},
                    {"redirectUrl": "http://ksap-w.cqut.edu.cn/sso/app?ticket=fresh"}]
        calls = []
        def get(url, **kwargs):
            calls.append((url, kwargs, dict(session.headers)))
            return Mock(json=lambda: {"code": "40001", "content": contents.pop(0)})
        session.get.side_effect = get
        with patch("FastAPI.exam_queries.requests.Session") as factory:
            factory.return_value.__enter__.return_value = session
            self.assertEqual("http://ksap-w.cqut.edu.cn/sso/app?ticket=fresh", exam_launch_url("fresh-native", 20))
        self.assertTrue(calls[1][0].endswith("/fresh-oauth"))
        self.assertNotIn("mictoken", calls[0][2])
        self.assertEqual("fresh-native", calls[1][2]["token"])
        self.assertEqual("fresh-mic", calls[2][2]["mictoken"])
        self.assertEqual("GTR585", calls[2][1]["params"]["applicationCode"])
        for _, kwargs, _ in calls:
            self.assertNotIn("sign", kwargs["params"])

    def test_mobile_launch_rejects_invalid_ticket_or_target(self):
        for first in ({}, {"ticket": None}):
            with patch("FastAPI.exam_queries._mobile_content", return_value=first), self.assertRaises(ServiceError):
                exam_launch_url("native", 20)
        for url in ("https://ksap-w.cqut.edu.cn/sso/app", "http://wrong.example/sso/app", None):
            with patch("FastAPI.exam_queries._mobile_content", side_effect=[{"ticket": "ticket-oauth"}, {"token": "mic"}, {"redirectUrl": url}]), self.assertRaises(ServiceError):
                exam_launch_url("native", 20)

    def test_browser_uses_encrypted_credentials_and_rejects_auth_failure(self):
        page = Mock()
        page.evaluate.return_value = {"code": 200}
        payload = {"name": "student", "pwd": "encrypted"}
        login_browser(page, "https://uis.cqut.edu.cn/login", "https://uis.cqut.edu.cn/doLogin", payload, 20000)
        self.assertEqual(payload, page.evaluate.call_args.args[1]["payload"])
        page.evaluate.return_value = {"code": 30006}
        with self.assertRaises(ServiceError) as error:
            login_browser(page, "page", "login", payload, 20000)
        self.assertEqual(401, error.exception.status_code)

    def test_process_dispatches_exam_without_term(self):
        queue = Mock()
        with patch("FastAPI.jwxt_automation.os.setsid", create=True), patch("FastAPI.exam_queries.run_exam_pipeline", return_value={"exams": []}) as pipeline, patch.dict("os.environ"):
            _pipeline_process_entry(queue, {"operation": "exams", "username": "student", "encrypted_password": "encrypted"})
        pipeline.assert_called_once_with(username="student", encrypted_password="encrypted")
        self.assertTrue(queue.put.call_args.args[0]["ok"])

    def test_endpoint_accepts_no_term_and_uses_shared_executor(self):
        data = {"generated_at": "2026-11-15T08:00:00+08:00", "exams_complete": True, "exams": []}
        with patch("FastAPI.jwxt_automation.run_pipeline_isolated", return_value=data) as pipeline:
            response = TestClient(app).post("/api/jwxt/exams", json={"username": "exam-endpoint-test", "encrypted_password": "encrypted"})
        self.assertEqual({"success": True, "data": data}, response.json())
        self.assertEqual("exams", pipeline.call_args.kwargs["operation"])
        self.assertNotIn("year_term", pipeline.call_args.kwargs)
        self.assertEqual(422, TestClient(app).post("/api/jwxt/exams", json={"username": "student"}).status_code)


if __name__ == "__main__":
    unittest.main()
