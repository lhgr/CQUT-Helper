import 'package:cqut_helper/manager/cache_cleanup_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('logout cleanup removes only the selected account data', () async {
    SharedPreferences.setMockInitialValues({
      'account': 'u1',
      'user_info_u1': 'private-u1',
      'user_info_u2': 'private-u2',
      'schedule_u1_2026-2027-1_1': 'schedule-u1',
      'schedule_u2_2026-2027-1_1': 'schedule-u2',
      'schedule_fetch_at_u1_2026-2027-1_1': 1,
      'schedule_last_week_u1': '1',
      'schedule_widget_term_u1': '2026-2027-1',
      'schedule_pending_changes_u1': 'changes',
      'schedule_notice_state_u1_2026-2027-1': 'notices',
      'schedule_notice_login_marker_u1': 1,
      'schedule_last_successful_refresh_at_u1': '2026-08-01T00:00:00',
      'schedule_course_color_map_v1_u1|2026-2027-1': '{}',
      'schedule_show_weekend': true,
      'schedule_notice_api_base_url': 'https://notice.example.com',
    });

    final removed = await CacheCleanupManager.clearAccountData('u1');
    final prefs = await SharedPreferences.getInstance();

    expect(removed, 10);
    expect(prefs.getString('user_info_u1'), isNull);
    expect(prefs.getString('schedule_u1_2026-2027-1_1'), isNull);
    expect(prefs.getString('schedule_pending_changes_u1'), isNull);
    expect(prefs.getString('user_info_u2'), 'private-u2');
    expect(prefs.getString('schedule_u2_2026-2027-1_1'), 'schedule-u2');
    expect(prefs.getBool('schedule_show_weekend'), isTrue);
    expect(
      prefs.getString('schedule_notice_api_base_url'),
      'https://notice.example.com',
    );
  });

  test('empty account never matches preference keys', () {
    expect(
      CacheCleanupManager.isAccountScopedKey('schedule_anything', ''),
      isFalse,
    );
  });
}
