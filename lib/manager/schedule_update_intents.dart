import 'package:flutter/foundation.dart';

class ScheduleLocationRequest {
  final int token;
  final String userId;
  final String yearTerm;
  final String weekNum;

  const ScheduleLocationRequest({
    required this.token,
    required this.userId,
    required this.yearTerm,
    required this.weekNum,
  });
}

class ScheduleUpdateIntents {
  static final ValueNotifier<ScheduleLocationRequest?> openWeek = ValueNotifier(
    null,
  );
  static int _locationToken = 0;

  static void requestOpenWeek({
    required String userId,
    required String yearTerm,
    required String weekNum,
  }) {
    openWeek.value = ScheduleLocationRequest(
      token: ++_locationToken,
      userId: userId.trim(),
      yearTerm: yearTerm.trim(),
      weekNum: weekNum.trim(),
    );
  }

  static void consumeOpenWeek(ScheduleLocationRequest request) {
    if (openWeek.value?.token == request.token) openWeek.value = null;
  }

  static final ValueNotifier<int> openFromSystemNotification =
      ValueNotifier<int>(0);
  static final ValueNotifier<int> openChangesSheet = ValueNotifier<int>(0);
  static final ValueNotifier<int> scheduleUpdated = ValueNotifier<int>(0);

  static void requestOpenFromNotification() {
    openFromSystemNotification.value++;
  }

  static void requestOpenChangesSheet() {
    openChangesSheet.value++;
  }

  static void requestScheduleUpdated() {
    scheduleUpdated.value++;
  }
}
