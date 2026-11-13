import unittest
from inspect import signature
from unittest.mock import Mock, patch

from pydantic import ValidationError
from fastapi.testclient import TestClient

from jwxt_automation import (
    JwxtAutomation,
    PipelineRequest,
    SlidingWindowRateLimiter,
    app,
    fetch_term_schedule_notices,
    health,
    run_pipeline,
)


class NoticePaginationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.client = JwxtAutomation("student", "encrypted", "test")
        self.client.config.page_size = 2
        self.client.signed_urls = {"pending": "signed", "read": "signed"}
        self.client.capture_signed_urls = Mock()
        self.client.session.post = Mock()

    def respond_with(self, *pages) -> None:
        self.client.session.post.side_effect = [
            Mock(json=Mock(return_value=page)) for page in pages
        ]

    def test_fetches_every_page_to_declared_total(self) -> None:
        items = [{"id": "one"}, {"id": "two"}, {"id": "three"}]
        self.respond_with(
            {"items": items[:2], "totalResult": "3"},
            {"items": items[2:], "totalResult": 3},
        )

        self.assertEqual(items, self.client.fetch_all_by_kind("pending"))
        self.assertEqual("2", self.client.session.post.call_args.kwargs["data"]["queryModel.currentPage"])

    def test_declared_zero_is_a_successful_empty_result(self) -> None:
        self.respond_with({"items": [], "totalResult": 0})

        self.assertEqual([], self.client.fetch_all_by_kind("read"))

    def test_missing_or_invalid_items_retry_then_fail(self) -> None:
        for response in ({}, [], {"items": None}, {"items": {}}):
            with self.subTest(response=response):
                self.respond_with(response, response)
                self.client.capture_signed_urls.reset_mock()

                with self.assertRaises(RuntimeError):
                    self.client.fetch_all_by_kind("pending")

                self.client.capture_signed_urls.assert_called_once_with(headless=True)
                self.assertEqual(2, self.client.session.post.call_count)
                self.client.session.post.reset_mock()

    def test_invalid_items_can_recover_after_recapturing_signature(self) -> None:
        self.respond_with({}, {"items": [], "totalResult": 0})

        self.assertEqual([], self.client.fetch_all_by_kind("pending"))
        self.client.capture_signed_urls.assert_called_once_with(headless=True)

    def test_malformed_entries_or_totals_fail(self) -> None:
        for response in (
            {"items": [None], "totalResult": 1},
            {"items": ["notice"], "totalResult": 1},
            {"items": []},
            *({"items": [], "totalResult": total} for total in (-1, True, 1.5, "1.5", "invalid")),
            {"items": [{"id": "one"}], "totalResult": 0},
        ):
            with self.subTest(response=response):
                self.respond_with(response)
                with self.assertRaises(RuntimeError):
                    self.client.fetch_all_by_kind("pending")

    def test_short_or_empty_page_before_total_fails(self) -> None:
        for last_items in ([], [{"id": "three"}]):
            with self.subTest(last_items=last_items):
                self.respond_with(
                    {"items": [{"id": "one"}, {"id": "two"}], "totalResult": 4},
                    {"items": last_items, "totalResult": 4},
                )
                with self.assertRaises(RuntimeError):
                    self.client.fetch_all_by_kind("read")

    def test_changed_total_between_pages_fails(self) -> None:
        self.respond_with(
            {"items": [{"id": "one"}, {"id": "two"}], "totalResult": 3},
            {"items": [{"id": "three"}], "totalResult": 4},
        )

        with self.assertRaises(RuntimeError):
            self.client.fetch_all_by_kind("pending")


class SecurityBoundaryTests(unittest.TestCase):
    def test_jwxt_service_exposes_no_calendar_routes(self) -> None:
        paths = {route.path for route in app.routes}

        self.assertIn("/health", paths)
        self.assertIn("/api/jwxt/term-schedule-notices", paths)
        self.assertFalse(any(path.startswith("/api/calendar/") for path in paths))
        self.assertFalse(any(path.startswith("/admin/calendar") for path in paths))

    def test_jwxt_request_body_limit_is_20_kib(self) -> None:
        response = TestClient(app).post(
            "/api/jwxt/term-schedule-notices",
            content=b"x" * 20481,
            headers={"content-type": "application/json"},
        )

        self.assertEqual(413, response.status_code)
        self.assertEqual("request_too_large", response.json()["error"]["code"])

    def test_rate_limiter_rejects_requests_inside_window(self) -> None:
        limiter = SlidingWindowRateLimiter(limit=2, window_seconds=60)

        self.assertTrue(limiter.allow("client", now=0))
        self.assertTrue(limiter.allow("client", now=1))
        self.assertFalse(limiter.allow("client", now=2))
        self.assertTrue(limiter.allow("client", now=61))

    def test_notice_endpoint_no_longer_accepts_api_key(self) -> None:
        self.assertNotIn("api_key", signature(fetch_term_schedule_notices).parameters)

    def test_health_is_ready_without_auth_configuration(self) -> None:
        self.assertEqual(health(), {"status": "ok", "ready": True})

    def test_pipeline_marks_empty_notice_result_as_complete(self) -> None:
        with patch("jwxt_automation.JwxtAutomation") as client_class:
            client = client_class.return_value
            client.signed_urls = {"pending": "signed", "read": "signed"}
            client.fetch_all_by_kind.side_effect = [[], []]

            result = run_pipeline(
                username="student",
                encrypted_password="encrypted",
                year_term="2026-2027-1",
                env_name="prod",
            )

        self.assertTrue(result["term_schedule_notices_complete"])
        self.assertEqual(result["term_schedule_notices"], [])

    def test_request_model_rejects_oversized_account(self) -> None:
        with self.assertRaises(ValidationError):
            PipelineRequest(
                username="u" * 65,
                encrypted_password="encrypted",
                year_term="2026-2027-1",
            )

    def test_pipeline_does_not_return_complete_when_either_fetch_fails(self) -> None:
        for results in ([RuntimeError("pending failed")], [[], RuntimeError("read failed")]):
            with self.subTest(results=results):
                with patch("jwxt_automation.JwxtAutomation") as client_class:
                    client_class.return_value.fetch_all_by_kind.side_effect = results
                    with self.assertRaises(RuntimeError):
                        run_pipeline("student", "encrypted", "2026-2027-1", "test")


if __name__ == "__main__":
    unittest.main()
