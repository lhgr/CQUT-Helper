import 'package:cqut_helper/api/auth/auth_api.dart';
import 'package:cqut_helper/manager/cache_cleanup_manager.dart';
import 'package:cqut_helper/manager/course_color_assignment_manager.dart';
import 'package:cqut_helper/manager/credential_store.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountSessionManager {
  AccountSessionManager({CredentialStore? credentialStore, AuthApi? authApi})
    : _credentialStore = credentialStore ?? CredentialStore(),
      _authApi = authApi ?? AuthApi();

  final CredentialStore _credentialStore;
  final AuthApi _authApi;

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = (prefs.getString('account') ?? '').trim();
    Object? firstError;

    Future<void> runCleanupStep(
      String step,
      Future<void> Function() action,
    ) async {
      try {
        await action();
      } catch (error, stackTrace) {
        firstError ??= error;
        AppLogger.I.warn(
          'AccountSession',
          'logout cleanup step failed',
          error: error,
          stackTrace: stackTrace,
          fields: {'step': step},
        );
      }
    }

    // Stop future work before removing cached account data. Clearing consent
    // prevents a different account from inheriting background credential use.
    await runCleanupStep(
      'disable_notice_enhancement',
      ScheduleSettingsManager.disableNoticeEnhancementForLogout,
    );
    await runCleanupStep('remove_account', () async {
      await prefs.remove('account');
    });
    await runCleanupStep(
      'clear_credential',
      _credentialStore.clearEncryptedPassword,
    );
    await runCleanupStep(
      'reset_login_context',
      () => _authApi.resetLoginContext(account: userId),
    );
    await runCleanupStep(
      'cancel_background_work',
      ScheduleUpdateWorker.syncFromPreferences,
    );
    if (userId.isNotEmpty) {
      await runCleanupStep('clear_account_cache', () async {
        await CacheCleanupManager.clearAccountData(userId);
      });
      await runCleanupStep('clear_schedule_customizations', () async {
        await ScheduleCustomizationManager.instance.clearUserData(userId);
      });
    }
    CourseColorAssignmentManager.instance.resetInMemoryCache();
    await runCleanupStep('cancel_notifications', LocalNotifications.cancelAll);
    await runCleanupStep(
      'clear_widgets',
      () => WidgetUpdater.updateTodayWidget(trigger: 'logout'),
    );

    AppLogger.I.info(
      'AccountSession',
      'logout cleanup completed',
      fields: {'hadAccount': userId.isNotEmpty, 'complete': firstError == null},
    );
    if (firstError != null) {
      throw StateError('logout cleanup incomplete');
    }
  }
}
