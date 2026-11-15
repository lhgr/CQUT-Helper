"""Current examination arrangements from the school's examination application."""

import hashlib
import json
import re
import unicodedata
import time
from datetime import datetime, timedelta, timezone
from urllib.parse import parse_qs, quote, urlparse

import requests

from FastAPI.service_common import ServiceError

MOBILE_BASE = "https://app-ehall.cqut.edu.cn"
AUTH_URL = MOBILE_BASE + "/ump/common/login/authURL"
EXAM_HOST = "ksap-w.cqut.edu.cn"
CHINA_TIME = timezone(timedelta(hours=8))
FIELDS = ("kcmc", "kscs", "xqmc", "ldmc", "cdmc")


def _invalid_response() -> ServiceError:
    return ServiceError(502, "upstream_invalid_response", "考试查询返回数据不完整或格式错误")


def normalize_exam_data(body: object) -> list[dict]:
    if not isinstance(body, dict) or body.get("IsSuccessful") is not True:
        raise _invalid_response()
    rows = body.get("Data")
    if not isinstance(rows, list):
        raise _invalid_response()
    exams = []
    seen = set()
    for row in rows:
        if not isinstance(row, dict) or any(not isinstance(row.get(field), str) for field in FIELDS):
            raise _invalid_response()
        values = [re.sub(r"\s+", " ", unicodedata.normalize("NFKC", row[field])).strip() for field in FIELDS]
        course, time_text, campus, building, room = values
        if not course:
            raise _invalid_response()
        key = hashlib.sha256(json.dumps(values, ensure_ascii=False, separators=(",", ":")).encode("utf-8")).hexdigest()
        start_at = end_at = None
        match = re.fullmatch(r"(\d{4}-\d{2}-\d{2})\s*\(\s*(\d{2}:\d{2})\s*-\s*(\d{2}:\d{2})\s*\)", time_text)
        if match:
            try:
                start = datetime.strptime(f"{match[1]} {match[2]}", "%Y-%m-%d %H:%M").replace(tzinfo=CHINA_TIME)
                end = datetime.strptime(f"{match[1]} {match[3]}", "%Y-%m-%d %H:%M").replace(tzinfo=CHINA_TIME)
                if end > start:
                    start_at, end_at = start.isoformat(), end.isoformat()
            except ValueError:
                pass
        if key in seen:
            continue
        seen.add(key)
        exams.append({"key": key, "course_name": course, "time_text": row["kscs"].strip(),
                      "campus": campus, "building": building, "room": room,
                      "start_at": start_at, "end_at": end_at})
    return exams


def mobile_params(**extra) -> dict:
    return {"appKey": "mobileplatform", "appVersion": "V6.3.10",
            "clientCategory": "ANDROID", "debugApk": "false", "universityId": "100005",
            "nonce": str(time.time_ns())[:13], "timestamp": str(round(time.time() * 1000)), **extra}


def _mobile_content(session: requests.Session, path: str, timeout: int, **extra) -> dict:
    response = session.get(MOBILE_BASE + path, params=mobile_params(**extra), timeout=timeout)
    response.raise_for_status()
    try:
        body = response.json()
        if not isinstance(body, dict) or body.get("code") != "40001" or not isinstance(body.get("content"), dict):
            raise _invalid_response()
        return body["content"]
    except (ValueError, TypeError) as exc:
        raise _invalid_response() from exc


def exam_cas_url(session: requests.Session, timeout: int) -> str:
    content = _mobile_content(session, "/ump/common/login/authURL", timeout, userType="STUDENT")
    try:
        url = content["redirectUri"]
        parsed = urlparse(url)
        service = urlparse(parse_qs(parsed.query)["service"][0])
        if (content.get("authSource") != "CAS_PLUS"
                or parsed.scheme != "https" or parsed.netloc != "uis.cqut.edu.cn"
                or parsed.path != "/center-auth-server/officeHallApplicationCode/cas/login"
                or service.scheme != "https" or service.netloc != "uis.cqut.edu.cn"
                or service.path != "/ump/common/login/authSourceAuth/auth" or service.query):
            raise _invalid_response()
        return url
    except (ValueError, TypeError, KeyError, IndexError) as exc:
        raise _invalid_response() from exc


def exam_launch_url(token: str, timeout: int) -> str:
    # A new native-app session deliberately has no UIS browser cookies.
    with requests.Session() as session:
        session.headers.update({"User-Agent": "okhttp/4.4.1", "Accept": "application/json", "token": token})
        content = _mobile_content(session, "/ump/officeHall/getApplicationUrl", timeout, applicationCode="UIVx60")
        ticket = content.get("ticket")
        if not isinstance(ticket, str) or not ticket:
            raise _invalid_response()
        content = _mobile_content(session, "/generalservice/auth/userInfo/" + quote(ticket, safe=""),
                                  timeout, applicationCode="UIVx60")
        mic_token = content.get("token")
        if not isinstance(mic_token, str) or not mic_token:
            raise _invalid_response()
        session.headers["mictoken"] = mic_token
        content = _mobile_content(session, "/ump/officeHall/getApplicationUrl", timeout,
                                  applicationCode="GTR585", userType="STUDENT")
        url = content.get("redirectUrl")
        if not isinstance(url, str):
            raise _invalid_response()
        parsed = urlparse(url)
        if parsed.scheme != "http" or parsed.netloc != EXAM_HOST or parsed.path != "/sso/app":
            raise _invalid_response()
        return url


