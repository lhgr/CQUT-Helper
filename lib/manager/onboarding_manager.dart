import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingManager extends ChangeNotifier {
  OnboardingManager();

  static final OnboardingManager instance = OnboardingManager();

  static const _eligibilityKey = 'onboarding_is_new_user';
  static const _scheduleReadyKey = 'onboarding_schedule_ready';
  static const _scheduleHintDismissedKey = 'onboarding_schedule_hint_dismissed';
  static const _optionalFeaturesDismissedKey =
      'onboarding_optional_features_dismissed';

  Future<void>? _initialization;
  bool _initialized = false;
  bool _isNewUser = false;
  bool _scheduleReady = false;
  bool _scheduleHintDismissed = false;
  bool _optionalFeaturesDismissed = false;

  bool get isNewUser => _initialized && _isNewUser;
  bool get scheduleReady => _initialized && _scheduleReady;
  bool get showScheduleHint =>
      _initialized && _isNewUser && _scheduleReady && !_scheduleHintDismissed;
  bool get showOptionalFeatures =>
      _initialized &&
      _isNewUser &&
      _scheduleReady &&
      !_optionalFeaturesDismissed;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final eligibility = prefs.getBool(_eligibilityKey);
    _isNewUser =
        eligibility ??
        !((prefs.getString('account')?.isNotEmpty ?? false) ||
            prefs.containsKey('app_last_active_at'));
    if (eligibility == null) {
      await prefs.setBool(_eligibilityKey, _isNewUser);
    }
    _scheduleReady = prefs.getBool(_scheduleReadyKey) ?? false;
    _scheduleHintDismissed = prefs.getBool(_scheduleHintDismissedKey) ?? false;
    _optionalFeaturesDismissed =
        prefs.getBool(_optionalFeaturesDismissedKey) ?? false;
    _initialized = true;
    notifyListeners();
  }

  Future<void> markScheduleReady() async {
    await initialize();
    if (_scheduleReady) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_scheduleReadyKey, true);
    _scheduleReady = true;
    notifyListeners();
  }

  Future<void> dismissScheduleHint() async {
    await initialize();
    if (_scheduleHintDismissed) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_scheduleHintDismissedKey, true);
    _scheduleHintDismissed = true;
    notifyListeners();
  }

  Future<void> dismissOptionalFeatures() async {
    await initialize();
    if (_optionalFeaturesDismissed) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_optionalFeaturesDismissedKey, true);
    _optionalFeaturesDismissed = true;
    notifyListeners();
  }
}
