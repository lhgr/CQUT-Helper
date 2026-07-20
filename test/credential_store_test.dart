import 'package:cqut_helper/manager/credential_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecureStorage implements SecureSecretStore {
  final Map<String, String> values = <String, String>{};
  int readCount = 0;
  int writeCount = 0;
  int deleteCount = 0;

  @override
  Future<String?> read(String key) async {
    readCount++;
    return values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    writeCount++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deleteCount++;
    values.remove(key);
  }
}

void main() {
  group('CredentialStore', () {
    test('returns encrypted password from secure storage when present', () async {
      SharedPreferences.setMockInitialValues({
        'encrypted_password': 'legacy-value',
      });
      final secureStore = _FakeSecureStorage()
        ..values['encrypted_password'] = 'secure-value';
      final store = CredentialStore(secureStore: secureStore);

      final encryptedPassword = await store.readEncryptedPassword();
      final prefs = await SharedPreferences.getInstance();

      expect(encryptedPassword, 'secure-value');
      expect(prefs.getString('encrypted_password'), 'legacy-value');
      expect(secureStore.writeCount, 0);
    });

    test('migrates legacy encrypted password into secure storage on first read', () async {
      SharedPreferences.setMockInitialValues({
        'encrypted_password': 'legacy-value',
      });
      final secureStore = _FakeSecureStorage();
      final store = CredentialStore(secureStore: secureStore);

      final encryptedPassword = await store.readEncryptedPassword();
      final prefs = await SharedPreferences.getInstance();

      expect(encryptedPassword, 'legacy-value');
      expect(secureStore.values['encrypted_password'], 'legacy-value');
      expect(prefs.getString('encrypted_password'), isNull);
      expect(secureStore.writeCount, 1);
    });

    test('clears secure and legacy encrypted password values together', () async {
      SharedPreferences.setMockInitialValues({
        'encrypted_password': 'legacy-value',
      });
      final secureStore = _FakeSecureStorage()
        ..values['encrypted_password'] = 'secure-value';
      final store = CredentialStore(secureStore: secureStore);

      await store.clearEncryptedPassword();
      final prefs = await SharedPreferences.getInstance();

      expect(secureStore.values['encrypted_password'], isNull);
      expect(prefs.getString('encrypted_password'), isNull);
      expect(secureStore.deleteCount, 1);
    });
  });
}
