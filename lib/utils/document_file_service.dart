import 'dart:io';

import 'package:flutter/services.dart';

class DocumentFileService {
  static const MethodChannel _channel = MethodChannel('cqut/documents');

  static Future<String?> saveText({
    required String fileName,
    required String mimeType,
    required String content,
  }) async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('createTextDocument', {
      'fileName': fileName,
      'mimeType': mimeType,
      'content': content,
    });
  }

  static Future<String?> openText({
    String mimeType = 'application/json',
  }) async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('openTextDocument', {
      'mimeType': mimeType,
    });
  }
}
