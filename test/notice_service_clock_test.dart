import 'package:cqut_helper/utils/notice_service_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notice quiet hours use Beijing midnight and 07:00 regardless of input offset', () {
    expect(
      isNoticeServiceQuietHours(DateTime.parse('2026-11-12T15:59:59Z')),
      isFalse,
    );
    expect(
      isNoticeServiceQuietHours(DateTime.parse('2026-11-12T16:00:00Z')),
      isTrue,
    );
    expect(
      isNoticeServiceQuietHours(DateTime.parse('2026-11-12T22:59:59Z')),
      isTrue,
    );
    expect(
      isNoticeServiceQuietHours(DateTime.parse('2026-11-12T23:00:00Z')),
      isFalse,
    );
    expect(
      isNoticeServiceQuietHours(DateTime.parse('2026-11-12T18:00:00-05:00')),
      isFalse,
    );
  });
}
