import os
import unittest
from unittest.mock import patch

from pydantic import ValidationError

from jwxt_automation import (
    PipelineRequest,
    ServiceError,
    SlidingWindowRateLimiter,
    _require_api_key,
)


class SecurityBoundaryTests(unittest.TestCase):
    def test_rate_limiter_rejects_requests_inside_window(self) -> None:
        limiter = SlidingWindowRateLimiter(limit=2, window_seconds=60)

        self.assertTrue(limiter.allow("client", now=0))
        self.assertTrue(limiter.allow("client", now=1))
        self.assertFalse(limiter.allow("client", now=2))
        self.assertTrue(limiter.allow("client", now=61))

    def test_api_key_is_fail_closed_when_not_configured(self) -> None:
        with patch.dict(
            os.environ,
            {"JWXT_REQUIRE_API_KEY": "true", "JWXT_API_KEYS": ""},
            clear=False,
        ):
            with self.assertRaises(ServiceError) as raised:
                _require_api_key("anything")

        self.assertEqual(raised.exception.status_code, 503)
        self.assertEqual(raised.exception.code, "service_not_configured")

    def test_api_key_accepts_one_of_rotatable_keys(self) -> None:
        old_key = "o" * 32
        new_key = "n" * 32
        with patch.dict(
            os.environ,
            {
                "JWXT_REQUIRE_API_KEY": "true",
                "JWXT_API_KEYS": f"{old_key},{new_key}",
            },
            clear=False,
        ):
            _require_api_key(new_key)
            with self.assertRaises(ServiceError) as raised:
                _require_api_key("wrong-key")

        self.assertEqual(raised.exception.status_code, 401)
        self.assertEqual(raised.exception.code, "unauthorized")

    def test_short_api_keys_are_rejected_as_misconfiguration(self) -> None:
        with patch.dict(
            os.environ,
            {"JWXT_REQUIRE_API_KEY": "true", "JWXT_API_KEYS": "too-short"},
            clear=False,
        ):
            with self.assertRaises(ServiceError) as raised:
                _require_api_key("too-short")

        self.assertEqual(raised.exception.code, "service_not_configured")

    def test_private_deployment_can_explicitly_disable_api_key(self) -> None:
        with patch.dict(
            os.environ,
            {"JWXT_REQUIRE_API_KEY": "false", "JWXT_API_KEYS": ""},
            clear=False,
        ):
            _require_api_key(None)

    def test_request_model_rejects_oversized_account(self) -> None:
        with self.assertRaises(ValidationError):
            PipelineRequest(
                username="u" * 65,
                encrypted_password="encrypted",
                year_term="2026-2027-1",
            )


if __name__ == "__main__":
    unittest.main()
