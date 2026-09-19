import os
import tempfile
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from calendar_overrides import CalendarError, CalendarStore, parse_notice
from jwxt_automation import app


NOTICE_TITLE = "关于2026年中秋节、国庆节放假调休安排的通知"
NOTICE_BODY = """校属各单位：
一、放假时间
1.中秋节：9月25日（星期五）放假，共1天。
2.国庆节：9月29日（星期二）至10月7日（星期三）放假调休，共9天。
二、调休补课安排
1.9月20日（星期日）上班，按当天（校历第3周星期日）课表上课。
2.9月26日（星期六）上班，按9月29日（校历第5周星期二）课表上课。
3.9月27日（星期日）上班，按9月30日（校历第5周星期三）课表上课。
4.10月10日（星期六）上班，按10月7日（校历第6周星期三）课表上课。"""


class CalendarParserTests(unittest.TestCase):
    def test_2026_notice_expands_to_ten_holidays_and_four_teaching_days(self):
        items, complete, issues = parse_notice("2026-2027-1", NOTICE_TITLE, NOTICE_BODY)

        self.assertTrue(complete, issues)
        self.assertEqual([], issues)
        holidays = {item["date"] for item in items if item["kind"] == "holiday"}
        teaching = {
            item["date"]: item["schedule_date"]
            for item in items
            if item["kind"] == "teaching_day"
        }
        self.assertEqual(10, len(holidays))
        self.assertEqual(
            {
                "2026-09-25",
                *[f"2026-09-{day:02d}" for day in range(29, 31)],
                *[f"2026-10-{day:02d}" for day in range(1, 8)],
            },
            holidays,
        )
        self.assertEqual(
            {
                "2026-09-20": "2026-09-20",
                "2026-09-26": "2026-09-29",
                "2026-09-27": "2026-09-30",
                "2026-10-10": "2026-10-07",
            },
            teaching,
        )


class CalendarStoreTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.store = CalendarStore(os.path.join(self.temp_dir.name, "calendar.sqlite3"))

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_manual_upsert_and_suppress_take_precedence(self):
        notice = self.store.create_notice("2026-2027-1", NOTICE_TITLE, NOTICE_BODY)
        self.store.set_override("2026-2027-1", "2026-09-26", "suppress")
        self.store.set_override(
            "2026-2027-1",
            "2026-10-11",
            "upsert",
            "teaching_day",
            "2026-09-29",
            "临时补课",
        )

        draft = self.store.preview("2026-2027-1")
        by_date = {item["date"]: item for item in draft["days"]}
        self.assertNotIn("2026-09-26", by_date)
        self.assertEqual("2026-09-29", by_date["2026-10-11"]["schedule_date"])
        self.assertTrue(draft["publishable"])

        self.store.update_notice(notice["id"], "2026-2027-1", NOTICE_TITLE, NOTICE_BODY)
        self.store.delete_notice(notice["id"])
        after_delete = {
            item["date"]: item
            for item in self.store.preview("2026-2027-1")["days"]
        }
        self.assertNotIn("2026-09-26", after_delete)
        self.assertEqual("2026-09-29", after_delete["2026-10-11"]["schedule_date"])

    def test_only_publish_changes_public_revision_and_revision_is_stable(self):
        notice = self.store.create_notice("2026-2027-1", NOTICE_TITLE, NOTICE_BODY)
        self.assertIsNone(self.store.get_snapshot("2026-2027-1"))
        first = self.store.publish("2026-2027-1")
        self.assertEqual(
            first["revision"],
            self.store.get_snapshot("2026-2027-1")["revision"],
        )
        self.store.update_notice(notice["id"], "2026-2027-1", NOTICE_TITLE, NOTICE_BODY)
        self.assertEqual(
            first["revision"],
            self.store.get_snapshot("2026-2027-1")["revision"],
        )
        second = self.store.publish("2026-2027-1")
        self.assertEqual(first["revision"], second["revision"])

    def test_empty_complete_snapshot_can_be_published(self):
        self.store.set_override("2026-2027-1", "2026-09-25", "suppress")
        snapshot = self.store.publish("2026-2027-1")
        self.assertTrue(snapshot["term_calendar_complete"])
        self.assertEqual([], snapshot["days"])

    def test_override_dates_must_belong_to_academic_year(self):
        with self.assertRaises(CalendarError):
            self.store.set_override("2026-2027-1", "2025-08-31", "suppress")
        with self.assertRaises(CalendarError):
            self.store.set_override(
                "2026-2027-1",
                "2026-09-25",
                "upsert",
                "teaching_day",
                "2027-09-01",
                "补课",
            )

    def test_preview_reports_added_changed_and_removed_rules(self):
        self.store.create_notice("2026-2027-1", NOTICE_TITLE, NOTICE_BODY)
        self.store.publish("2026-2027-1")
        self.store.set_override("2026-2027-1", "2026-09-26", "suppress")
        self.store.set_override(
            "2026-2027-1",
            "2026-10-11",
            "upsert",
            "teaching_day",
            "2026-09-29",
            "临时补课",
        )
        self.store.set_override(
            "2026-2027-1",
            "2026-09-25",
            "upsert",
            "holiday",
            None,
            "中秋假期调整",
        )

        diff = self.store.preview("2026-2027-1")["diff"]
        self.assertEqual(["2026-10-11"], [item["date"] for item in diff["added"]])
        self.assertEqual(["2026-09-25"], [item["date"] for item in diff["changed"]])
        self.assertEqual(["2026-09-26"], [item["date"] for item in diff["removed"]])

    def test_conflict_and_incomplete_drafts_cannot_publish(self):
        self.store.create_notice(
            "2026-2027-1",
            "通知一",
            "中秋节：9月25日（星期五）放假，共1天。",
        )
        self.store.create_notice(
            "2026-2027-1",
            "通知二",
            "中秋节：9月25日（星期五）上班，按当天课表上课。",
        )
        conflict = self.store.preview("2026-2027-1")
        self.assertFalse(conflict["publishable"])
        self.assertTrue(conflict["conflicts"])
        with self.assertRaises(CalendarError):
            self.store.publish("2026-2027-1")

        incomplete_store = CalendarStore(
            os.path.join(self.temp_dir.name, "incomplete.sqlite3")
        )
        incomplete_store.create_notice(
            "2026-2027-1",
            "待确认",
            "本学期放假安排请以最终通知为准。",
        )
        incomplete = incomplete_store.preview("2026-2027-1")
        self.assertFalse(incomplete["publishable"])
        with self.assertRaises(CalendarError):
            incomplete_store.publish("2026-2027-1")


