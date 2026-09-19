"""Persistent, publishable academic-calendar overrides.

This module deliberately uses only the Python standard library.  The public
snapshot is immutable until an administrator explicitly publishes a new one.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import threading
from contextlib import contextmanager
from datetime import date, datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple
from zoneinfo import ZoneInfo


SHANGHAI = ZoneInfo("Asia/Shanghai")
_YEAR_TERM_RE = re.compile(r"^(\d{4})-(\d{4})-([12])$")
_DATE_RE = re.compile(r"(\d{1,2})月(\d{1,2})日")
_WEEKDAY_RE = re.compile(r"星期([一二三四五六日天])")
_WEEKDAY_INDEX = {"一": 0, "二": 1, "三": 2, "四": 3, "五": 4, "六": 5, "日": 6, "天": 6}


class CalendarError(ValueError):
    """A user-correctable calendar administration error."""


def validate_year_term(year_term: str) -> str:
    normalized = (year_term or "").strip()
    match = _YEAR_TERM_RE.fullmatch(normalized)
    if (
        not match
        or int(match.group(1)) < 1
        or int(match.group(2)) != int(match.group(1)) + 1
        or int(match.group(2)) > 9999
    ):
        raise CalendarError("year_term格式错误，应为YYYY-YYYY-1或YYYY-YYYY-2")
    return normalized


def parse_iso_date(value: str) -> date:
    if not isinstance(value, str):
        raise CalendarError("日期格式错误，应为YYYY-MM-DD")
    try:
        return date.fromisoformat((value or "").strip())
    except ValueError as exc:
        raise CalendarError("日期格式错误，应为YYYY-MM-DD") from exc


def _term_bounds(year_term: str) -> Tuple[date, date]:
    """Return the academic-year date range represented by a term."""
    start_year, end_year, _ = _YEAR_TERM_RE.fullmatch(validate_year_term(year_term)).groups()
    return date(int(start_year), 9, 1), date(int(end_year), 8, 31)


def _validate_term_date(year_term: str, value: str, field: str = "日期") -> str:
    parsed = parse_iso_date(value)
    start, end = _term_bounds(year_term)
    if not start <= parsed <= end:
        raise CalendarError(f"{field}不在学年范围内，应为{start.isoformat()}至{end.isoformat()}")
    return parsed.isoformat()


def _term_date(year_term: str, month: int, day: int) -> date:
    start_year, end_year, term = _YEAR_TERM_RE.fullmatch(validate_year_term(year_term)).groups()
    year = int(start_year) if (int(term) == 1 and month >= 9) or (int(term) == 2 and month >= 9) else int(end_year)
    # Second terms naturally use the end year; first terms use the start year
    # for September--December and end year for January.
    if int(term) == 2:
        year = int(end_year)
    try:
        return date(year, month, day)
    except ValueError as exc:
        raise CalendarError("通知中包含无效日期") from exc


def _date_from_match(year_term: str, match: re.Match[str]) -> date:
    return _term_date(year_term, int(match.group(1)), int(match.group(2)))


def _check_weekday(clause: str, dates: List[date], issues: List[str]) -> None:
    """Mark a notice incomplete when an explicit weekday is inconsistent.

    The date remains a candidate so an administrator can see and correct it,
    but the draft cannot be published until the mismatch is resolved.
    """
    weekdays = _WEEKDAY_RE.findall(clause)
    if not weekdays:
        return
    if len(weekdays) != len(dates) or any(
        _WEEKDAY_INDEX[weekday] != current.weekday()
        for weekday, current in zip(weekdays, dates)
    ):
        issues.append("通知中的星期与日期不一致，请人工确认")


def _expand(start: date, end: date) -> Iterable[date]:
    if end < start:
        raise CalendarError("放假结束日期早于开始日期")
    ordinal = start.toordinal()
    while ordinal <= end.toordinal():
        yield date.fromordinal(ordinal)
        ordinal += 1


def parse_notice(year_term: str, title: str, body: str) -> Tuple[List[Dict[str, Any]], bool, List[str]]:
    """Parse the stable date phrases used in school holiday notices.

    Unknown prose is harmless.  A notice is marked incomplete only when it
    clearly announces holiday/workday arrangements but none of the relevant
    clauses can be parsed, allowing the administrator to finish it manually.
    """
    validate_year_term(year_term)
    source = (title or "") + "\n" + (body or "")
    normalized = re.sub(r"\s+", "", source)
    items: List[Dict[str, Any]] = []
    issues: List[str] = []

    holiday_pattern = re.compile(
        r"(?P<label>[\u4e00-\u9fff]{1,12}节)\s*[：:]\s*"
        r"(?P<start>\d{1,2}月\d{1,2}日)(?:（[^）]*）|\([^)]*\))?"
        r"(?:至(?P<end>\d{1,2}月\d{1,2}日)(?:（[^）]*）|\([^)]*\))?)?"
        r"放假(?:调休)?(?:，共(?P<count>\d+)天)?"
    )
    for match in holiday_pattern.finditer(normalized):
        start_match = _DATE_RE.fullmatch(match.group("start"))
        end_text = match.group("end")
        end_match = _DATE_RE.fullmatch(end_text) if end_text else start_match
        if start_match is None or end_match is None:
            issues.append("未能识别放假日期")
            continue
        start = _date_from_match(year_term, start_match)
        end = _date_from_match(year_term, end_match)
        _check_weekday(match.group(0), [start] if end_match is start_match else [start, end], issues)
        declared_count = match.group("count")
        if declared_count is not None and int(declared_count) != (end - start).days + 1:
            issues.append("通知中的放假天数与日期范围不一致，请人工确认")
        for current in _expand(start, end):
            items.append({
                "date": current.isoformat(),
                "kind": "holiday",
                "schedule_date": None,
                "label": match.group("label"),
                "source_excerpt": match.group(0),
            })

    # e.g. "9月26日（星期六）上班，按9月29日（校历第5周星期二）课表上课".
    mapped_workday_pattern = re.compile(
        r"(?P<actual>\d{1,2}月\d{1,2}日)(?:（[^）]*）|\([^)]*\))?上班，"
        r"按(?P<source>\d{1,2}月\d{1,2}日)(?:（[^）]*）|\([^)]*\))?课表上课"
    )
    for match in mapped_workday_pattern.finditer(normalized):
        actual_match = _DATE_RE.fullmatch(match.group("actual"))
        source_match = _DATE_RE.fullmatch(match.group("source"))
        if actual_match is None or source_match is None:
            issues.append("未能识别调休补课日期")
            continue
        actual = _date_from_match(year_term, actual_match)
        source = _date_from_match(year_term, source_match)
        _check_weekday(match.group(0), [actual, source], issues)
        items.append({
            "date": actual.isoformat(),
            "kind": "teaching_day",
            "schedule_date": source.isoformat(),
            "label": "调休补课",
            "source_excerpt": match.group(0),
        })

    # e.g. "9月20日（星期日）上班，按当天（校历第3周星期日）课表上课".
    same_day_pattern = re.compile(
        r"(?P<actual>\d{1,2}月\d{1,2}日)(?:（[^）]*）|\([^)]*\))?上班，按当天"
        r"(?:（[^）]*）|\([^)]*\))?课表上课"
    )
    for match in same_day_pattern.finditer(normalized):
        actual_match = _DATE_RE.fullmatch(match.group("actual"))
        if actual_match is None:
            issues.append("未能识别调休上班日期")
            continue
        actual_date = _date_from_match(year_term, actual_match)
        # Both the actual date and the referenced same-day timetable can have
        # an explicit weekday annotation; they refer to the same date.
        _check_weekday(match.group(0), [actual_date, actual_date], issues)
        actual = actual_date.isoformat()
        items.append({
            "date": actual,
            "kind": "teaching_day",
            "schedule_date": actual,
            "label": "调休上班",
            "source_excerpt": match.group(0),
        })

    has_arrangement_words = any(word in normalized for word in ("放假", "上班，按", "补课"))
    return items, not (has_arrangement_words and not items) and not issues, issues


def _canonical_rule(rule: Dict[str, Any]) -> Tuple[str, Optional[str], str]:
    return rule["kind"], rule.get("schedule_date"), rule.get("label") or ""


class CalendarStore:
    def __init__(self, db_path: str):
        self.db_path = str(Path(db_path))
        self._lock = threading.RLock()
        Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    @contextmanager
    def _connect(self) -> Iterable[sqlite3.Connection]:
        connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        try:
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def _initialize(self) -> None:
        with self._connect() as db:
            db.executescript(
                """
                PRAGMA foreign_keys = ON;
                CREATE TABLE IF NOT EXISTS calendar_notices (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    year_term TEXT NOT NULL,
                    title TEXT NOT NULL,
                    body TEXT NOT NULL,
                    parse_complete INTEGER NOT NULL,
                    parse_issues TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS calendar_candidates (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    notice_id INTEGER NOT NULL REFERENCES calendar_notices(id) ON DELETE CASCADE,
                    date TEXT NOT NULL,
                    kind TEXT NOT NULL CHECK(kind IN ('holiday', 'teaching_day')),
                    schedule_date TEXT,
                    label TEXT NOT NULL,
                    source_excerpt TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS calendar_overrides (
                    year_term TEXT NOT NULL,
                    date TEXT NOT NULL,
                    action TEXT NOT NULL CHECK(action IN ('upsert', 'suppress')),
                    kind TEXT CHECK(kind IN ('holiday', 'teaching_day')),
                    schedule_date TEXT,
                    label TEXT,
                    updated_at TEXT NOT NULL,
                    PRIMARY KEY(year_term, date)
                );
                CREATE TABLE IF NOT EXISTS calendar_snapshots (
                    year_term TEXT PRIMARY KEY,
                    revision TEXT NOT NULL,
                    generated_at TEXT NOT NULL,
                    content_json TEXT NOT NULL
                );
                """
            )

    @staticmethod
    def _now() -> str:
        return datetime.now(SHANGHAI).isoformat(timespec="seconds")

    @staticmethod
    def _validate_rule(year_term: str, kind: str, schedule_date: Optional[str], label: Optional[str]) -> Tuple[str, Optional[str], str]:
        normalized_kind = (kind or "").strip()
        if normalized_kind not in {"holiday", "teaching_day"}:
            raise CalendarError("kind必须是holiday或teaching_day")
        normalized_label = (label or "").strip()
        if not normalized_label:
            raise CalendarError("label不能为空")
        if normalized_kind == "holiday":
            if schedule_date:
                raise CalendarError("holiday不能包含schedule_date")
            return normalized_kind, None, normalized_label
        if not schedule_date:
            raise CalendarError("teaching_day必须包含schedule_date")
        return normalized_kind, _validate_term_date(year_term, schedule_date, "schedule_date"), normalized_label

    def create_notice(self, year_term: str, title: str, body: str) -> Dict[str, Any]:
        term = validate_year_term(year_term)
        if not (title or "").strip() or not (body or "").strip():
            raise CalendarError("标题和正文不能为空")
        parsed, complete, issues = parse_notice(term, title, body)
        now = self._now()
        with self._lock, self._connect() as db:
            cursor = db.execute(
                "INSERT INTO calendar_notices(year_term,title,body,parse_complete,parse_issues,created_at,updated_at) VALUES(?,?,?,?,?,?,?)",
                (term, title.strip(), body.strip(), int(complete), json.dumps(issues, ensure_ascii=False), now, now),
            )
            notice_id = int(cursor.lastrowid)
            self._replace_candidates(db, notice_id, parsed)
        return self.get_notice(notice_id)

    def update_notice(self, notice_id: int, year_term: str, title: str, body: str) -> Dict[str, Any]:
        term = validate_year_term(year_term)
        if not (title or "").strip() or not (body or "").strip():
            raise CalendarError("标题和正文不能为空")
        parsed, complete, issues = parse_notice(term, title, body)
        with self._lock, self._connect() as db:
            existing = db.execute("SELECT id FROM calendar_notices WHERE id=?", (notice_id,)).fetchone()
            if existing is None:
                raise CalendarError("通知不存在")
            db.execute(
                "UPDATE calendar_notices SET year_term=?,title=?,body=?,parse_complete=?,parse_issues=?,updated_at=? WHERE id=?",
                (term, title.strip(), body.strip(), int(complete), json.dumps(issues, ensure_ascii=False), self._now(), notice_id),
            )
            db.execute("DELETE FROM calendar_candidates WHERE notice_id=?", (notice_id,))
            self._replace_candidates(db, notice_id, parsed)
        return self.get_notice(notice_id)

    def _replace_candidates(self, db: sqlite3.Connection, notice_id: int, items: List[Dict[str, Any]]) -> None:
        db.executemany(
            "INSERT INTO calendar_candidates(notice_id,date,kind,schedule_date,label,source_excerpt) VALUES(?,?,?,?,?,?)",
            [
                (
                    notice_id,
                    item["date"],
                    item["kind"],
                    item["schedule_date"],
                    item["label"],
                    item["source_excerpt"],
                )
                for item in items
            ],
        )

    def delete_notice(self, notice_id: int) -> None:
        with self._lock, self._connect() as db:
            if db.execute("DELETE FROM calendar_notices WHERE id=?", (notice_id,)).rowcount != 1:
                raise CalendarError("通知不存在")

    def get_notice(self, notice_id: int) -> Dict[str, Any]:
        with self._connect() as db:
            row = db.execute("SELECT * FROM calendar_notices WHERE id=?", (notice_id,)).fetchone()
            if row is None:
                raise CalendarError("通知不存在")
            return self._notice_dict(db, row)

    def list_notices(self, year_term: str) -> List[Dict[str, Any]]:
        term = validate_year_term(year_term)
        with self._connect() as db:
            rows = db.execute("SELECT * FROM calendar_notices WHERE year_term=? ORDER BY id DESC", (term,)).fetchall()
            return [self._notice_dict(db, row) for row in rows]

    def _notice_dict(self, db: sqlite3.Connection, row: sqlite3.Row) -> Dict[str, Any]:
        candidates = db.execute(
            "SELECT date,kind,schedule_date,label,source_excerpt FROM calendar_candidates WHERE notice_id=? ORDER BY date,id",
            (row["id"],),
        ).fetchall()
        return {
            "id": row["id"], "year_term": row["year_term"], "title": row["title"], "body": row["body"],
            "parse_complete": bool(row["parse_complete"]), "parse_issues": json.loads(row["parse_issues"]),
            "created_at": row["created_at"], "updated_at": row["updated_at"],
            "candidates": [dict(candidate) for candidate in candidates],
        }

    def set_override(self, year_term: str, day: str, action: str, kind: Optional[str] = None,
                     schedule_date: Optional[str] = None, label: Optional[str] = None) -> Dict[str, Any]:
        term = validate_year_term(year_term)
        actual_date = _validate_term_date(term, day)
        normalized_action = (action or "").strip()
        if normalized_action not in {"upsert", "suppress"}:
            raise CalendarError("action必须是upsert或suppress")
        if normalized_action == "suppress":
            kind, schedule_date, label = None, None, None
        else:
            kind, schedule_date, label = self._validate_rule(term, kind or "", schedule_date, label)
        with self._lock, self._connect() as db:
            db.execute(
                "INSERT INTO calendar_overrides(year_term,date,action,kind,schedule_date,label,updated_at) VALUES(?,?,?,?,?,?,?) "
                "ON CONFLICT(year_term,date) DO UPDATE SET action=excluded.action,kind=excluded.kind,schedule_date=excluded.schedule_date,label=excluded.label,updated_at=excluded.updated_at",
                (term, actual_date, normalized_action, kind, schedule_date, label, self._now()),
            )
        return {"year_term": term, "date": actual_date, "action": normalized_action, "kind": kind,
                "schedule_date": schedule_date, "label": label}

    def delete_override(self, year_term: str, day: str) -> None:
        term = validate_year_term(year_term)
        actual_date = _validate_term_date(term, day)
        with self._lock, self._connect() as db:
            db.execute("DELETE FROM calendar_overrides WHERE year_term=? AND date=?", (term, actual_date))

    def _draft_from_db(self, db: sqlite3.Connection, year_term: str) -> Dict[str, Any]:
        term = validate_year_term(year_term)
        incomplete = db.execute(
                "SELECT id,title,parse_issues FROM calendar_notices WHERE year_term=? AND parse_complete=0 ORDER BY id",
                (term,),
            ).fetchall()
        candidate_rows = db.execute(
                "SELECT c.date,c.kind,c.schedule_date,c.label,c.notice_id FROM calendar_candidates c "
                "JOIN calendar_notices n ON n.id=c.notice_id WHERE n.year_term=? ORDER BY c.date,c.id",
                (term,),
            ).fetchall()
        override_rows = db.execute("SELECT * FROM calendar_overrides WHERE year_term=?", (term,)).fetchall()
        overrides = {row["date"]: dict(row) for row in override_rows}
        grouped: Dict[str, List[Dict[str, Any]]] = {}
        for row in candidate_rows:
            grouped.setdefault(row["date"], []).append(dict(row))
        conflicts: List[Dict[str, Any]] = []
        days: List[Dict[str, Any]] = []
        for day, rules in grouped.items():
            override = overrides.pop(day, None)
            if override is not None:
                if override["action"] == "upsert":
                    days.append({"date": day, "kind": override["kind"], "schedule_date": override["schedule_date"], "label": override["label"]})
                continue
            canonical = {_canonical_rule(rule) for rule in rules}
            if len(canonical) != 1:
                conflicts.append({"date": day, "candidates": rules})
                continue
            rule = rules[0]
            days.append({"date": day, "kind": rule["kind"], "schedule_date": rule["schedule_date"], "label": rule["label"]})
        for day, override in overrides.items():
            if override["action"] == "upsert":
                days.append({"date": day, "kind": override["kind"], "schedule_date": override["schedule_date"], "label": override["label"]})
        return {
            "year_term": term,
            "days": sorted(days, key=lambda item: item["date"]),
            "incomplete_notices": [{"id": row["id"], "title": row["title"], "parse_issues": json.loads(row["parse_issues"])} for row in incomplete],
            "conflicts": conflicts,
        }

    def _draft(self, year_term: str) -> Dict[str, Any]:
        with self._connect() as db:
            return self._draft_from_db(db, year_term)

    def preview(self, year_term: str) -> Dict[str, Any]:
        draft = self._draft(year_term)
        snapshot = self.get_snapshot(year_term)
        published_days = snapshot["days"] if snapshot else []
        published_by_date = {item["date"]: item for item in published_days}
        draft_by_date = {item["date"]: item for item in draft["days"]}
        added = [
            {"date": day, "before": None, "after": draft_by_date[day]}
            for day in sorted(set(draft_by_date) - set(published_by_date))
        ]
        removed = [
            {"date": day, "before": published_by_date[day], "after": None}
            for day in sorted(set(published_by_date) - set(draft_by_date))
        ]
        changed = [
            {"date": day, "before": published_by_date[day], "after": draft_by_date[day]}
            for day in sorted(set(published_by_date) & set(draft_by_date))
            if published_by_date[day] != draft_by_date[day]
        ]
        current = json.dumps(draft["days"], ensure_ascii=False, sort_keys=True)
        previous = json.dumps(published_days, ensure_ascii=False, sort_keys=True)
        draft["publishable"] = not draft["incomplete_notices"] and not draft["conflicts"]
        draft["changed"] = current != previous
        draft["published_revision"] = snapshot["revision"] if snapshot else None
        draft["diff"] = {"added": added, "changed": changed, "removed": removed}
        return draft

    def publish(self, year_term: str) -> Dict[str, Any]:
        # Re-read and validate under the same process lock and SQLite write
        # transaction as the snapshot write.  A preview must never become a
        # stale basis for a later publish if an editor changes the draft.
        term = validate_year_term(year_term)
        with self._lock, self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            draft = self._draft_from_db(db, term)
            draft["publishable"] = not draft["incomplete_notices"] and not draft["conflicts"]
            if not draft["publishable"]:
                raise CalendarError("草稿存在冲突或未完成解析，不能发布")
            days = draft["days"]
            payload = {"schema_version": 1, "year_term": term, "term_calendar_complete": True, "days": days}
            revision = "sha256:" + hashlib.sha256(
                json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
            ).hexdigest()
            generated_at = self._now()
            payload["revision"] = revision
            payload["generated_at"] = generated_at
            content = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
            db.execute(
                "INSERT INTO calendar_snapshots(year_term,revision,generated_at,content_json) VALUES(?,?,?,?) "
                "ON CONFLICT(year_term) DO UPDATE SET revision=excluded.revision,generated_at=excluded.generated_at,content_json=excluded.content_json",
                (term, revision, generated_at, content),
            )
        return payload

    def get_snapshot(self, year_term: str) -> Optional[Dict[str, Any]]:
        term = validate_year_term(year_term)
        with self._connect() as db:
            row = db.execute("SELECT content_json FROM calendar_snapshots WHERE year_term=?", (term,)).fetchone()
        return json.loads(row["content_json"]) if row is not None else None


def default_store() -> CalendarStore:
    path = os.getenv("CALENDAR_DB_PATH") or str(Path(__file__).with_name("calendar.db"))
    return CalendarStore(path)
