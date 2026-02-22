import 'package:flutter/foundation.dart';

class ScheduleUpdateIntents {
  static final ValueNotifier<int> openFromSystemNotification =
      ValueNotifier<int>(0);
  static final ValueNotifier<int> openChangesSheet = ValueNotifier<int>(0);

  static void requestOpenFromNotification() {
    openFromSystemNotification.value++;
  }

  static void requestOpenChangesSheet() {
    openChangesSheet.value++;
  }
}

