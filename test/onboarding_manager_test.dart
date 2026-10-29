import 'package:cqut_helper/manager/onboarding_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OnboardingManager', () {
    test('starts hidden and identifies a new user', () async {
      SharedPreferences.setMockInitialValues({});
      final manager = OnboardingManager();

      expect(manager.isNewUser, isFalse);
      expect(manager.scheduleReady, isFalse);
      expect(manager.showScheduleHint, isFalse);
      expect(manager.showOptionalFeatures, isFalse);

      await manager.initialize();

      expect(manager.isNewUser, isTrue);
      expect(manager.scheduleReady, isFalse);
      expect(manager.showScheduleHint, isFalse);
      expect(manager.showOptionalFeatures, isFalse);
    });

    test(
      'existing account or active timestamp identifies an old user',
      () async {
        for (final values in [
          <String, Object>{'account': 'existing-user'},
          <String, Object>{'app_last_active_at': 123},
        ]) {
          SharedPreferences.setMockInitialValues(values);
          final manager = OnboardingManager();

          await manager.initialize();

          expect(manager.isNewUser, isFalse);
        }
      },
    );

    test('login does not change persisted new-user eligibility', () async {
      SharedPreferences.setMockInitialValues({});
      final first = OnboardingManager();
      await first.initialize();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account', 'newly-signed-in-user');

      final recreated = OnboardingManager();
      await recreated.initialize();

      expect(first.isNewUser, isTrue);
      expect(recreated.isNewUser, isTrue);
    });

    test('dismissals are independent and persist across instances', () async {
      SharedPreferences.setMockInitialValues({});
      final manager = OnboardingManager();
      await manager.initialize();
      await manager.markScheduleReady();
      await manager.dismissScheduleHint();

      expect(manager.showScheduleHint, isFalse);
      expect(manager.showOptionalFeatures, isTrue);

      final recreated = OnboardingManager();
      await recreated.initialize();

      expect(recreated.showScheduleHint, isFalse);
      expect(recreated.showOptionalFeatures, isTrue);

      await recreated.dismissOptionalFeatures();
      final finalInstance = OnboardingManager();
      await finalInstance.initialize();
      expect(finalInstance.showOptionalFeatures, isFalse);
    });

    test(
      'concurrent initialization and readiness marking are idempotent',
      () async {
        SharedPreferences.setMockInitialValues({});
        final manager = OnboardingManager();
        await Future.wait([
          manager.initialize(),
          manager.initialize(),
          manager.markScheduleReady(),
          manager.markScheduleReady(),
        ]);

        expect(manager.isNewUser, isTrue);
        expect(manager.scheduleReady, isTrue);
        expect(manager.showScheduleHint, isTrue);
        expect(manager.showOptionalFeatures, isTrue);
      },
    );
  });
}
