import 'dart:io';

import 'package:cqut/utils/app_logger.dart';
import 'package:cqut/utils/github_proxy.dart';
import 'package:dio/dio.dart';

void throwIfCancelled(CancelToken? token) {
  if (token == null) return;
  if (!token.isCancelled) return;
  throw DioException(
    requestOptions: RequestOptions(path: ''),
    type: DioExceptionType.cancel,
    error: token.cancelError,
  );
}

class ResumableDownloader {
  static const String _tag = 'ResumableDownloader';

  final Dio _dio;

  ResumableDownloader({Dio? dio}) : _dio = dio ?? Dio() {
    AppLogger.I.attachToDio(_dio, tag: _tag);
  }

  Future<void> downloadFileResumable(
    Uri raw,
    String savePath, {
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
    Options? options,
  }) async {
    final candidates = <Uri>[raw];
    if (GithubProxy.isGithubUri(raw) && !GithubProxy.isWorkerUri(raw)) {
      candidates
        ..clear()
        ..add(GithubProxy.proxyUriOf(raw))
        ..add(raw);
    }

    Object? lastError;
    for (final uri in candidates) {
      try {
        await _downloadSingle(
          uri,
          savePath,
          onReceiveProgress: onReceiveProgress,
          cancelToken: cancelToken,
          options: options,
        );
        return;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('下载失败');
  }

  Future<void> _downloadSingle(
    Uri uri,
    String savePath, {
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
    Options? options,
  }) async {
    final target = File(savePath);
    await target.parent.create(recursive: true);

    final partPath = '$savePath.part';
    final partFile = File(partPath);

    int existing = 0;
    if (await partFile.exists()) {
      existing = await partFile.length();
    }

    final baseOptions = (options ?? Options()).copyWith(
      responseType: ResponseType.stream,
      followRedirects: true,
      receiveTimeout: const Duration(minutes: 10),
      sendTimeout: const Duration(minutes: 2),
    );

    final headers = <String, dynamic>{...?baseOptions.headers};
    if (existing > 0) {
      headers['range'] = 'bytes=$existing-';
    }

    final resp = await _dio.getUri<ResponseBody>(
      uri,
      options: baseOptions.copyWith(headers: headers),
      cancelToken: cancelToken,
    );

    final status = resp.statusCode ?? 0;
    if (status < 200 || status >= 400) {
      throw HttpException('HTTP $status', uri: uri);
    }

    final acceptPartial = status == 206 && existing > 0;
    if (!acceptPartial && existing > 0) {
      existing = 0;
    }

    final raf = await partFile.open(
      mode: acceptPartial ? FileMode.append : FileMode.write,
    );

    int received = existing;
    final contentLength = int.tryParse(
      resp.headers.value(Headers.contentLengthHeader) ?? '',
    );
    final total = contentLength == null
        ? -1
        : (status == 206 ? existing + contentLength : contentLength);

    try {
      final stream = resp.data!.stream;
      await for (final chunk in stream) {
        throwIfCancelled(cancelToken);
        await raf.writeFrom(chunk);
        received += chunk.length;
        onReceiveProgress?.call(received, total);
      }
    } finally {
      await raf.close();
    }

    if (await target.exists()) {
      await target.delete();
    }
    await partFile.rename(savePath);
  }
}

