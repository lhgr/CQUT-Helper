import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/pkcs1.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/api.dart' show PublicKeyParameter;
import '../core/api_client.dart';

class _TimetableLoginState {
  DateTime? lastSuccessAt;
  Future<void>? inFlight;
}

class AuthApi {
  final ApiClient _client = ApiClient();

  static final Map<String, _TimetableLoginState> _timetableLoginStates = {};
  static const Duration _defaultTimetableLoginTtl = Duration(minutes: 30);

  static const String _casLogin1 =
      'https://uis.cqut.edu.cn/center-auth-server/sso/doLogin';
  static const String _casLogin2 =
      'https://uis.cqut.edu.cn/center-auth-server/YF8A4013/cas/login?service=https://timetable-cfc.cqut.edu.cn/api/auth/casLogin';

  static const String _publicKeyPem = '''-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDACwPDxYycdCiNeblZa9LjvDzb
iZU1vc9gKRcG/pGjZ/DJkI4HmoUE2r/o6SfB5az3s+H5JDzmOMVQ63hD7LZQGR4k
3iYWnCg3UpQZkZEtFtXBXsQHjKVJqCiEtK+gtxz4WnriDjf+e/CxJ7OD03e7sy5N
Y/akVmYNtghKZzz6jwIDAQAB
-----END PUBLIC KEY-----''';

  Future<void> login({
    required String account,
    required String password,
  }) async {
    final encryptedPwd = encryptPassword(password);
    await loginWithEncrypted(account: account, encryptedPassword: encryptedPwd);
  }

  Future<void> ensureTimetableLogin({
    required String account,
    String? password,
    String? encryptedPassword,
    Duration ttl = _defaultTimetableLoginTtl,
    bool force = false,
  }) async {
    if (encryptedPassword == null && password == null) {
      throw Exception('Password or encryptedPassword must be provided');
    }

    final state = _timetableLoginStates.putIfAbsent(
      account,
      () => _TimetableLoginState(),
    );

    if (!force && state.lastSuccessAt != null) {
      final age = DateTime.now().difference(state.lastSuccessAt!);
      if (age <= ttl) return;
    }

    final inFlight = state.inFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    state.inFlight = () async {
      if (encryptedPassword != null) {
        await loginWithEncrypted(account: account, encryptedPassword: encryptedPassword);
      } else {
        await login(account: account, password: password!);
      }
      state.lastSuccessAt = DateTime.now();
    }();

    try {
      await state.inFlight;
    } finally {
      state.inFlight = null;
    }
  }

  Future<void> loginWithEncrypted({
    required String account,
    required String encryptedPassword,
  }) async {
    final res1 = await _client.dio.post(
      _casLogin1,
      data: <String, dynamic>{
        'name': account,
        'pwd': encryptedPassword,
        'verifyCode': null,
        'universityId': '100005',
        'loginType': 'login',
      },
    );

    // 检查业务层面的错误
    if (res1.data is Map<String, dynamic>) {
      final data = res1.data as Map<String, dynamic>;
      if (data['code'] == -1) {
        throw Exception(data['msg'] ?? '登录失败');
      }
    }

    if (res1.statusCode == null || res1.statusCode! >= 400) {
      throw Exception('Login failed at step 1');
    }

    final res2 = await _client.getWithRedirects(_casLogin2);
    if (res2.statusCode == null || res2.statusCode! >= 400) {
      throw Exception('Login failed at step 2');
    }
  }

  String encryptPassword(String p) {
    if (p.trim().isEmpty) return '';

    final publicKey = _parsePublicKeyFromPem(_publicKeyPem);
    final cipher = PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

    final encryptedChunks = <String>[];
    final chunkSize = 29;
    for (int i = 0; i < p.length; i += chunkSize) {
      final end = min(i + chunkSize, p.length);
      final chunk = p.substring(i, end);
      final encrypted = cipher.process(Uint8List.fromList(utf8.encode(chunk)));
      encryptedChunks.add(base64.encode(encrypted));
    }

    final jsonStr = json.encode(encryptedChunks);
    return Uri.encodeComponent(jsonStr);
  }

  RSAPublicKey _parsePublicKeyFromPem(String pem) {
    final cleaned = pem
        .replaceAll('-----BEGIN PUBLIC KEY-----', '')
        .replaceAll('-----END PUBLIC KEY-----', '')
        .replaceAll(RegExp(r'\s'), '');
    final bytes = base64.decode(cleaned);

    final asn1Parser = ASN1Parser(Uint8List.fromList(bytes));
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    final publicKeyBitString = topLevelSeq.elements[1] as ASN1BitString;
    final publicKeyBytes = publicKeyBitString.contentBytes();

    final publicKeyParser = ASN1Parser(publicKeyBytes);
    final publicKeySeq = publicKeyParser.nextObject() as ASN1Sequence;
    final modulus = publicKeySeq.elements[0] as ASN1Integer;
    final exponent = publicKeySeq.elements[1] as ASN1Integer;

    return RSAPublicKey(modulus.valueAsBigInteger, exponent.valueAsBigInteger);
  }
}
