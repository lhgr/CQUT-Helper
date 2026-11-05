import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DocumentFileService {
  static const MethodChannel _channel = MethodChannel('cqut/documents');

  static Future<String?> saveText({
    required String fileName,
    required String mimeType,
    required String content,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return null;
    }
    return _channel.invokeMethod<String>('createTextDocument', {
      'fileName': fileName,
      'mimeType': mimeType,
      'content': content,
    });
  }

  static Future<String?> openText({
    String mimeType = 'application/json',
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return null;
    }
    return _channel.invokeMethod<String>('openTextDocument', {
      'mimeType': mimeType,
    });
  }

  static Future<String?> exportFile({
    required String path,
    String? fileName,
    String mimeType = 'text/plain',
  }) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return path;
    return _channel.invokeMethod<String>('exportFile', {
      'path': path,
      'fileName': fileName ?? File(path).uri.pathSegments.last,
      'mimeType': mimeType,
    });
  }
}
