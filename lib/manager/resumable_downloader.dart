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
  static const int _defaultSegmentBytes = 1024 * 1024;
  static const int _defaultRetryTimes = 3;

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
    bool segmented = false,
    int segmentBytes = _defaultSegmentBytes,
    int retryTimesPerSegment = _defaultRetryTimes,
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
          segmented: segmented,
          segmentBytes: segmentBytes,
          retryTimesPerSegment: retryTimesPerSegment,
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
    required bool segmented,
    required int segmentBytes,
    required int retryTimesPerSegment,
  }) async {
    if (segmented) {
      await _downloadBySegments(
        uri,
        savePath,
        onReceiveProgress: onReceiveProgress,
        cancelToken: cancelToken,
        options: options,
        segmentBytes: segmentBytes,
        retryTimesPerSegment: retryTimesPerSegment,
      );
      return;
    }
    await _downloadByStream(
      uri,
      savePath,
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
      options: options,
    );
  }

  Future<void> _downloadByStream(
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

  Future<void> _downloadBySegments(
    Uri uri,
    String savePath, {
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
    Options? options,
    required int segmentBytes,
    required int retryTimesPerSegment,
  }) async {
    final target = File(savePath);
    await target.parent.create(recursive: true);
    final partFile = File('$savePath.part');
    final baseOptions = (options ?? Options()).copyWith(
      responseType: ResponseType.stream,
      followRedirects: true,
      receiveTimeout: const Duration(minutes: 10),
      sendTimeout: const Duration(minutes: 2),
    );

    int totalBytes = -1;
    bool supportsRange = false;
    try {
      final headResp = await _dio.headUri(
        uri,
        options: baseOptions.copyWith(responseType: ResponseType.plain),
        cancelToken: cancelToken,
      );
      final lenHeader = headResp.headers.value(Headers.contentLengthHeader);
      totalBytes = int.tryParse(lenHeader ?? '') ?? -1;
      final acceptRanges =
          (headResp.headers.value('accept-ranges') ?? '').toLowerCase();
      supportsRange = acceptRanges.contains('bytes');
    } catch (_) {}

    if (!supportsRange || totalBytes <= 0) {
      await _downloadByStream(
        uri,
        savePath,
        onReceiveProgress: onReceiveProgress,
        cancelToken: cancelToken,
        options: options,
      );
      return;
    }

    if (!await partFile.exists()) {
      await partFile.create(recursive: true);
    }
    int received = await partFile.length();
    if (received > totalBytes) {
      await partFile.writeAsBytes(const []);
      received = 0;
    }
    onReceiveProgress?.call(received, totalBytes);
    if (received == totalBytes) {
      if (await target.exists()) {
        await target.delete();
      }
      await partFile.rename(savePath);
      return;
    }

    final raf = await partFile.open(mode: FileMode.append);
    try {
      while (received < totalBytes) {
        throwIfCancelled(cancelToken);
        final start = received;
        final end = (start + segmentBytes - 1).clamp(0, totalBytes - 1);
        int attempts = 0;
        while (true) {
          throwIfCancelled(cancelToken);
          try {
            final resp = await _dio.getUri<ResponseBody>(
              uri,
              options: baseOptions.copyWith(
                headers: {
                  ...?baseOptions.headers,
                  'range': 'bytes=$start-$end',
                },
              ),
              cancelToken: cancelToken,
            );
            final status = resp.statusCode ?? 0;
            if (status != 206) {
              throw HttpException('HTTP $status', uri: uri);
            }
            var segmentReceived = 0;
            await for (final chunk in resp.data!.stream) {
              throwIfCancelled(cancelToken);
              await raf.writeFrom(chunk);
              segmentReceived += chunk.length;
              received += chunk.length;
              onReceiveProgress?.call(received, totalBytes);
            }
            final expected = end - start + 1;
            if (segmentReceived != expected) {
              throw const HttpException('分段下载中断');
            }
            break;
          } catch (e) {
            attempts += 1;
            if (attempts >= retryTimesPerSegment) rethrow;
            await Future<void>.delayed(Duration(milliseconds: 250 * attempts));
            await raf.truncate(start);
            await raf.setPosition(start);
            received = start;
            onReceiveProgress?.call(received, totalBytes);
          }
        }
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

