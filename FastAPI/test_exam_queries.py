import unittest
from contextlib import contextmanager
from unittest.mock import Mock, patch

from fastapi.testclient import TestClient
from playwright.sync_api import TimeoutError as BrowserTimeout

from FastAPI.exam_queries import EXAM_PAGE, normalize_exam_data, run_exam_pipeline
from FastAPI.jwxt_automation import _pipeline_process_entry, login_browser
from FastAPI.main import app
from FastAPI.service_common import ServiceError


def exam_row(**overrides):
    return {"kcmc": "高等数学", "kssj": "2026-12-20（09:00-11:00）",
            "cdxqmc": "两江", "cdmc": "A101", **overrides}


def exam_page(*rows, current=1, total=None, size=20):
    total = len(rows) if total is None else total
    return {"currentPage": current, "totalCount": total, "totalPage": (total + size - 1) // size,
            "showCount": size, "items": list(rows)}


class ExamParsingTests(unittest.TestCase):
    def parse(self, *rows):
        return normalize_exam_data(exam_page(*rows))

    def test_desktop_fields_map_without_inventing_a_building(self):
        row = self.parse(exam_row())[0]
        self.assertEqual("高等数学", row["course_name"])
        self.assertEqual("2026-12-20（09:00-11:00）", row["time_text"])
        self.assertEqual("2026-12-20T09:00:00+08:00", row["start_at"])
        self.assertEqual("2026-12-20T11:00:00+08:00", row["end_at"])
        self.assertEqual(("两江", "", "A101"), (row["campus"], row["building"], row["room"]))

    def test_normalized_keys_are_stable_and_duplicates_collapse(self):
        first, second = exam_row(), exam_row(kcmc=" 高等数学 ", cdmc="Ａ１０１")
        self.assertEqual(self.parse(first)[0]["key"], self.parse(second)[0]["key"])
        self.assertEqual(1, len(self.parse(first, second)))
        self.assertNotEqual(self.parse(first)[0]["key"], self.parse(exam_row(cdmc="A102"))[0]["key"])

    def test_unknown_or_invalid_times_retain_text_without_dates(self):
        for text in ("待安排", "", "2026-02-30(09:00-11:00)", "2026-12-20(11:00-09:00)"):
            with self.subTest(text=text):
                row = self.parse(exam_row(kssj=text))[0]
                self.assertEqual(text, row["time_text"])
                self.assertIsNone(row["start_at"])
                self.assertIsNone(row["end_at"])

    def test_empty_success_and_malformed_response_are_distinct(self):
        self.assertEqual([], self.parse())
        missing_campus = exam_row()
        del missing_campus["cdxqmc"]
        invalid = [{}, {**exam_page(), "items": None}, exam_page(None), exam_page(missing_campus),
                   exam_page(exam_row(cdmc=None)), exam_page(exam_row(kcmc=" ")),
                   {**exam_page(), "totalCount": "0"}]
        for body in invalid:
            with self.subTest(body=body), self.assertRaises(ServiceError):
                normalize_exam_data(body)


class ExamDesktopPipelineTests(unittest.TestCase):
    def setUp(self):
        playwright = self.enterContext(patch("playwright.sync_api.sync_playwright"))
        self.browser = playwright.return_value.__enter__.return_value.chromium.launch.return_value
        self.page = self.browser.new_context.return_value.new_page.return_value
        self.page.evaluate.return_value = {"code": 200}
        self.page.goto.side_effect = self.navigate

    def navigate(self, url, **kwargs):
        self.page.url = url
        return Mock(url=url, status=200, headers={})

    def run_pipeline(self, *bodies):
        remaining = iter(bodies)

        @contextmanager
        def expect_response(predicate, *, timeout):
            pending = Mock()
            yield pending
            body = next(remaining, BrowserTimeout("no next exam response"))
            if isinstance(body, Exception):
                raise body
            response = Mock(url=EXAM_PAGE, status=200, headers={})
            response.request.method = "POST"
            response.json.return_value = body
            self.assertTrue(predicate(response))
            pending.value = response

        self.page.expect_response.side_effect = expect_response
        return run_exam_pipeline(username="student", encrypted_password="encrypted")

    def test_desktop_session_uses_one_context_and_accepts_empty_result(self):
        result = self.run_pipeline(exam_page(current=0))
        self.assertEqual([], result["exams"])
        self.assertIs(result["exams_complete"], True)
        self.browser.new_context.assert_called_once_with()
        self.assertEqual("encrypted", self.page.evaluate.call_args.args[1]["payload"]["pwd"])
        self.assertEqual(EXAM_PAGE, self.page.goto.call_args.args[0])
        self.page.locator.assert_not_called()
        self.browser.close.assert_called_once()

    def test_accepts_exam_post_when_navigation_returns_none(self):
        def navigate(url, **kwargs):
            response = self.navigate(url, **kwargs)
            return None if url == EXAM_PAGE else response

        self.page.goto.side_effect = navigate
        result = self.run_pipeline(exam_page(exam_row()))
        self.assertEqual([("高等数学", "A101")],
                         [(row["course_name"], row["room"]) for row in result["exams"]])
        self.assertIs(result["exams_complete"], True)

    def test_queries_when_page_does_not_load_results_automatically(self):
        result = self.run_pipeline(BrowserTimeout("no automatic query"), exam_page(exam_row()))
        self.assertEqual(["A101"], [row["room"] for row in result["exams"]])
        self.page.locator.assert_called_once_with("#search_go")
        self.page.locator.return_value.click.assert_called_once()

    def test_collects_all_pages_before_marking_complete(self):
        result = self.run_pipeline(exam_page(exam_row(), total=3, size=1),
                                   exam_page(exam_row(cdmc="B202"), current=2, total=3, size=1),
                                   exam_page(exam_row(cdmc="C303"), current=3, total=3, size=1))
        self.assertEqual(["A101", "B202", "C303"], [row["room"] for row in result["exams"]])
        self.assertIs(result["exams_complete"], True)
        self.assertEqual(2, self.page.locator.return_value.click.call_count)
        self.page.locator.assert_called_with('#pager [id="next_pager"]')

    def test_missing_page_response_fails_instead_of_returning_partial_results(self):
        with self.assertRaises(ServiceError) as error:
            self.run_pipeline(exam_page(exam_row(), total=2, size=1))
        self.assertEqual((504, "pipeline_timeout"), (error.exception.status_code, error.exception.code))
        self.browser.close.assert_called_once()

    def test_repeated_or_incomplete_page_is_rejected(self):
        first = exam_page(exam_row(), total=2, size=1)
        for second in (first, {**first, "currentPage": 2}, exam_page(current=2, total=2, size=1)):
            with self.subTest(page=second):
                with self.assertRaises(ServiceError) as error:
                    self.run_pipeline(first, second)
                self.assertEqual((502, "upstream_invalid_response"), (error.exception.status_code, error.exception.code))


class ExamContractTests(unittest.TestCase):
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