class CalendarApiTests(unittest.TestCase):
    def test_admin_bearer_publish_and_etag_not_modified(self):
        with tempfile.TemporaryDirectory() as temp_dir, patch.dict(
            os.environ,
            {
                "CALENDAR_DB_PATH": os.path.join(temp_dir, "calendar.sqlite3"),
                "CALENDAR_ADMIN_TOKEN": "test-token",
            },
            clear=False,
        ):
            old_store = getattr(app.state, "calendar_store", None)
            app.state.calendar_store = CalendarStore(os.environ["CALENDAR_DB_PATH"])
            try:
                client = TestClient(app)
                self.assertEqual(
                    401,
                    client.get(
                        "/admin/calendar/notices?year_term=2026-2027-1"
                    ).status_code,
                )
                headers = {"Authorization": "Bearer test-token"}
                created = client.post(
                    "/admin/calendar/notices",
                    headers=headers,
                    json={
                        "year_term": "2026-2027-1",
                        "title": NOTICE_TITLE,
                        "body": NOTICE_BODY,
                    },
                )
                self.assertEqual(200, created.status_code, created.text)
                published = client.post(
                    "/admin/calendar/publish",
                    headers=headers,
                    json={"year_term": "2026-2027-1"},
                )
                self.assertEqual(200, published.status_code, published.text)
                snapshot = client.get(
                    "/api/calendar/term-overrides?year_term=2026-2027-1"
                )
                self.assertEqual(200, snapshot.status_code, snapshot.text)
                self.assertEqual(14, len(snapshot.json()["data"]["days"]))
                etag = snapshot.headers["etag"]
                not_modified = client.get(
                    "/api/calendar/term-overrides?year_term=2026-2027-1",
                    headers={"If-None-Match": etag},
                )
                self.assertEqual(304, not_modified.status_code)
            finally:
                if old_store is None:
                    try:
                        del app.state.calendar_store
                    except AttributeError:
                        pass
                else:
                    app.state.calendar_store = old_store


if __name__ == "__main__":
    unittest.main()
