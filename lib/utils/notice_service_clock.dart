/// The notice service closes between 00:00 and 07:00 in Beijing time.
bool isNoticeServiceQuietHours(DateTime instant) {
  final hour = instant.toUtc().add(const Duration(hours: 8)).hour;
  return hour < 7;
}
