import json
import hmac
import logging
import multiprocessing
import os
import queue
import re
import subprocess
import tempfile
import threading
import time
from collections import defaultdict, deque
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urljoin

import requests
from fastapi import FastAPI, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import HTMLResponse, JSONResponse, Response
try:
    # pydantic v2
    from pydantic import BaseModel, Field, field_validator
except ImportError:
    # pydantic v1 fallback
    from pydantic import BaseModel, Field, validator as field_validator
from requests.adapters import HTTPAdapter
from urllib3.util import Retry

from calendar_overrides import CalendarError, CalendarStore, default_store, validate_year_term

logger = logging.getLogger("jwxt_automation")

@dataclass
class EnvConfig:
    cas_login_page: str
    cas_do_login: str
    dbsy_page: str
    page_size: int = 15
    timeout_sec: int = 20


def build_env_config(env_name: str) -> EnvConfig:
    cas_login_page = os.getenv(
        "JWXT_CAS_LOGIN_PAGE",
        "https://uis.cqut.edu.cn/center-auth-server/officeHallApplicationCode/cas/login?service=https%3A%2F%2Fuis.cqut.edu.cn%2Fump%2Fcommon%2Flogin%2FauthSourceAuth%2Fauth%3FapplicationCode%3Dzc6v439",
    )
    cas_do_login = os.getenv("JWXT_CAS_DO_LOGIN", "https://uis.cqut.edu.cn/center-auth-server/sso/doLogin")
    dbsy_page = os.getenv("JWXT_DBSY_PAGE", "https://jwxt.cqut.edu.cn/jwglxt/xtgl/index_cxDbsy.html?flag=1")
    if env_name.lower() in {"dev", "test", "prod"}:
        return EnvConfig(cas_login_page=cas_login_page, cas_do_login=cas_do_login, dbsy_page=dbsy_page)
    raise ValueError(f"Unsupported env: {env_name}")


def parse_year_term_range(year_term: str) -> Tuple[datetime, datetime]:
    normalized = (year_term or "").strip()
    m = re.fullmatch(r"(\d{4})-(\d{4})-([12])", normalized)
    if not m:
        raise ValueError("year_term格式错误，应为YYYY-YYYY-1或YYYY-YYYY-2")

    start_year = int(m.group(1))
    end_year = int(m.group(2))
    term_index = int(m.group(3))
    if end_year != start_year + 1:
        raise ValueError("year_term学年不合法，结束学年应等于开始学年+1")

    if term_index == 1:
        return datetime(start_year, 9, 1), datetime(end_year, 1, 31, 23, 59, 59)
    return datetime(end_year, 2, 1), datetime(end_year, 8, 31, 23, 59, 59)


def parse_notice_fields(text: str) -> Dict[str, Optional[str]]:
    normalized = re.sub(r"\s+", "", text or "")
    pattern = re.compile(
        r"调课提醒:(?P<teacher>.+?)老师于(?P<old>.+?)上的(?P<course>.+?)课程调课到由(?P<teacher2>.+?)老师在(?P<new>.+?)上课"
    )
    m = pattern.search(normalized)
    if not m:
        return {
            "course_name": None,
            "teacher": None,
            "original_time": None,
            "original_classroom": None,
            "adjusted_time": None,
            "adjusted_classroom": None,
        }

    old_part = m.group("old")
    new_part = m.group("new")
    old_m = re.search(r"(?P<time>第.+?节)在(?P<room>.+)", old_part)
    new_m = re.search(r"(?P<time>第.+?节)(?:在)?(?P<room>.+)", new_part)
    return {
        "course_name": m.group("course"),
        "teacher": m.group("teacher"),
        "original_time": old_m.group("time") if old_m else old_part,
        "original_classroom": old_m.group("room") if old_m else None,
        "adjusted_time": new_m.group("time") if new_m else new_part,
        "adjusted_classroom": new_m.group("room") if new_m else None,
    }


