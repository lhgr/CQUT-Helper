import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class SecureSecretStore {
  Future<String?> read(String key);

  Future<void> write({required String key, required String value});

  Future<void> delete(String key);
}

class FlutterSecureSecretStore implements SecureSecretStore {
  FlutterSecureSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) {
    return _storage.read(key: key);
  }

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) {
    return _storage.delete(key: key);
  }
}

class CredentialStore {
  CredentialStore({
    SecureSecretStore? secureStore,
    Future<SharedPreferences> Function()? prefsProvider,
  }) : secureStore = secureStore ?? FlutterSecureSecretStore(),
       _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  static const String encryptedPasswordKey = 'encrypted_password';

  final SecureSecretStore secureStore;
  final Future<SharedPreferences> Function() _prefsProvider;

  Future<String?> readEncryptedPassword() async {
    final secureValue = await secureStore.read(encryptedPasswordKey);
    if (secureValue != null && secureValue.trim().isNotEmpty) {
      return secureValue;
    }

    final prefs = await _prefsProvider();
    final legacyValue = prefs.getString(encryptedPasswordKey);
    if (legacyValue == null || legacyValue.trim().isEmpty) {
      return null;
    }

    await secureStore.write(key: encryptedPasswordKey, value: legacyValue);
    await prefs.remove(encryptedPasswordKey);
    return legacyValue;
  }

  Future<void> writeEncryptedPassword(String value) async {
    await secureStore.write(key: encryptedPasswordKey, value: value);
    final prefs = await _prefsProvider();
    await prefs.remove(encryptedPasswordKey);
  }

  Future<void> clearEncryptedPassword() async {
    await secureStore.delete(encryptedPasswordKey);
    final prefs = await _prefsProvider();
    await prefs.remove(encryptedPasswordKey);
  }
}
