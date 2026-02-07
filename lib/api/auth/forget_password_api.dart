import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:pointycastle/api.dart' show PublicKeyParameter;
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/pkcs1.dart';
import 'package:pointycastle/asymmetric/rsa.dart';

import '../core/api_client.dart';

class ForgetPasswordApi {
  final ApiClient _client = ApiClient();

  static const String _baseUrl = 'https://uis.cqut.edu.cn';
  static const String _appKey = 'uap-web-key';
  static const String _appSecret = 'uap-web-secret';
  static const String _universityId = '100005';
  static const String _clientCategory = 'PC';

  static const String _publicKeyPem = '''-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDACwPDxYycdCiNeblZa9LjvDzb
iZU1vc9gKRcG/pGjZ/DJkI4HmoUE2r/o6SfB5az3s+H5JDzmOMVQ63hD7LZQGR4k
3iYWnCg3UpQZkZEtFtXBXsQHjKVJqCiEtK+gtxz4WnriDjf+e/CxJ7OD03e7sy5N
Y/akVmYNtghKZzz6jwIDAQAB
-----END PUBLIC KEY-----''';

  Future<String> sendAuthCode({required String mobilePhone}) async {
    final base = _baseParams();
    final params = <String, String>{...base, 'mobilePhone': mobilePhone};

    final secretParam = _buildSecretParam(params);
    final signedParams = <String, String>{
      ...params,
      'secretParam': secretParam,
    };
    final sign = _buildSign(signedParams);

    final url = _buildUrl(
      '/ump/common/login/forgetPassword/sendAuthCode',
      <String, String>{...signedParams, 'sign': sign},
    );

    final resp = await _client.dio.post(
      url,
      options: _formUrlEncodedOptions(),
      data: null,
    );

    final data = _asJsonMap(resp.data);
    _ensureBizSuccess(data);
    final content = data['content'];
    if (content is Map<String, dynamic>) {
      final ticket = content['ticket']?.toString();
      if (ticket != null && ticket.isNotEmpty) return ticket;
    }
    throw Exception('发送验证码失败：缺少 ticket');
  }

  Future<void> checkAuthCode({
    required String ticket,
    required String authCode,
  }) async {
    final base = _baseParams();
    final params = <String, String>{...base, 'authCode': authCode};

    final secretParam = _buildSecretParam(params);
    final signedParams = <String, String>{
      ...params,
      'secretParam': secretParam,
    };
    final sign = _buildSign(signedParams);

    final url = _buildUrl(
      '/ump/common/login/forgetPassword/checkAuthCode/$ticket',
      <String, String>{...signedParams, 'sign': sign},
    );

    final resp = await _client.dio.post(
      url,
      options: _formUrlEncodedOptions(),
      data: null,
    );

    final data = _asJsonMap(resp.data);
    _ensureBizSuccess(data);
  }

  Future<void> setNewPassword({
    required String ticket,
    required String password,
  }) async {
    final base = _baseParams();
    final params = <String, String>{...base, 'password': password};

    final secretParam = _buildSecretParam(params);
    final signedParams = <String, String>{
      ...params,
      'secretParam': secretParam,
    };
    final sign = _buildSign(signedParams);

    final url = _buildUrl(
      '/ump/common/login/forgetPassword/setNewPassword/$ticket',
      <String, String>{...signedParams, 'sign': sign},
    );

    final resp = await _client.dio.post(
      url,
      options: _formUrlEncodedOptions(),
      data: null,
    );

    final data = _asJsonMap(resp.data);
    _ensureBizSuccess(data);
  }

  Map<String, String> _baseParams() {
    final nonce = _randomDigits(14);
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    return <String, String>{
      'universityId': _universityId,
      'appKey': _appKey,
      'timestamp': timestamp,
      'nonce': nonce,
      'clientCategory': _clientCategory,
    };
  }

  String _randomDigits(int length) {
    final r = Random.secure();
    final buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      final digit = r.nextInt(10);
      if (i == 0 && digit == 0) {
        buffer.write(r.nextInt(9) + 1);
      } else {
        buffer.write(digit);
      }
    }
    return buffer.toString();
  }

  String _buildSecretParam(Map<String, String> params) {
    final plain = json.encode(params);
    final publicKey = _parsePublicKeyFromPem(_publicKeyPem);
    final cipher = PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

    final chunks = <String>[];
    const chunkSize = 29;
    for (int i = 0; i < plain.length; i += chunkSize) {
      final end = min(i + chunkSize, plain.length);
      final chunk = plain.substring(i, end);
      final encrypted = cipher.process(Uint8List.fromList(utf8.encode(chunk)));
      final encoded = Uri.encodeComponent(base64.encode(encrypted));
      chunks.add('%22$encoded%22');
    }

    return '[${chunks.join(',')}]';
  }

  String _buildSign(Map<String, String> params) {
    final keys = params.keys.toList()..sort();
    final buffer = StringBuffer();
    for (int i = 0; i < keys.length; i++) {
      final k = keys[i];
      final v = params[k] ?? '';
      if (i > 0) buffer.write('&');
      buffer.write('$k=$v');
    }
    buffer.write('&appSecret=$_appSecret');
    return md5.convert(utf8.encode(buffer.toString())).toString().toUpperCase();
  }

  String _buildUrl(String path, Map<String, String> params) {
    final keys = params.keys.toList()..sort();
    final parts = <String>[];
    for (final k in keys) {
      final v = params[k] ?? '';
      if (k == 'secretParam') {
        parts.add('$k=$v');
      } else {
        parts.add('$k=${Uri.encodeQueryComponent(v)}');
      }
    }
    return '$_baseUrl$path?${parts.join('&')}';
  }

  Options _formUrlEncodedOptions() {
    return Options(contentType: Headers.formUrlEncodedContentType);
  }

  Map<String, dynamic> _asJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) return json.decode(data) as Map<String, dynamic>;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw Exception('响应格式异常');
  }

  void _ensureBizSuccess(Map<String, dynamic> data) {
    final code = data['code'];
    final codeStr = code?.toString();
    if (codeStr == '40001') return;
    final message = data['message']?.toString() ?? '操作失败';
    throw Exception(message);
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
