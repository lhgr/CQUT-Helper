import json
import os
import re
import subprocess
import tempfile
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urljoin

import requests
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field, field_validator
from requests.adapters import HTTPAdapter
from urllib3.util import Retry

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
        "term_schedule_notices": notices,
    }
    return result


class PipelineRequest(BaseModel):
    username: str = Field(..., min_length=1)
    encrypted_password: str = Field(..., min_length=1)
    year_term: str = Field(..., pattern=r"^\d{4}-\d{4}-[12]$")
    env: str = Field(default="prod", pattern="^(dev|test|prod)$")
    headless: bool = True

    @field_validator("year_term")
    @classmethod
    def validate_year_term(cls, value: str) -> str:
        normalized = value.strip()
        parse_year_term_range(normalized)
        return normalized


app = FastAPI(title="JWXT Automation API", version="1.0.0")


@app.get("/health")
def health() -> Dict[str, str]:
    return {"status": "ok"}


@app.post("/api/jwxt/term-schedule-notices")
def fetch_term_schedule_notices(payload: PipelineRequest) -> Dict[str, Any]:
    try:
        result = run_pipeline(
            username=payload.username,
            encrypted_password=payload.encrypted_password,
            year_term=payload.year_term,
            env_name=payload.env,
            headless=payload.headless,
        )
        return {"success": True, "data": result}
    except HTTPException:
        raise
    except requests.HTTPError as exc:
        status_code = exc.response.status_code if exc.response is not None else None
        if status_code == 403:
            raise HTTPException(
                status_code=403,
                detail="上游接口夜间关闭(403)，请白天时段再试",
            ) from exc
        raise HTTPException(status_code=502, detail=f"上游请求失败: {exc}") from exc
    except requests.RequestException as exc:
        raise HTTPException(status_code=502, detail=f"上游请求失败: {exc}") from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"处理失败: {exc}") from exc
