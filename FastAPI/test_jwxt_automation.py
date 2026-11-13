import unittest
import os
import sys
import subprocess
import tempfile
import time
import threading
from pathlib import Path
from inspect import signature
from unittest.mock import Mock, patch

from FastAPI.main import app, health
from FastAPI.service_common import ServiceError
from pydantic import ValidationError
from fastapi.testclient import TestClient

from FastAPI.jwxt_automation import (
    JwxtAutomation,
    PipelineRequest,
    SlidingWindowRateLimiter,
    fetch_term_schedule_notices,
    run_pipeline,
    merge_and_filter_term_notices,
    _run_pipeline_isolated,
    _pipeline_process_entry,
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
    def test_unified_service_exposes_both_routers(self) -> None:
        paths = set(app.openapi()["paths"])

        self.assertIn("/health", paths)
        self.assertIn("/api/jwxt/term-schedule-notices", paths)
        self.assertNotIn("/api/calendar/term-overrides", paths)
        self.assertNotIn("/admin/calendar/publish", paths)

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
        with patch("FastAPI.jwxt_automation.JwxtAutomation") as client_class:
            client = client_class.return_value
            client.signed_urls = {"pending": "signed", "read": "signed"}
            client.fetch_all_by_kind.side_effect = [[], []]

            result = run_pipeline(
                username="student",
                encrypted_password="encrypted",
                year_term="2026-2027-1",
                env_name="prod",
            )

        self.assertNotIn("signed_urls", result)
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
                with patch("FastAPI.jwxt_automation.JwxtAutomation") as client_class:
                    client_class.return_value.fetch_all_by_kind.side_effect = results
                    with self.assertRaises(RuntimeError):
                        run_pipeline("student", "encrypted", "2026-2027-1", "test")




def hanging_process_tree(result_queue, kwargs):
    if os.name != "nt":
        os.setsid()
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(120)"])
    Path(kwargs["pid_file"]).write_text(f"{os.getpid()},{child.pid}")
    time.sleep(120)


def process_running(pid):
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel.OpenProcess.restype = wintypes.HANDLE
        kernel.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
        kernel.GetExitCodeProcess.restype = wintypes.BOOL
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        kernel.CloseHandle.restype = wintypes.BOOL
        handle = kernel.OpenProcess(0x1000, False, pid)
        if not handle:
            if ctypes.get_last_error() == 87:
                return False
            raise ctypes.WinError(ctypes.get_last_error())
        try:
            code = wintypes.DWORD()
            if not kernel.GetExitCodeProcess(handle, ctypes.byref(code)):
                raise ctypes.WinError(ctypes.get_last_error())
            return code.value == 259
        finally:
            if not kernel.CloseHandle(handle):
                raise ctypes.WinError(ctypes.get_last_error())
    try:
        os.kill(pid, 0)
        stat = Path(f"/proc/{pid}/stat")
        return not stat.exists() or stat.read_text().split()[2] != "Z"
    except ProcessLookupError:
        return False


class PipelineIntegrityTests(unittest.TestCase):
    def test_invalid_adjustment_dates_fail_before_complete_result(self):
        for bad in (None, 123, "", "2026-02-30 12:00:00", "bad"):
            with self.subTest(bad=bad):
                with self.assertRaisesRegex(ServiceError, "发布时间"):
                    merge_and_filter_term_notices([{"xxbt": "调课", "cjsj": bad}], [], "2026-2027-1")

    def test_non_adjustment_invalid_dates_are_ignored_and_adjustments_sorted(self):
        result = merge_and_filter_term_notices([
            {"xxbt": "普通通知", "cjsj": None},
            {"xxbt": "调课", "cjsj": "2026-10-02 10:00:00"},
            {"xxbt": "调课", "cjsj": "2025-10-02 10:00:00"},
            {"xxbt": "调课", "cjsj": "2026-10-01 10:00:00"},
        ], [], "2026-2027-1")
        self.assertEqual(["2026-10-01 10:00:00", "2026-10-02 10:00:00"], [n["published_at"] for n in result])

    def test_session_closed_when_login_or_notice_processing_fails(self):
        for phase in ("login", "fetch_all_by_kind"):
            with patch("FastAPI.jwxt_automation.JwxtAutomation") as factory:
                client = factory.return_value
                getattr(client, phase).side_effect = RuntimeError("failure")
                with self.assertRaises(RuntimeError):
                    run_pipeline("student", "encrypted", "2026-2027-1", "test")
                client.session.close.assert_called_once()

    def test_browser_closed_if_context_creation_fails(self):
        from types import ModuleType
        fake = ModuleType("playwright.sync_api")
        playwright = Mock()
        fake.sync_playwright = Mock(return_value=Mock(__enter__=Mock(return_value=playwright), __exit__=Mock(return_value=False)))
        fake.TimeoutError = TimeoutError
        browser = playwright.chromium.launch.return_value
        browser.new_context.side_effect = RuntimeError("context failed")
        client = JwxtAutomation("student", "encrypted", "test")
        try:
            with patch.object(client, "capture_signed_urls_requests", side_effect=RuntimeError("requests failed")), patch.dict(sys.modules, {"playwright.sync_api": fake}):
                with self.assertRaisesRegex(RuntimeError, "context failed"):
                    client.capture_signed_urls()
            browser.close.assert_called_once()
            self.assertTrue(playwright.chromium.launch.call_args.kwargs["chromium_sandbox"])
            self.assertTrue(playwright.chromium.launch.call_args.kwargs["headless"])
            self.assertNotIn("CALENDAR_ADMIN_TOKEN", playwright.chromium.launch.call_args.kwargs["env"])
        finally:
            client.session.close()

    def test_spawn_entry_handles_failure_without_school_access(self):
        with self.assertRaises(ServiceError) as error:
            _run_pipeline_isolated(_pipeline_process_entry, 10, {})
        self.assertEqual("pipeline_failed", error.exception.code)

    def test_entry_preserves_upstream_invalid_date_failure(self):
        result_queue = Mock()
        # Run the entry inline without changing this test process's POSIX group.
        with patch.dict(os.environ), patch("FastAPI.jwxt_automation.os.setsid", create=True), patch("FastAPI.jwxt_automation.run_pipeline", side_effect=ServiceError(502, "upstream_invalid_response", "invalid date")):
            _pipeline_process_entry(result_queue, {})
        self.assertEqual({"ok": False, "status": 502, "code": "upstream_invalid_response", "message": "invalid date"}, result_queue.put.call_args.args[0])

    def test_hard_timeout_reaps_real_worker_and_descendant(self):
        with tempfile.TemporaryDirectory() as folder:
            pid_file = Path(folder) / "pids"
            observed = []
            stop = threading.Event()
            def observe():
                while not stop.wait(0.02):
                    if pid_file.exists():
                        pids = [int(pid) for pid in pid_file.read_text().split(",")]
                        if all(process_running(pid) for pid in pids):
                            observed.extend(pids)
                            return
            watcher = threading.Thread(target=observe)
            watcher.start()
            try:
                with self.assertRaises(ServiceError) as error:
                    _run_pipeline_isolated(hanging_process_tree, 3, {"pid_file": str(pid_file)})
                self.assertEqual("pipeline_timeout", error.exception.code)
                self.assertEqual(2, len(observed), "must observe worker and descendant alive before timeout")
                for _ in range(30):
                    if not any(process_running(pid) for pid in observed):
                        break
                    time.sleep(0.1)
                self.assertFalse(any(process_running(pid) for pid in observed), observed)
            finally:
                stop.set()
                watcher.join()
                if pid_file.exists():
                    for pid in [int(value) for value in pid_file.read_text().split(",")]:
                        if process_running(pid):
                            if os.name == "nt":
                                subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True)
                            else:
                                os.kill(pid, 9)


if __name__ == "__main__":
    unittest.main()