def run_exam_pipeline(username: str, encrypted_password: str, query_id: str | None = None,
                      query_started_at: float | None = None) -> dict:
    from playwright.sync_api import TimeoutError as BrowserTimeout, Error as BrowserError, sync_playwright
    from FastAPI.jwxt_automation import JwxtAutomation, _query_process_environment, login_browser, log_exam_query

    started_at = time.monotonic() if query_started_at is None else query_started_at
    client = JwxtAutomation(username, encrypted_password, "prod")
    try:
        log_exam_query(query_id, "phase", started_at, phase="cas_entry")
        login_url = exam_cas_url(client.session, client.config.timeout_sec)
        log_exam_query(query_id, "phase", started_at, phase="browser_launch")
        with sync_playwright() as playwright:
            # The school's HTTP challenge requires native non-automation behavior.
            browser = playwright.chromium.launch(
                headless=True, chromium_sandbox=True, env=_query_process_environment(),
                args=["--disable-features=HttpsUpgrades,HttpsFirstModeV2,HttpsFirstModeV2ForEngagedSites,HttpsFirstBalancedModeAutoEnable",
                      "--disable-blink-features=AutomationControlled"])
            try:
                auth_context = browser.new_context(
                    user_agent="Mozilla/5.0 (Linux; Android 13; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/" + browser.version + " Mobile Safari/537.36 AXINFU2.0 YhkjApp/V6.3.10",
                    is_mobile=True, has_touch=True, viewport={"width": 390, "height": 844})
                captured = {}

                def capture_token(source, payload):
                    try:
                        value = json.loads(payload) if isinstance(payload, str) else payload
                        token = value.get("token") if isinstance(value, dict) else None
                        if isinstance(token, str) and token:
                            captured["token"] = token
                    except (ValueError, TypeError):
                        pass

                auth_context.expose_binding("__capture_auth", capture_token)
                auth_context.add_init_script("window.jsAndroid = {yhThirdAuthToken: value => window.__capture_auth(value)};")
                page = auth_context.new_page()
                log_exam_query(query_id, "phase", started_at, phase="browser_login")
                payload = {"name": username, "pwd": encrypted_password, "verifyCode": "", "universityId": "100005"}
                login_browser(page, login_url, client.config.cas_do_login, payload, client.config.timeout_sec * 1000)
                page.goto(login_url, wait_until="domcontentloaded", timeout=30000)
                deadline = time.monotonic() + 15
                while not captured and time.monotonic() < deadline:
                    page.wait_for_timeout(100)
                if not captured:
                    raise ServiceError(502, "upstream_unavailable", "考试查询认证暂时不可用")
                log_exam_query(query_id, "phase", started_at, phase="mobile_launch")
                redirect_url = exam_launch_url(captured.pop("token"), client.config.timeout_sec)
                auth_context.close()
                cdp = browser.new_browser_cdp_session()
                try:
                    desktop_ua = cdp.send("Browser.getVersion")["userAgent"].replace("HeadlessChrome", "Chrome")
                finally:
                    cdp.detach()
                context = browser.new_context(user_agent=desktop_ua)
                page = context.new_page()

                def is_exam_response(response):
                    parsed = urlparse(response.url)
                    return (parsed.hostname == EXAM_HOST and parsed.path.lower() == "/home/getdata"
                            and response.request.method == "POST")

                log_exam_query(query_id, "phase", started_at, phase="wait_exam_response")
                with context.expect_event("response", predicate=is_exam_response, timeout=30000) as pending:
                    page.goto(redirect_url, wait_until="domcontentloaded", timeout=30000)
                response = pending.value
                log_exam_query(query_id, "phase", started_at, phase="exam_response", status=response.status)
                if response.status != 200:
                    raise ServiceError(502, "upstream_unavailable", "考试查询服务暂时不可用")
                try:
                    exams = normalize_exam_data(response.json())
                except (ValueError, TypeError) as exc:
                    raise _invalid_response() from exc
                return {"generated_at": datetime.now(CHINA_TIME).isoformat(),
                        "exams_complete": True, "exams": exams}
            finally:
                browser.close()
    except BrowserTimeout as exc:
        raise ServiceError(504, "pipeline_timeout", "考试查询超时，请稍后重试") from exc
    except (BrowserError, requests.RequestException) as exc:
        raise ServiceError(502, "upstream_unavailable", "考试查询服务暂时不可用") from exc
    finally:
        client.session.close()

