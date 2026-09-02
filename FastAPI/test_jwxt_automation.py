import unittest
from inspect import signature
from unittest.mock import patch

from pydantic import ValidationError

from jwxt_automation import (
    PipelineRequest,
    SlidingWindowRateLimiter,
    fetch_term_schedule_notices,
    health,
    run_pipeline,
)


class SecurityBoundaryTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