class JwxtAutomation:
    def __init__(self, username: str, encrypted_password: str, env_name: str):
        self.username = username
        self.encrypted_password = encrypted_password
        self.config = build_env_config(env_name)
        self.session = requests.Session()
        self.session.headers.update(
            {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
                "Accept": "application/json, text/javascript, */*; q=0.01",
            }
        )
        retries = Retry(
            total=3,
            connect=3,
            read=3,
            backoff_factor=0.4,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["GET", "POST"],
        )
        adapter = HTTPAdapter(max_retries=retries)
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)
        self.signed_urls: Dict[str, str] = {}

    def _login_payload(self) -> Dict[str, Any]:
        return {
            "name": self.username,
            "pwd": self.encrypted_password,
            "verifyCode": None,
            "universityId": "100005",
            "loginType": "login",
        }

    def login(self) -> None:
        self.session.get(self.config.cas_login_page, timeout=self.config.timeout_sec)
        resp = self.session.post(
            self.config.cas_do_login,
            json=self._login_payload(),
            headers={
                "Content-Type": "application/json, application/json;charset=UTF-8",
                "Referer": self.config.cas_login_page,
                "Origin": "https://uis.cqut.edu.cn",
            },
            timeout=self.config.timeout_sec,
        )
        resp.raise_for_status()
        body = resp.json()
        if body.get("code") != 200:
            raise RuntimeError(f"统一认证失败: {body}")
        self.session.get(self.config.cas_login_page, allow_redirects=True, timeout=self.config.timeout_sec)
        page_resp = self.session.get(self.config.dbsy_page, allow_redirects=True, timeout=self.config.timeout_sec)
        if page_resp.status_code >= 400:
            page_resp.raise_for_status()

    def _extract_ts_material(self, html: str) -> Dict[str, str]:
        src_match = re.search(r'<script[^>]+src="(/eZ[^"]+\.js)"', html)
        if not src_match:
            raise RuntimeError("未找到反爬脚本地址")
        ts_match = re.search(r"\$_ts\.nsd=(\d+);.*?\$_ts\.cd=\"([^\"]+)\"", html, flags=re.S)
        if not ts_match:
            raise RuntimeError("未找到$_ts动态参数")
        return {"js_src": src_match.group(1), "nsd": ts_match.group(1), "cd": ts_match.group(2)}

    def _build_node_signer_script(self, nsd: str, cd: str, ts_js: str, target_url: str) -> str:
        inline_js = f"$_ts=window['$_ts']||{{}};$_ts.nsd={nsd};$_ts.cd={json.dumps(cd)};"
        return f"""
process.on('uncaughtException', (e) => {{
  console.log(JSON.stringify({{error: String(e && e.stack ? e.stack : e)}}));
  process.exit(1);
}});
global.window = global;
global.self = global;
global.top = global;
global.parent = global;
global.navigator = {{userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}};
global.location = {{href:'https://jwxt.cqut.edu.cn/jwglxt/xtgl/index_cxDbsy.html?flag=1', pathname:'/jwglxt/xtgl/index_cxDbsy.html', protocol:'https:'}};
global.history = {{length: 1}};
global.screen = {{width: 1920, height: 1080, availWidth: 1920, availHeight: 1040}};
global.performance = {{now: function(){{ return Date.now() % 100000; }}}};
global.localStorage = {{getItem:function(){{return null;}}, setItem:function(){{}}, removeItem:function(){{}}}};
global.sessionStorage = {{getItem:function(){{return null;}}, setItem:function(){{}}, removeItem:function(){{}}}};
global.document = {{
  cookie: '',
  referrer: '',
  location: global.location,
  getElementsByTagName: function(){{ return []; }},
  getElementById: function(){{ return null; }},
  querySelector: function(){{ return null; }},
  createElement: function(){{ return {{style:{{}}, setAttribute:function(){{}}, appendChild:function(){{}}, addEventListener:function(){{}} }}; }},
  documentElement: {{style:{{}}}},
  body: {{appendChild:function(){{}}, removeChild:function(){{}}}}
}};
var __lastUrl = {json.dumps(target_url)};
function __XHR(){{}}
__XHR.prototype.open = function(method, url){{ __lastUrl = url; }};
__XHR.prototype.send = function(){{}};
__XHR.prototype.setRequestHeader = function(){{}};
global.XMLHttpRequest = __XHR;
if (typeof global.atob === 'undefined') {{
  global.atob = function(s){{ return Buffer.from(String(s), 'base64').toString('binary'); }};
}}
if (typeof global.btoa === 'undefined') {{
  global.btoa = function(s){{ return Buffer.from(String(s), 'binary').toString('base64'); }};
}}
eval({json.dumps(inline_js)});
eval({json.dumps(ts_js)});
var xhr = new XMLHttpRequest();
xhr.open('POST', {json.dumps(target_url)}, true);
console.log(JSON.stringify({{signedUrl: __lastUrl}}));
"""

    def _sign_url_by_node(self, dbsy_html: str, target_url: str) -> str:
        material = self._extract_ts_material(dbsy_html)
        js_url = urljoin("https://jwxt.cqut.edu.cn", material["js_src"])
        ts_js = self.session.get(js_url, timeout=self.config.timeout_sec).text
        node_script = self._build_node_signer_script(
            nsd=material["nsd"],
            cd=material["cd"],
            ts_js=ts_js,
            target_url=target_url,
        )
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as f:
            f.write(node_script)
            node_file = f.name
        try:
            res = subprocess.run(["node", node_file], capture_output=True, text=True, timeout=20)
        finally:
            try:
                os.remove(node_file)
            except OSError:
                pass
        if res.returncode != 0:
            out = (res.stdout or "").strip()
            err = (res.stderr or "").strip()
            detail = err[:500] if err else out[:500]
            raise RuntimeError(f"node签名执行失败: {detail}")
        lines = [ln.strip() for ln in res.stdout.splitlines() if ln.strip()]
        if not lines:
            raise RuntimeError("node签名执行无输出")
        payload = json.loads(lines[-1])
        signed = payload.get("signedUrl")
        if not signed or "xqmeKlxm=" not in signed:
            raise RuntimeError(f"未生成xqmeKlxm签名URL: {signed}")
        if signed.startswith("/"):
            signed = urljoin("https://jwxt.cqut.edu.cn", signed)
        return signed

    def _probe_dbsy_query_url(self, url: str) -> bool:
        payload = self._dbsy_payload(sfyy=1, time_flag=0, page_no=1)
        resp = self.session.post(
            url,
            data=payload,
            headers={
                "X-Requested-With": "XMLHttpRequest",
                "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
                "Referer": self.config.dbsy_page,
                "Origin": "https://jwxt.cqut.edu.cn",
            },
            timeout=self.config.timeout_sec,
        )
        if resp.status_code != 200:
            return False
        try:
            data = resp.json()
        except ValueError:
            return False
        return isinstance(data, dict) and "items" in data

    def capture_signed_urls_requests(self) -> Dict[str, str]:
        page_resp = self.session.get(self.config.dbsy_page, allow_redirects=True, timeout=self.config.timeout_sec)
        page_resp.raise_for_status()
        html = page_resp.text
        base_target = "https://jwxt.cqut.edu.cn/jwglxt/xtgl/index_cxDbsy.html?doType=query"
        if self._probe_dbsy_query_url(base_target):
            signed = base_target
        else:
            signed = self._sign_url_by_node(dbsy_html=html, target_url=base_target)
        self.signed_urls = {"pending": signed, "read": signed}
        return self.signed_urls

    def capture_signed_urls(self, headless: bool = True) -> Dict[str, str]:
        req_exc: Optional[Exception] = None
        try:
            return self.capture_signed_urls_requests()
        except Exception as exc:
            req_exc = exc
        try:
            from playwright.sync_api import TimeoutError as PlaywrightTimeoutError
            from playwright.sync_api import sync_playwright
        except ModuleNotFoundError as exc:
            detail = str(req_exc) if req_exc else "未知错误"
            raise RuntimeError(f"纯requests签名失败，且缺少playwright降级能力。requests错误: {detail}") from exc
        captured: Dict[str, str] = {}
        encrypted_pwd = self.encrypted_password
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=headless)
            context = browser.new_context()
            page = context.new_page()

            def on_request(req: Any) -> None:
                url = req.url
                if "jwxt.cqut.edu.cn/jwglxt/xtgl/index_cxDbsy.html?xqmeKlxm=" in url and req.method == "POST":
                    post_data = req.post_data or ""
                    if "sfyy=1" in post_data:
                        captured["pending"] = url
                    if "sfyy=2" in post_data:
                        captured["read"] = url

            page.on("request", on_request)
            page.goto(self.config.cas_login_page, wait_until="domcontentloaded", timeout=self.config.timeout_sec * 1000)
            payload = {
                "name": self.username,
                "pwd": encrypted_pwd,
                "verifyCode": None,
                "universityId": "100005",
                "loginType": "login",
            }
            login_result = page.evaluate(
                """async ({url, payload}) => {
                    const r = await fetch(url, {
                        method: 'POST',
                        credentials: 'include',
                        headers: {'content-type': 'application/json, application/json;charset=UTF-8'},
                        body: JSON.stringify(payload)
                    });
                    return await r.json();
                }""",
                {"url": self.config.cas_do_login, "payload": payload},
            )
            if login_result.get("code") != 200:
                raise RuntimeError(f"浏览器登录失败: {login_result}")
            page.goto(self.config.cas_login_page, wait_until="networkidle", timeout=self.config.timeout_sec * 1000)
            page.goto(self.config.dbsy_page, wait_until="networkidle", timeout=self.config.timeout_sec * 1000)
            try:
                page.get_by_text("已阅事宜").click(timeout=5000)
            except PlaywrightTimeoutError:
                pass
            page.wait_for_timeout(2500)
            for c in context.cookies():
                self.session.cookies.set(c["name"], c["value"], domain=c.get("domain"), path=c.get("path"))
            browser.close()
        if "pending" not in captured or "read" not in captured:
            raise RuntimeError(f"未能捕获完整签名URL: {captured}")
        self.signed_urls = captured
        return captured

    def _dbsy_payload(self, sfyy: int, time_flag: int, page_no: int) -> Dict[str, Any]:
        return {
            "flag": "1",
            "sfyy": str(sfyy),
            "_search": "false",
            "nd": str(int(datetime.now().timestamp() * 1000)),
            "queryModel.showCount": str(self.config.page_size),
            "queryModel.currentPage": str(page_no),
            "queryModel.sortName": "cjsj ",
            "queryModel.sortOrder": "desc",
            "time": str(time_flag),
        }

    def fetch_all_by_kind(self, kind: str) -> List[Dict[str, Any]]:
        if kind not in {"pending", "read"}:
            raise ValueError("kind必须是pending或read")
        if kind not in self.signed_urls:
            raise RuntimeError("签名URL未初始化")
        sfyy = 1 if kind == "pending" else 2
        time_flag = 0 if kind == "pending" else 1
        url = self.signed_urls[kind]
        all_items: List[Dict[str, Any]] = []
        page_no = 1
        total = None
        while total is None or len(all_items) < total:
            payload = self._dbsy_payload(sfyy=sfyy, time_flag=time_flag, page_no=page_no)
            data = None
            for attempt in range(2):
                resp = self.session.post(
                    url,
                    data=payload,
                    headers={
                        "X-Requested-With": "XMLHttpRequest",
                        "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
                        "Referer": self.config.dbsy_page,
                        "Origin": "https://jwxt.cqut.edu.cn",
                    },
                    timeout=self.config.timeout_sec,
                )
                resp.raise_for_status()
                data = resp.json()
                if "items" in data:
                    break
                if attempt == 0:
                    self.capture_signed_urls(headless=True)
                    url = self.signed_urls[kind]
            if data is None:
                raise RuntimeError("拉取待阅/已阅数据失败")
            items = data.get("items", [])
            if total is None:
                total = int(data.get("totalResult", len(items)))
            if not items:
                break
            all_items.extend(items)
            if len(items) < self.config.page_size:
                break
            page_no += 1
        return all_items


