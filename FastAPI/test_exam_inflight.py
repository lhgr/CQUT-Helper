"""Real Uvicorn HTTP + spawned synthetic school worker; never calls the school."""

import concurrent.futures
import json
import os
import pathlib
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request
import uuid

from FastAPI import jwxt_automation as jwxt
from FastAPI.main import app


def synthetic_entry(result_queue, kwargs):
    if os.name != "nt":
        os.setsid()
    mode = kwargs.pop("synthetic_mode")
    jwxt.log_exam_query(kwargs.get("query_id"), "phase", kwargs["query_started_at"], phase="synthetic_worker")
    time.sleep(30 if mode == "timeout" else 1.2)
    if mode == "error":
        result_queue.put({"ok": False, "status": 502, "code": "upstream_unavailable", "message": "合成上游失败"})
    else:
        result_queue.put({"ok": True, "data": {"generated_at": "2026-11-15T00:00:00+08:00", "exams_complete": True, "exams": []}})


# Only the spawned test server selects a synthetic child target. The real
# run_pipeline_isolated / Queue / Process / timeout and HTTP handlers still run.
if os.getenv("CQUT_EXAM_SYNTHETIC_HTTP_TEST") == "1":
    _mode = "success"
    _real_runner = jwxt.run_pipeline_isolated
    jwxt._pipeline_process_entry = synthetic_entry

    def synthetic_runner(**kwargs):
        return _real_runner(synthetic_mode=_mode, **kwargs)

    jwxt.run_pipeline_isolated = synthetic_runner

    @app.post("/__test__/mode/{mode}")
    def configure_mode(mode: str):
        global _mode
        assert not jwxt._exam_inflight
        _mode = mode
        return {"active": len(jwxt._exam_inflight), "slots": jwxt._pipeline_slots._value}


class ExamInflightHttpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.log_path = pathlib.Path(cls.directory.name) / "uvicorn.log"
        cls.log_file = cls.log_path.open("w", encoding="utf-8")
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        cls.base = f"http://127.0.0.1:{port}"
        env = {**os.environ, "CQUT_EXAM_SYNTHETIC_HTTP_TEST": "1", "JWXT_PIPELINE_TIMEOUT_SEC": "10", "JWXT_RATE_LIMIT_PER_MINUTE": "600"}
        cls.server = subprocess.Popen([
            sys.executable, "-m", "uvicorn", "FastAPI.test_exam_inflight:app",
            "--host", "127.0.0.1", "--port", str(port), "--workers", "1", "--no-proxy-headers",
        ], cwd=pathlib.Path(__file__).resolve().parent.parent, env=env,
            stdout=cls.log_file, stderr=subprocess.STDOUT)
        for _ in range(100):
            try:
                urllib.request.urlopen(cls.base + "/health", timeout=.2).close()
                return
            except OSError:
                if cls.server.poll() is not None:
                    raise RuntimeError(cls.log_path.read_text(encoding="utf-8"))
                time.sleep(.1)
        cls.server.terminate()
        cls.server.wait(10)
        raise RuntimeError("Synthetic HTTP server failed to start")

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate()
        try:
            cls.server.wait(10)
        except subprocess.TimeoutExpired:
            cls.server.kill()
            cls.server.wait(5)
        cls.log_file.close()
        cls.directory.cleanup()

    def configure(self, mode):
        state = self.request("/__test__/mode/" + mode, {})[1]
        self.assertEqual({"active": 0, "slots": 2}, state)
        self.offset = len(self.log_path.read_text(encoding="utf-8"))
        return {"username": "synthetic-" + uuid.uuid4().hex, "encrypted_password": "synthetic-private-value"}

    def request(self, path, data, timeout=25):
        request = urllib.request.Request(self.base + path, data=json.dumps(data).encode(), headers={"Content-Type": "application/json"})
        try:
            response = urllib.request.urlopen(request, timeout=timeout)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            return response.status, json.load(response)

    def concurrent(self, payloads):
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(payloads)) as executor:
            return list(executor.map(lambda payload: self.request("/api/jwxt/exams", payload), payloads))

    def events(self):
        raw = self.log_path.read_text(encoding="utf-8")[self.offset:]
        self.assertNotIn("synthetic-private-value", raw)
        self.assertNotIn('"username"', raw)
        return [json.loads(line) for line in raw.splitlines() if line.startswith('{"operation":')]

    def assert_one_flight(self, terminal):
        events = self.events()
        self.assertEqual(1, sum(event["event"] == "start" for event in events))
        self.assertGreaterEqual(sum(event["event"] == "join" for event in events), 1)
        self.assertEqual(1, sum(event["event"] == terminal for event in events))
        self.assertEqual(1, sum(event.get("phase") == "synthetic_worker" for event in events))
        self.assertEqual(1, len({event["query_id"] for event in events}))

    def test_concurrent_success_shares_worker_and_does_not_cache_completed_result(self):
        payload = self.configure("success")
        # Eight callers exceed the six-per-account quota if joins are counted.
        results = self.concurrent([payload] * 8)
        self.assertTrue(all(result == results[0] for result in results))
        self.assertEqual(200, results[0][0])
        self.assert_one_flight("done")
        first_id = self.events()[0]["query_id"]
        self.offset = len(self.log_path.read_text(encoding="utf-8"))
        self.assertEqual(200, self.request("/api/jwxt/exams", payload)[0])
        self.assertNotEqual(first_id, self.events()[0]["query_id"])

    def test_failure_is_shared_and_next_call_can_run(self):
        payload = self.configure("error")
        results = self.concurrent([payload] * 3)
        self.assertTrue(all(result == results[0] for result in results))
        self.assertEqual(502, results[0][0])
        self.assert_one_flight("error")
        self.request("/__test__/mode/success", {})
        self.assertEqual(200, self.request("/api/jwxt/exams", payload)[0])

    def test_hard_timeout_is_shared_and_releases_map_and_slots(self):
        payload = self.configure("timeout")
        results = self.concurrent([payload] * 3)
        self.assertTrue(all(result == results[0] for result in results))
        self.assertEqual(504, results[0][0])
        self.assert_one_flight("error")
        self.assertEqual({"active": 0, "slots": 2}, self.request("/__test__/mode/success", {})[1])
        self.assertEqual(200, self.request("/api/jwxt/exams", payload)[0])

    def test_different_credentials_for_same_account_do_not_share_or_get_409(self):
        payload = self.configure("success")
        other = {**payload, "encrypted_password": "synthetic-other-value"}
        results = self.concurrent([payload, other])
        self.assertEqual([200, 200], [result[0] for result in results])
        starts = [event for event in self.events() if event["event"] == "start"]
        self.assertEqual(2, len(starts))
        self.assertEqual(2, len({event["query_id"] for event in starts}))

    def test_disconnected_leader_does_not_leave_a_residual_flight(self):
        payload = self.configure("success")
        with self.assertRaises(TimeoutError):
            self.request("/api/jwxt/exams", payload, timeout=.15)
        self.assertEqual(200, self.request("/api/jwxt/exams", payload)[0])
        self.assert_one_flight("done")
        self.assertEqual({"active": 0, "slots": 2}, self.request("/__test__/mode/success", {})[1])


if __name__ == "__main__":
    unittest.main()
