"""Current examination arrangements from the desktop JWXT page."""

import hashlib
import json
import re
import time
import unicodedata
from collections.abc import Callable
from datetime import datetime, timedelta, timezone
from urllib.parse import urljoin, urlsplit

from FastAPI.service_common import ServiceError

EXAM_HOST = "jwxt.cqut.edu.cn"
EXAM_PATH = "/jwglxt/kwgl/kscx_cxXsksxxIndex.html"
EXAM_PAGE = f"https://{EXAM_HOST}{EXAM_PATH}?gnmkdm=N358105&layout=default"
CHINA_TIME = timezone(timedelta(hours=8))
FIELDS = ("kcmc", "kssj", "cdxqmc", "cdmc")


def _invalid_response() -> ServiceError:
    return ServiceError(502, "upstream_invalid_response", "考试查询返回数据不完整或格式错误")


def _unavailable(message: str = "考试查询服务暂时不可用") -> ServiceError:
    return ServiceError(502, "upstream_unavailable", message)


def _page_rows(body: object, expected_page: int) -> tuple[tuple[int, int, int], list[dict]]:
    if not isinstance(body, dict):
        raise _invalid_response()
    current, total, pages, size = (body.get(field) for field in
                                   ("currentPage", "totalCount", "totalPage", "showCount"))
    rows = body.get("items")
    if (any(type(value) is not int for value in (current, total, pages, size))
            or total < 0 or size < 1 or not isinstance(rows, list)):
        raise _invalid_response()
    if total == 0:
        if expected_page != 1 or current not in (0, 1) or pages not in (0, 1) or rows:
            raise _invalid_response()
    elif (current != expected_page or not 1 <= current <= pages
          or pages != (total + size - 1) // size
          or len(rows) != min(size, total - (current - 1) * size)):
        raise _invalid_response()
    return (total, pages, size), rows


def _normalize_rows(rows: list[dict]) -> list[dict]:
    exams = {}
    for row in rows:
        if not isinstance(row, dict) or any(not isinstance(row.get(field), str) for field in FIELDS):
            raise _invalid_response()
        course, time_text, campus, room = [
            re.sub(r"\s+", " ", unicodedata.normalize("NFKC", row[field])).strip() for field in FIELDS
        ]
        if not course:
            raise _invalid_response()
        values = (course, time_text, campus, "", room)
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
        exams.setdefault(key, {"key": key, "course_name": course, "time_text": row["kssj"].strip(),
                               "campus": campus, "building": "", "room": room,
                               "start_at": start_at, "end_at": end_at})
    return list(exams.values())


def normalize_exam_data(body: object) -> list[dict]:
    """Normalize a complete single-page JWXT response, including an empty result."""
    return _collect_exam_pages(body)


def _collect_exam_pages(first_body: object, fetch_page: Callable[[int], object] | None = None) -> list[dict]:
    metadata, rows = _page_rows(first_body, 1)
    _, pages, _ = metadata
    if pages > 1 and fetch_page is None:
        raise _invalid_response()
    all_rows = list(rows)
    previous_pages = [rows]
    for page_number in range(2, pages + 1):
        page_metadata, rows = _page_rows(fetch_page(page_number), page_number)
        if page_metadata != metadata or rows in previous_pages:
            raise _invalid_response()
        previous_pages.append(rows)
        all_rows.extend(rows)
    return _normalize_rows(all_rows)


def _is_exam_url(url: str) -> bool:
    target = urlsplit(url)
    return target.hostname == EXAM_HOST and target.path == EXAM_PATH


def _is_login_url(url: str, login_page: str) -> bool:
    target, login = urlsplit(url), urlsplit(login_page)
    return (target.hostname == login.hostname
            or (target.hostname == EXAM_HOST and target.path.startswith("/jwglxt/xtgl/login_")))


def _check_response(response, login_page: str) -> None:
    location = response.headers.get("location")
    if (response.status in (401, 403) or _is_login_url(response.url, login_page)
            or (location and _is_login_url(urljoin(response.url, location), login_page))):
        raise _unavailable("教务系统会话已失效，请重新查询")
    if response.status != 200:
        raise _unavailable()


def run_exam_pipeline(username: str, encrypted_password: str, query_id: str | None = None,
                      query_started_at: float | None = None) -> dict:
    from playwright.sync_api import Error as BrowserError, TimeoutError as BrowserTimeout, sync_playwright
    from FastAPI.jwxt_automation import _query_process_environment, build_env_config, login_browser, log_exam_query

    started_at = time.monotonic() if query_started_at is None else query_started_at
    config = build_env_config("prod")
    timeout_ms = config.timeout_sec * 1000

    def log_phase(phase: str, status: int | None = None) -> None:
        log_exam_query(query_id, "phase", started_at, phase=phase, status=status)

    def is_exam_response(response) -> bool:
        return response.request.method == "POST" and _is_exam_url(response.url)

    def response_body(response) -> object:
        log_phase("exam_response", response.status)
        _check_response(response, config.cas_login_page)
        try:
            return response.json()
        except ValueError as exc:
            raise _invalid_response() from exc

    try:
        log_phase("browser_launch")
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True, chromium_sandbox=True, env=_query_process_environment())
            try:
                page = browser.new_context().new_page()
                log_phase("browser_login")
                payload = {"name": username, "pwd": encrypted_password, "verifyCode": None,
                           "universityId": "100005", "loginType": "login"}
                login_browser(page, config.cas_login_page, config.cas_do_login, payload, timeout_ms)
                page.goto(config.cas_login_page, wait_until="domcontentloaded", timeout=timeout_ms)

                log_phase("wait_exam_response")
                loaded = False
                try:
                    with page.expect_response(is_exam_response, timeout=min(4000, timeout_ms)) as pending:
                        navigation = page.goto(EXAM_PAGE, wait_until="domcontentloaded", timeout=timeout_ms)
                        if navigation is not None:
                            _check_response(navigation, config.cas_login_page)
                        if not _is_exam_url(page.url):
                            raise _invalid_response()
                        loaded = True
                except BrowserTimeout:
                    if not loaded:
                        raise
                    if _is_login_url(page.url, config.cas_login_page):
                        raise _unavailable("教务系统会话已失效，请重新查询")
                    with page.expect_response(is_exam_response, timeout=timeout_ms) as pending:
                        page.locator("#search_go").click(timeout=timeout_ms)

                def fetch_page(_page_number: int) -> object:
                    log_phase("wait_exam_response")
                    with page.expect_response(is_exam_response, timeout=timeout_ms) as next_response:
                        page.locator('#pager [id="next_pager"]').click(timeout=timeout_ms)
                    return response_body(next_response.value)

                exams = _collect_exam_pages(response_body(pending.value), fetch_page)
                return {"generated_at": datetime.now(CHINA_TIME).isoformat(),
                        "exams_complete": True, "exams": exams}
            finally:
                browser.close()
    except BrowserTimeout as exc:
        raise ServiceError(504, "pipeline_timeout", "考试查询超时，请稍后重试") from exc
    except BrowserError as exc:
        raise _unavailable() from exc