def merge_and_filter_term_notices(
    pending_items: List[Dict[str, Any]],
    read_items: List[Dict[str, Any]],
    year_term: str,
) -> List[Dict[str, Any]]:
    merged = pending_items + read_items
    merged.sort(key=lambda x: x.get("cjsj", ""))
    start, end = parse_year_term_range(year_term)
    results: List[Dict[str, Any]] = []
    for item in merged:
        title = item.get("xxbt", "") or ""
        content = item.get("xxnr", "") or ""
        if "调课" not in title and "调课" not in content:
            continue
        cjsj = item.get("cjsj", "")
        try:
            published_at = datetime.strptime(cjsj, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            continue
        if not (start <= published_at <= end):
            continue
        parsed = parse_notice_fields(content or title)
        results.append(
            {
                "notice_id": item.get("id"),
                "status": "已阅" if str(item.get("clzt")) == "2" else "待阅",
                "published_at": cjsj,
                "title": title,
                "content": content,
                "course_name": parsed["course_name"],
                "teacher": parsed["teacher"],
                "original_time": parsed["original_time"],
                "original_classroom": parsed["original_classroom"],
                "adjusted_time": parsed["adjusted_time"],
                "adjusted_classroom": parsed["adjusted_classroom"],
            }
        )
    return results


def run_pipeline(
    username: str,
    encrypted_password: str,
    year_term: str,
    env_name: str,
    headless: bool = True,
) -> Dict[str, Any]:
    client = JwxtAutomation(
        username=username,
        encrypted_password=encrypted_password,
        env_name=env_name,
    )
    client.login()
    client.capture_signed_urls(headless=headless)
    pending = client.fetch_all_by_kind("pending")
    read = client.fetch_all_by_kind("read")
    notices = merge_and_filter_term_notices(pending, read, year_term=year_term)

    result = {
        "env": env_name,
        "year_term": year_term,
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "signed_urls": client.signed_urls,
        "counts": {
            "pending_total": len(pending),
            "read_total": len(read),
            "term_schedule_notice_total": len(notices),
        },
        "term_schedule_notices_complete": True,
        "term_schedule_notices": notices,
    }
    return result


class PipelineRequest(BaseModel):
    username: str = Field(..., min_length=1, max_length=64)
    encrypted_password: str = Field(..., min_length=1, max_length=16384)
    year_term: str = Field(..., pattern=r"^\d{4}-\d{4}-[12]$")
    env: str = Field(default="prod")
    headless: bool = True

    @field_validator("env")
    @classmethod
    def validate_env(cls, value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in {"dev", "test", "prod"}:
            raise ValueError("env必须是dev、test或prod")
        return normalized

    @field_validator("year_term")
    @classmethod
    def validate_year_term(cls, value: str) -> str:
        normalized = value.strip()
        parse_year_term_range(normalized)
        return normalized


class CalendarNoticeRequest(BaseModel):
    year_term: str = Field(..., pattern=r"^\d{4}-\d{4}-[12]$")
    title: str = Field(..., min_length=1, max_length=256)
    body: str = Field(..., min_length=1, max_length=60000)

    @field_validator("year_term")
    @classmethod
    def validate_calendar_year_term(cls, value: str) -> str:
        return validate_year_term(value)


class CalendarOverrideRequest(BaseModel):
    year_term: str = Field(..., pattern=r"^\d{4}-\d{4}-[12]$")
    date: str = Field(..., min_length=10, max_length=10)
    action: str = Field(..., pattern=r"^(upsert|suppress)$")
    kind: Optional[str] = None
    schedule_date: Optional[str] = None
    label: Optional[str] = None

    @field_validator("year_term")
    @classmethod
    def validate_override_year_term(cls, value: str) -> str:
        return validate_year_term(value)


class CalendarPublishRequest(BaseModel):
    year_term: str = Field(..., pattern=r"^\d{4}-\d{4}-[12]$")

    @field_validator("year_term")
    @classmethod
    def validate_publish_year_term(cls, value: str) -> str:
        return validate_year_term(value)


class ServiceError(Exception):
    def __init__(self, status_code: int, code: str, message: str):
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message


class SlidingWindowRateLimiter:
    def __init__(self, limit: int, window_seconds: int):
        self.limit = max(1, limit)
        self.window_seconds = max(1, window_seconds)
        self._events: Dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def allow(self, identity: str, now: Optional[float] = None) -> bool:
        current = time.monotonic() if now is None else now
        cutoff = current - self.window_seconds
        with self._lock:
            if len(self._events) > 4096:
                stale_identities = [
                    key
                    for key, values in self._events.items()
                    if not values or values[-1] <= cutoff
                ]
                for key in stale_identities:
                    self._events.pop(key, None)
            events = self._events[identity]
            while events and events[0] <= cutoff:
                events.popleft()
            if len(events) >= self.limit:
                return False
            events.append(current)
            if not events:
                self._events.pop(identity, None)
            return True


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _env_int(name: str, default: int, minimum: int, maximum: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except ValueError:
        value = default
    return max(minimum, min(maximum, value))


def _client_identity(request: Request) -> str:
    if _env_bool("JWXT_TRUST_PROXY_HEADERS", False):
        forwarded = request.headers.get("x-forwarded-for", "")
        if forwarded:
            return forwarded.split(",", 1)[0].strip()
    return request.client.host if request.client is not None else "unknown"


def _pipeline_process_entry(result_queue: Any, kwargs: Dict[str, Any]) -> None:
    try:
        result_queue.put({"ok": True, "data": run_pipeline(**kwargs)})
    except requests.HTTPError as exc:
        status_code = exc.response.status_code if exc.response is not None else None
        if status_code == 403:
            result_queue.put(
                {
                    "ok": False,
                    "status": 403,
                    "code": "upstream_closed",
                    "message": "上游接口夜间关闭，请白天时段再试",
                }
            )
        else:
            logger.exception("upstream HTTP request failed")
            result_queue.put(
                {
                    "ok": False,
                    "status": 502,
                    "code": "upstream_unavailable",
                    "message": "上游教务服务暂时不可用",
                }
            )
    except requests.RequestException:
        logger.exception("upstream request failed")
        result_queue.put(
            {
                "ok": False,
                "status": 502,
                "code": "upstream_unavailable",
                "message": "上游教务服务暂时不可用",
            }
        )
    except ValueError as exc:
        result_queue.put(
            {
                "ok": False,
                "status": 400,
                "code": "invalid_request",
                "message": str(exc),
            }
        )
    except Exception:
        logger.exception("isolated pipeline failed")
        result_queue.put(
            {
                "ok": False,
                "status": 500,
                "code": "pipeline_failed",
                "message": "调课查询处理失败",
            }
        )


def run_pipeline_isolated(**kwargs: Any) -> Dict[str, Any]:
    timeout_seconds = _env_int("JWXT_PIPELINE_TIMEOUT_SEC", 90, 10, 300)
    context = multiprocessing.get_context("spawn")
    result_queue = context.Queue(maxsize=1)
    process = context.Process(
        target=_pipeline_process_entry,
        args=(result_queue, kwargs),
        daemon=True,
    )
    process.start()
    deadline = time.monotonic() + timeout_seconds
    outcome: Optional[Dict[str, Any]] = None
    while time.monotonic() < deadline:
        remaining = max(0.01, deadline - time.monotonic())
        try:
            outcome = result_queue.get(timeout=min(0.25, remaining))
            break
        except queue.Empty:
            if not process.is_alive():
                break

    if outcome is None and process.is_alive():
        process.terminate()
        process.join(5)
        if process.is_alive():
            process.kill()
            process.join(2)
        result_queue.close()
        raise ServiceError(504, "pipeline_timeout", "调课查询超时，请稍后重试")

    process.join(5)
    if outcome is None:
        try:
            outcome = result_queue.get(timeout=1)
        except queue.Empty as exc:
            raise ServiceError(500, "pipeline_failed", "调课查询处理失败") from exc
        finally:
            result_queue.close()
    else:
        result_queue.close()

    if outcome.get("ok") is True:
        return outcome["data"]
    raise ServiceError(
        int(outcome.get("status", 500)),
        str(outcome.get("code", "pipeline_failed")),
        str(outcome.get("message", "调课查询处理失败")),
    )


_rate_limiter = SlidingWindowRateLimiter(
    limit=_env_int("JWXT_RATE_LIMIT_PER_MINUTE", 12, 1, 600),
    window_seconds=60,
)
_pipeline_slots = threading.BoundedSemaphore(
    _env_int("JWXT_MAX_CONCURRENT_PIPELINES", 2, 1, 16)
)

app = FastAPI(title="JWXT Automation API", version="1.1.0")


def _calendar_store() -> CalendarStore:
    """Return the process-local calendar store.

    Keeping the store on ``app.state`` makes the database location explicit in
    tests and avoids opening a connection (or creating the database file) when
    the application module is merely imported.
    """
    store = getattr(app.state, "calendar_store", None)
    configured_path = os.getenv("CALENDAR_DB_PATH")
    expected_path = str(Path(configured_path)) if configured_path else str(Path(__file__).with_name("calendar.db"))
    if store is None or str(getattr(store, "db_path", "")) != expected_path:
        store = default_store()
        app.state.calendar_store = store
    return store


def _require_calendar_admin(request: Request) -> None:
    """Authenticate administration endpoints with the configured bearer token."""
    configured = os.getenv("CALENDAR_ADMIN_TOKEN", "").strip()
    if not configured:
        raise ServiceError(503, "calendar_admin_unconfigured", "校历管理接口尚未配置访问令牌")
    authorization = request.headers.get("authorization", "")
    scheme, _, supplied = authorization.partition(" ")
    if scheme.lower() != "bearer" or not supplied.strip() or not hmac.compare_digest(
        supplied.strip(), configured
    ):
        raise ServiceError(401, "calendar_admin_unauthorized", "校历管理接口访问令牌无效")


def _calendar_error(exc: CalendarError) -> ServiceError:
    return ServiceError(400, "calendar_invalid", str(exc))


_CALENDAR_ADMIN_HTML = """<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>校历发布台</title>
<style>
:root{--ink:#16213b;--muted:#6b7892;--line:#e6eaf2;--bg:#f5f7fb;--card:#fff;--brand:#4967e8;--brand2:#6d4de8;--ok:#14866d;--warn:#b66b00;--bad:#c44153;--shadow:0 10px 30px #25365d12}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC",sans-serif}button,input,textarea,select{font:inherit}button{border:0;border-radius:9px;padding:9px 14px;cursor:pointer;background:#eef1f8;color:var(--ink);font-weight:600}button:hover{filter:brightness(.97)}button.primary{background:linear-gradient(135deg,var(--brand),var(--brand2));color:#fff}button.danger{color:var(--bad);background:#fff0f2}button:disabled{opacity:.45;cursor:not-allowed}.shell{max-width:1180px;margin:auto;padding:25px 20px 60px}.top{display:flex;align-items:center;justify-content:space-between;gap:18px;margin-bottom:24px}.brand{display:flex;align-items:center;gap:12px}.logo{width:42px;height:42px;border-radius:13px;background:linear-gradient(135deg,var(--brand),var(--brand2));color:#fff;display:grid;place-items:center;font-size:22px}.brand h1{font-size:21px;margin:0}.brand p{margin:2px 0 0;color:var(--muted)}.controls{display:flex;align-items:center;gap:8px}.field{background:var(--card);border:1px solid var(--line);border-radius:9px;padding:9px 11px;outline:0}.field:focus{border-color:var(--brand);box-shadow:0 0 0 3px #4967e81a}.term{width:145px}.token{width:190px}.grid{display:grid;grid-template-columns:minmax(0,1.4fr) minmax(320px,.8fr);gap:18px}.stack{display:grid;gap:18px;align-content:start}.card{background:var(--card);border:1px solid var(--line);border-radius:16px;box-shadow:var(--shadow);padding:20px}.card h2{font-size:16px;margin:0 0 5px}.sub{color:var(--muted);margin:0 0 16px}.section-head{display:flex;justify-content:space-between;align-items:start;gap:12px;margin-bottom:15px}.badge{display:inline-flex;border-radius:99px;padding:4px 9px;font-size:12px;font-weight:700;background:#edf0f8;color:var(--muted)}.badge.ok{background:#e6f7f1;color:var(--ok)}.badge.bad{background:#fff0f2;color:var(--bad)}.summary{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-bottom:16px}.metric{background:#f7f8fc;border-radius:11px;padding:12px}.metric b{display:block;font-size:21px}.metric.meta{grid-column:span 3;padding:8px 10px}.metric.meta b{font-size:12px;line-height:1.35;word-break:break-word;overflow-wrap:anywhere}.metric span{color:var(--muted);font-size:12px}.table-wrap{overflow:auto}.days{width:100%;border-collapse:collapse}.days th,.days td{text-align:left;padding:9px 8px;border-bottom:1px solid var(--line);white-space:nowrap}.days th{font-size:12px;color:var(--muted)}.days .holiday{color:var(--bad)}.days .teaching{color:var(--ok)}.notice{border:1px solid var(--line);border-radius:12px;padding:14px;margin-top:10px}.notice-top{display:flex;justify-content:space-between;gap:8px}.notice h3{font-size:14px;margin:0}.notice small{color:var(--muted)}.notice-actions{display:flex;gap:6px}.notice-actions button{padding:5px 9px;font-size:12px}.issues{color:var(--bad);font-size:12px;margin:7px 0}.editor label,.override label{display:block;font-size:12px;color:var(--muted);margin:11px 0 5px}.editor input,.editor textarea,.override input,.override select{width:100%}.editor textarea{min-height:185px;resize:vertical}.actions{display:flex;flex-wrap:wrap;gap:8px;margin-top:15px}.override-grid{display:grid;grid-template-columns:1fr 1fr;gap:4px 12px}.preview-status{display:flex;align-items:center;justify-content:space-between;gap:8px;padding:11px 13px;border-radius:10px;background:#f7f8fc;margin:14px 0}.diff{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}.diff-box{border:1px solid var(--line);border-radius:10px;padding:10px}.diff-box b{display:block;font-size:18px}.diff-box span{color:var(--muted);font-size:12px}.alert{padding:10px 12px;border-radius:10px;margin-top:9px;font-size:13px}.alert.bad{background:#fff0f2;color:var(--bad)}.alert.warn{background:#fff6e4;color:var(--warn)}.empty{text-align:center;color:var(--muted);padding:25px 8px}.muted{color:var(--muted)}.toast{position:fixed;right:20px;bottom:20px;background:#1f2a44;color:#fff;padding:11px 16px;border-radius:10px;box-shadow:var(--shadow);opacity:0;transform:translateY(10px);transition:.2s;pointer-events:none}.toast.show{opacity:1;transform:none}.loading{position:fixed;inset:0;background:#16213b22;display:grid;place-items:center;z-index:5}.loading[hidden]{display:none}.loading span{background:#fff;padding:15px 20px;border-radius:12px;box-shadow:var(--shadow)}@media(max-width:800px){.top{align-items:stretch;flex-direction:column}.controls{flex-wrap:wrap}.token{flex:1;min-width:160px}.grid{grid-template-columns:1fr}.summary{grid-template-columns:repeat(3,1fr)}.card{padding:16px}}@media(max-width:480px){.summary,.diff{grid-template-columns:1fr 1fr}.summary .metric.meta{grid-column:1/-1}.summary .metric:last-child{grid-column:1/-1}}
</style></head><body><div class="shell"><header class="top"><div class="brand"><div class="logo">历</div><div><h1>假期与调休发布台</h1><p>整理通知，确认草稿后发布校历快照</p></div></div><div class="controls"><input id="term" class="field term" value="2026-2027-1" aria-label="学期"><input id="token" class="field token" type="password" placeholder="管理令牌" autocomplete="off" aria-label="管理令牌"><button onclick="refreshAll()">刷新</button></div></header><main class="grid"><div class="stack"><section class="card"><div class="section-head"><div><h2>已发布校历</h2><p class="sub">客户端当前正在使用的版本</p></div><span id="publish-badge" class="badge">尚未加载</span></div><div id="published-summary" class="summary"></div><div id="published-table" class="table-wrap"><div class="empty">点击“刷新”查看已发布内容</div></div></section><section class="card"><div class="section-head"><div><h2>通知资料</h2><p class="sub">解析学校通知，生成可发布的候选日期</p></div><button onclick="newNotice()">新建通知</button></div><div id="notices"><div class="empty">正在加载通知…</div></div></section><section class="card editor"><h2 id="editor-heading">新建通知</h2><p class="sub">原文会保存在本地管理库中，解析结果用于草稿。</p><label for="title">通知标题</label><input id="title" class="field" placeholder="例如：2026年国庆节放假安排通知"><label for="body">通知正文</label><textarea id="body" class="field" placeholder="粘贴学校通知正文"></textarea><div class="actions"><button class="primary" onclick="saveNotice()">保存并解析</button><button onclick="clearEditor()">清空</button></div></section></div><div class="stack"><section class="card override"><div class="section-head"><div><h2>人工覆盖</h2><p class="sub">修正单个日期，不必改动原通知</p></div></div><div class="override-grid"><div><label for="override-date">实际日期</label><input id="override-date" class="field" type="date"></div><div><label for="override-action">动作</label><select id="override-action" class="field"><option value="upsert">新增 / 修改</option><option value="suppress">屏蔽该日</option></select></div><div id="override-kind-field"><label for="override-kind">类型</label><select id="override-kind" class="field"><option value="holiday">放假</option><option value="teaching_day">调休上课</option></select></div><div id="override-source-field"><label for="override-source">课表来源日期</label><input id="override-source" class="field" type="date"></div></div><div id="override-label-field"><label for="override-label">说明</label><input id="override-label" class="field" value="人工调整"></div><div class="actions"><button class="primary" onclick="setOverride()">保存覆盖</button><button class="danger" onclick="removeOverride()">移除该日期覆盖</button></div></section><section class="card"><div class="section-head"><div><h2>草稿预览</h2><p class="sub">发布前检查变化、冲突与解析完整性</p></div><button onclick="preview()">重新预览</button></div><div id="preview"><div class="empty">点击“重新预览”查看草稿</div></div><div class="actions"><button id="publish-btn" class="primary" disabled onclick="publish()">发布当前草稿</button></div></section></div></main></div><div id="toast" class="toast" role="status"></div><div id="loading" class="loading" hidden><span>正在处理…</span></div><script>
const $=id=>document.getElementById(id);let notices=[];let editingId=null;let lastPreview=null;let pending=0;const tokenKey='calendar-admin-token';$('token').value=sessionStorage.getItem(tokenKey)||'';$('token').addEventListener('change',()=>sessionStorage.setItem(tokenKey,$('token').value));function escapeHtml(value){return String(value??'').replace(/[&<>\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[c]));}function term(){return $('term').value.trim()}function headers(){return {'Content-Type':'application/json','Authorization':'Bearer '+$('token').value.trim()}}function toast(message,bad=false){const el=$('toast');el.textContent=message;el.style.background=bad?'#c44153':'#1f2a44';el.classList.add('show');setTimeout(()=>el.classList.remove('show'),3000)}function busy(on){pending=Math.max(0,pending+(on?1:-1));$('loading').hidden=pending<=0}async function call(url,options={}){busy(true);try{const requestOptions={...options};delete requestOptions.auth;const authHeaders=options.auth===false?{'Content-Type':'application/json'}:headers();const r=await fetch(url,{...requestOptions,headers:{...authHeaders,...(options.headers||{})}});const text=await r.text();let data;try{data=JSON.parse(text)}catch(_){data={success:false,error:{message:text.replace(/<[^>]*>/g,' ').replace(/\\s+/g,' ').trim().slice(0,160)||('HTTP '+r.status)}}}if(!r.ok||data.success===false){const e=new Error(data.error?.message||('请求失败（HTTP '+r.status+'）'));e.status=r.status;if(r.status!==404)toast(e.message,true);throw e}return data}catch(e){if(!e.status)toast(e.message,true);throw e}finally{busy(false)}}
function dateLabel(item){return item.kind==='holiday'?'放假':'调休上课'}function renderDays(days){if(!days.length)return '<div class="empty">暂无已发布日期</div>';return '<table class="days"><thead><tr><th>日期</th><th>安排</th><th>说明</th><th>课表来源</th></tr></thead><tbody>'+days.map(d=>'<tr><td>'+escapeHtml(d.date)+'</td><td class="'+(d.kind==='holiday'?'holiday':'teaching')+'">'+escapeHtml(dateLabel(d))+'</td><td>'+escapeHtml(d.label||'—')+'</td><td>'+escapeHtml(d.schedule_date||'—')+'</td></tr>').join('')+'</tbody></table>'}function renderPublished(snapshot){if(!snapshot){$('publish-badge').textContent='尚未发布';$('publish-badge').className='badge bad';$('published-summary').innerHTML='';$('published-table').innerHTML='<div class="empty">该学期还没有发布快照</div>';return}const days=snapshot.days||[];const revision=String(snapshot.revision||'');$('publish-badge').textContent='已发布';$('publish-badge').title=revision;$('publish-badge').className='badge ok';$('published-summary').innerHTML='<div class="metric"><b>'+days.length+'</b><span>日期规则</span></div><div class="metric"><b>'+days.filter(d=>d.kind==='holiday').length+'</b><span>放假</span></div><div class="metric"><b>'+days.filter(d=>d.kind==='teaching_day').length+'</b><span>调休上课</span></div><div class="metric meta"><b>'+escapeHtml(snapshot.generated_at||'—')+'</b><span>发布时间</span></div><div class="metric meta"><b>'+escapeHtml(revision||'—')+'</b><span>revision</span></div>';$('published-table').innerHTML=renderDays(days)}async function loadPublished(){try{const data=await call('/api/calendar/term-overrides?year_term='+encodeURIComponent(term()),{auth:false});renderPublished(data&&data.data?data.data:data)}catch(e){if(e.status===404)renderPublished(null);else $('published-table').innerHTML='<div class="empty">加载已发布快照失败，请检查服务状态</div>'}}
function renderNotices(){if(!notices.length){$('notices').innerHTML='<div class="empty">还没有通知，先粘贴一份学校通知吧</div>';return}$('notices').innerHTML=notices.map(n=>'<article class="notice"><div class="notice-top"><div><h3>'+escapeHtml(n.title||'无标题')+'</h3><small>'+escapeHtml(n.updated_at||'')+' · '+n.candidates.length+' 条日期候选</small></div><div class="notice-actions"><button onclick="loadNotice('+Number(n.id)+')">编辑</button><button class="danger" onclick="deleteNotice('+Number(n.id)+')">删除</button></div></div>'+(n.parse_complete?'<span class="badge ok">解析完整</span>':'<div class="issues">解析未完成：'+escapeHtml((n.parse_issues||[]).join('；'))+'</div>')+'</article>').join('')}async function listNotices(){try{const data=await call('/admin/calendar/notices?year_term='+encodeURIComponent(term()));notices=data.data||[];renderNotices()}catch(_){}}function newNotice(){editingId=null;$('editor-heading').textContent='新建通知';$('title').value='';$('body').value='';document.querySelector('.editor .actions button:last-child').textContent='清空'}function clearEditor(){newNotice()}function loadNotice(id){const n=notices.find(item=>item.id===id);if(!n)return;editingId=n.id;$('editor-heading').textContent='编辑通知 #'+n.id;document.querySelector('.editor .actions button:last-child').textContent='取消编辑';$('title').value=n.title;$('body').value=n.body;$('body').scrollIntoView({behavior:'smooth',block:'center'})}async function saveNotice(){const payload={year_term:term(),title:$('title').value.trim(),body:$('body').value};try{await call(editingId?'/admin/calendar/notices/'+editingId:'/admin/calendar/notices',{method:editingId?'PUT':'POST',body:JSON.stringify(payload)});toast(editingId?'通知已更新':'通知已解析');newNotice();await listNotices();await preview()}catch(_){} }async function deleteNotice(id){if(!confirm('确定删除这条通知吗？'))return;try{await call('/admin/calendar/notices/'+id,{method:'DELETE'});toast('通知已删除');if(editingId===id)newNotice();await listNotices();await preview()}catch(_){}}
function ruleText(rule){if(!rule)return '无';return (rule.kind==='holiday'?'放假':'调休上课')+' · '+(rule.label||'—')+(rule.schedule_date?' · 课表 '+rule.schedule_date:'')}function renderPreview(p){lastPreview=p;$('publish-btn').disabled=!p.publishable||!p.changed;const diff=p.diff||{added:[],changed:[],removed:[]};const detail=(items,mode)=>items.length?'<ul>'+items.map(x=>'<li><b>'+escapeHtml(x.date)+'</b>：'+(mode==='removed'?escapeHtml(ruleText(x.before)):mode==='added'?escapeHtml(ruleText(x.after)):escapeHtml(ruleText(x.before))+' → '+escapeHtml(ruleText(x.after)))+'</li>').join('')+'</ul>':'<span class="muted">无</span>';const conflicts=p.conflicts||[],incomplete=p.incomplete_notices||[];$('preview').innerHTML='<div class="preview-status"><span>草稿 '+(p.publishable?'可以发布':'暂不可发布')+'</span><span class="badge '+(p.changed?'':'ok')+'">'+(p.changed?'有变更':'与已发布一致')+'</span></div><div class="diff"><div class="diff-box"><b>'+diff.added.length+'</b><span>新增日期</span></div><div class="diff-box"><b>'+diff.changed.length+'</b><span>调整日期</span></div><div class="diff-box"><b>'+diff.removed.length+'</b><span>移除日期</span></div></div><div class="alert"><b>新增规则</b>'+detail(diff.added,'added')+'</div><div class="alert"><b>调整规则</b>'+detail(diff.changed,'changed')+'</div><div class="alert"><b>移除规则</b>'+detail(diff.removed,'removed')+'</div>'+(conflicts.length?'<div class="alert bad"><b>日期冲突</b>'+conflicts.map(c=>'<div>'+escapeHtml(c.date)+'：'+c.candidates.map(ruleText).map(escapeHtml).join('；')+'</div>').join('')+'</div>':'')+(incomplete.length?'<div class="alert warn"><b>解析未完成</b>'+incomplete.map(n=>'<div>'+escapeHtml(n.title||('通知 #'+n.id))+'：'+escapeHtml((n.parse_issues||[]).join('；'))+'</div>').join('')+'</div>':'')+'<div class="table-wrap" style="margin-top:12px">'+renderDays(p.days||[])+'</div>'}async function preview(){try{const data=await call('/admin/calendar/preview?year_term='+encodeURIComponent(term()));renderPreview(data.data||{})}catch(_){}}async function publish(){try{await preview()}catch(_){return}if(!lastPreview||!lastPreview.publishable||!lastPreview.changed)return;if(!confirm('确认发布当前草稿？客户端将使用新的校历快照。'))return;try{await call('/admin/calendar/publish',{method:'POST',body:JSON.stringify({year_term:term()})});toast('发布成功');await Promise.all([loadPublished(),preview(),listNotices()])}catch(_){}}async function setOverride(){const action=$('override-action').value;const kind=$('override-kind').value;const date=$('override-date').value;if(!date){toast('请先选择实际日期',true);return}try{await call('/admin/calendar/overrides',{method:'POST',body:JSON.stringify({year_term:term(),date:date,action:action,kind:action==='upsert'?kind:null,schedule_date:action==='upsert'&&kind==='teaching_day'?($('override-source').value||null):null,label:action==='upsert'?$('override-label').value:null})});toast('人工覆盖已保存');await preview()}catch(_){}}async function removeOverride(){const date=$('override-date').value;if(!date){toast('请先选择要移除的日期',true);return}if(!confirm('移除 '+date+' 的人工覆盖？'))return;try{await call('/admin/calendar/overrides?year_term='+encodeURIComponent(term())+'&date='+encodeURIComponent(date),{method:'DELETE'});toast('人工覆盖已移除');await preview()}catch(_){}}async function refreshAll(){await loadPublished();if(!$('token').value.trim()){$('notices').innerHTML='<div class="empty">输入管理令牌后刷新管理数据</div>';$('preview').innerHTML='<div class="empty">输入管理令牌后刷新草稿</div>';return}await Promise.all([listNotices(),preview()])} $('term').addEventListener('change',()=>{notices=[];editingId=null;lastPreview=null;newNotice();$('notices').innerHTML='<div class="empty">正在加载通知…</div>';$('preview').innerHTML='<div class="empty">正在加载草稿…</div>';$('publish-btn').disabled=true;refreshAll()});function syncOverrideFields(){const kindField=$('override-kind-field');const sourceField=$('override-source-field');const labelField=$('override-label-field');const suppress=$('override-action').value==='suppress';const teaching=$('override-kind').value==='teaching_day'&&!suppress;$('override-kind').disabled=suppress;$('override-source').disabled=!teaching;sourceField.hidden=!teaching;kindField.hidden=suppress;labelField.hidden=suppress}$('override-action').addEventListener('change',syncOverrideFields);$('override-kind').addEventListener('change',syncOverrideFields);syncOverrideFields();refreshAll();
</script></body></html>"""


@app.middleware("http")
async def security_headers_and_body_limit(request: Request, call_next: Any) -> JSONResponse:
    content_length = request.headers.get("content-length", "").strip()
    if content_length:
        try:
            if int(content_length) > 65536:
                return JSONResponse(
                    status_code=413,
                    content={
                        "success": False,
                        "error": {
                            "code": "request_too_large",
                            "message": "请求体过大",
                        },
                    },
                    headers={"Cache-Control": "no-store"},
                )
        except ValueError:
            pass
    response = await call_next(request)
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response


@app.exception_handler(ServiceError)
async def service_error_handler(_request: Request, exc: ServiceError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "success": False,
            "error": {"code": exc.code, "message": exc.message},
        },
    )


@app.exception_handler(RequestValidationError)
async def validation_error_handler(
    _request: Request, _exc: RequestValidationError
) -> JSONResponse:
    return JSONResponse(
        status_code=422,
        content={
            "success": False,
            "error": {"code": "validation_error", "message": "请求参数不合法"},
        },
    )


@app.get("/health")
def health() -> Dict[str, Any]:
    return {"status": "ok", "ready": True}


@app.get("/admin/calendar", response_class=HTMLResponse)
def calendar_admin_page(request: Request) -> HTMLResponse:
    return HTMLResponse(_CALENDAR_ADMIN_HTML)


@app.get("/admin/calendar/notices")
def calendar_list_notices(request: Request, year_term: str = Query(...)) -> Dict[str, Any]:
    _require_calendar_admin(request)
    try:
        notices = _calendar_store().list_notices(year_term)
    except CalendarError as exc:
        raise _calendar_error(exc) from exc
    return {"success": True, "data": notices}


@app.post("/admin/calendar/notices")
def calendar_create_notice(payload: CalendarNoticeRequest, request: Request) -> Dict[str, Any]:
    _require_calendar_admin(request)
    try:
        notice = _calendar_store().create_notice(payload.year_term, payload.title, payload.body)
    except CalendarError as exc:
        raise _calendar_error(exc) from exc
    return {"success": True, "data": notice}


@app.put("/admin/calendar/notices/{notice_id}")
def calendar_update_notice(
    notice_id: int, payload: CalendarNoticeRequest, request: Request
) -> Dict[str, Any]:
    _require_calendar_admin(request)
    try:
        notice = _calendar_store().update_notice(notice_id, payload.year_term, payload.title, payload.body)
    except CalendarError as exc:
        raise _calendar_error(exc) from exc
    return {"success": True, "data": notice}


@app.delete("/admin/calendar/notices/{notice_id}")
def calendar_delete_notice(notice_id: int, request: Request) -> Dict[str, Any]:
    _require_calendar_admin(request)
    try:
        _calendar_store().delete_notice(notice_id)
    except CalendarError as exc:
        raise _calendar_error(exc) from exc
    return {"success": True}


@app.get("/admin/calendar/preview")
def calendar_preview(request: Request, year_term: str = Query(...)) -> Dict[str, Any]:
    _require_calendar_admin(request)
    try:
        preview = _calendar_store().preview(year_term)
    except CalendarError as exc:
        raise _calendar_error(exc) from exc
    return {"success": True, "data": preview}


@app.post("/admin/calendar/overrides")
@app.post("/admin/calendar/override")
def calendar_set_override(
    payload: CalendarOverrideRequest, request: Request
) -> Dict[str, Any]:
    _require_calendar_admin(request)
    try:
        override = _calendar_store().set_override(
            payload.year_term,
            payload.date,
            payload.action,
            payload.kind,
            payload.schedule_date,
            payload.label,
        )
    except CalendarError as exc:
        raise _calendar_error(exc) from exc
    return {"success": True, "data": override}


@app.delete("/admin/calendar/overrides")
def calendar_delete_override(
    request: Request, year_term: str = Query(...), date: str = Query(...)
) -> Dict[str, Any]:
    _require_calendar_admin(request)
    try:
        _calendar_store().delete_override(year_term, date)
    except CalendarError as exc:
        raise _calendar_error(exc) from exc
    return {"success": True}


@app.post("/admin/calendar/publish")
def calendar_publish(payload: CalendarPublishRequest, request: Request) -> Dict[str, Any]:
    _require_calendar_admin(request)
    try:
        snapshot = _calendar_store().publish(payload.year_term)
    except CalendarError as exc:
        raise _calendar_error(exc) from exc
    return {"success": True, "data": snapshot}


@app.get("/api/calendar/term-overrides")
def calendar_term_overrides(
    request: Request, year_term: str = Query(...)
) -> Any:
    """Return the last explicitly published calendar snapshot for a term."""
    try:
        snapshot = _calendar_store().get_snapshot(year_term)
    except CalendarError as exc:
        raise _calendar_error(exc) from exc
    if snapshot is None:
        raise ServiceError(404, "calendar_not_published", "该学期尚未发布校历")

    revision = str(snapshot["revision"])
    supplied = request.headers.get("if-none-match", "").strip()
    # Accept both the plain revision emitted by this service and the quoted
    # form used by some HTTP clients/proxies.
    if supplied.strip('"') == revision:
        return Response(status_code=304, headers={"ETag": revision})
    return JSONResponse(
        content={"success": True, "data": snapshot},
        headers={"ETag": revision},
    )


@app.post("/api/jwxt/term-schedule-notices")
def fetch_term_schedule_notices(
    payload: PipelineRequest,
    request: Request,
) -> Dict[str, Any]:
    if not _rate_limiter.allow(_client_identity(request)):
        raise ServiceError(429, "rate_limited", "请求过于频繁，请稍后再试")
    if not _pipeline_slots.acquire(blocking=False):
        raise ServiceError(503, "service_busy", "服务繁忙，请稍后再试")
    try:
        result = run_pipeline_isolated(
            username=payload.username,
            encrypted_password=payload.encrypted_password,
            year_term=payload.year_term,
            env_name=payload.env,
            headless=payload.headless,
        )
        return {"success": True, "data": result}
    finally:
        _pipeline_slots.release()
