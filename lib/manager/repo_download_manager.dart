import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:cqut/api/github/github_api.dart';
import 'package:cqut/model/github_item.dart';
import 'package:cqut/utils/app_logger.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'repo_download_types.dart';
import 'resumable_downloader.dart';

export 'repo_download_types.dart';
export 'resumable_downloader.dart' show ResumableDownloader;

class RepoDownloadManager {
  static const String _tag = 'RepoDownloadManager';

  final GithubApi _api;
  final ResumableDownloader _downloader;
  final Future<Directory> Function()? _appDownloadDirResolver;
  final Future<Directory> Function()? _tempDirResolver;

  RepoDownloadManager({
    GithubApi? api,
    ResumableDownloader? downloader,
    Future<Directory> Function()? appDownloadDirResolver,
    Future<Directory> Function()? tempDirResolver,
  }) : _api = api ?? GithubApi(),
       _downloader = downloader ?? ResumableDownloader(),
       _appDownloadDirResolver = appDownloadDirResolver,
       _tempDirResolver = tempDirResolver;

  Future<Directory> resolveAppDownloadDir() async {
    final override = _appDownloadDirResolver;
    if (override != null) return override();

    Directory? downloadDir;
    if (Platform.isAndroid) {
      downloadDir = await getExternalStorageDirectory();
    } else {
      downloadDir = await getDownloadsDirectory();
    }

    if (downloadDir == null) {
      final baseDir = await getApplicationDocumentsDirectory();
      downloadDir = Directory(
        '${baseDir.path}${Platform.pathSeparator}downloads',
      );
    }

    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    final appDir = Directory(
      '${downloadDir.path}${Platform.pathSeparator}CQUT-Helper',
    );
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    return appDir;
  }

  String sanitizeFileName(String name) {
    final sanitized = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\u0000-\u001F]'), '_')
        .trim();
    return sanitized.isEmpty ? 'file' : sanitized;
  }

  String buildUniqueSavePath(String directoryPath, String fileName) {
    final safeName = sanitizeFileName(fileName);
    final dotIndex = safeName.lastIndexOf('.');
    final base = dotIndex > 0 ? safeName.substring(0, dotIndex) : safeName;
    final ext = dotIndex > 0 ? safeName.substring(dotIndex) : '';

    String candidate = '$directoryPath${Platform.pathSeparator}$safeName';
    int i = 1;
    while (File(candidate).existsSync() ||
        File('$candidate.part').existsSync()) {
      candidate = '$directoryPath${Platform.pathSeparator}$base ($i)$ext';
      i++;
    }
    return candidate;
  }

  Future<String> downloadFile({
    required GithubItem file,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    if (file.type == 'dir') {
      throw Exception('不支持下载文件夹：${file.path}');
    }

    final url = file.downloadUrl;
    if (url == null || url.isEmpty) {
      throw Exception('该文件没有可用的下载地址');
    }

    final appDir = await resolveAppDownloadDir();
    final savePath = buildUniqueSavePath(appDir.path, file.name);
    await _downloader.downloadFileResumable(
      Uri.parse(url),
      savePath,
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
    );
    return savePath;
  }

  Future<void> downloadUrlToPath({
    required Uri url,
    required String savePath,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) {
    return _downloader.downloadFileResumable(
      url,
      savePath,
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
    );
  }

  Future<RepoBatchDownloadResult> downloadFilesBatch({
    required List<GithubItem> files,
    int concurrency = 3,
    ValueChanged<RepoBatchDownloadProgress>? onProgress,
    CancelToken? cancelToken,
  }) async {
    final appDir = await resolveAppDownloadDir();
    final savedPaths = <String>[];

    final items = files.where((e) => e.type != 'dir').toList();
    int done = 0;
    final total = items.length;

    void report({String? name, int active = 0}) {
      final cb = onProgress;
      if (cb == null) return;
      cb(
        RepoBatchDownloadProgress(
          done: done,
          total: total,
          currentName: name,
          active: active,
        ),
      );
    }

    final effectiveConcurrency = max(1, min(concurrency, total));
    int nextIndex = 0;
    int active = 0;

    Future<void> runNext() async {
      throwIfCancelled(cancelToken);
      if (nextIndex >= items.length) return;
      final item = items[nextIndex++];
      active++;
      report(name: item.name, active: active);
      try {
        final url = item.downloadUrl;
        if (url == null || url.isEmpty) {
          throw Exception('文件缺少下载地址：${item.path}');
        }

        final savePath = buildUniqueSavePath(appDir.path, item.name);
        await _downloader.downloadFileResumable(
          Uri.parse(url),
          savePath,
          cancelToken: cancelToken,
        );
        savedPaths.add(savePath);
        done++;
      } finally {
        active--;
        report(active: active);
      }
      await runNext();
    }

    report(active: 0);
    await Future.wait(List.generate(effectiveConcurrency, (_) => runNext()));
    report(active: 0);
    return RepoBatchDownloadResult(
      directory: appDir,
      savedPaths: List.unmodifiable(savedPaths),
    );
  }

  Future<String> downloadItemsAsZip({
    required List<GithubItem> items,
    required String zipName,
    int concurrency = 3,
    RepoFolderDownloadProgress Function(RepoFolderDownloadProgress progress)?
    onProgress,
    CancelToken? cancelToken,
  }) async {
    final appDir = await resolveAppDownloadDir();
    final zipPath = buildUniqueSavePath(appDir.path, '$zipName.zip');
    final zipPartPath = '$zipPath.part';

    final sessionKey = sha1
        .convert(
          utf8.encode(
            '${items.map((e) => e.path).join('|')}|${DateTime.now().millisecondsSinceEpoch}',
          ),
        )
        .toString();
    final tempDir = await (_tempDirResolver?.call() ?? getTemporaryDirectory());
    final sessionDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}cqut_repo_sel_zip${Platform.pathSeparator}$sessionKey',
    );
    await sessionDir.create(recursive: true);

    final out = <_RepoFileEntry>[];
    final cb = onProgress;
    if (cb != null) {
      cb(
        RepoFolderDownloadProgress(
          phase: RepoDownloadPhase.listing,
          current: 0,
          total: items.length,
        ),
      );
    }

    for (final it in items) {
      throwIfCancelled(cancelToken);
      if (it.type == 'dir') {
        final sub = <_RepoFileEntry>[];
        await _listFilesRecursively(
          it.path,
          it.path,
          sub,
          onProgress: (current, total, name) {
            final cb2 = onProgress;
            if (cb2 == null) return;
            cb2(
              RepoFolderDownloadProgress(
                phase: RepoDownloadPhase.listing,
                current: current,
                total: total,
                currentName: name,
              ),
            );
          },
          cancelToken: cancelToken,
        );
        final prefix = sanitizeFileName(it.name);
        for (final e in sub) {
          out.add(
            _RepoFileEntry(
              item: e.item,
              relativePath: '$prefix/${e.relativePath}',
            ),
          );
        }
      } else {
        out.add(
          _RepoFileEntry(item: it, relativePath: sanitizeFileName(it.name)),
        );
      }
    }

    final totalFiles = out.length;
    int doneFiles = 0;
    final effectiveConcurrency = max(1, min(concurrency, totalFiles));
    int nextIndex = 0;

    void report(String? name) {
      final cb2 = onProgress;
      if (cb2 == null) return;
      cb2(
        RepoFolderDownloadProgress(
          phase: RepoDownloadPhase.downloading,
          current: doneFiles,
          total: totalFiles,
          currentName: name,
        ),
      );
    }

    Future<void> runNext() async {
      throwIfCancelled(cancelToken);
      if (nextIndex >= out.length) return;
      final entry = out[nextIndex++];
      report(entry.relativePath);

      final localPath = _joinPath(
        sessionDir.path,
        entry.relativePath.replaceAll('/', Platform.pathSeparator),
      );
      final localFile = File(localPath);
      await localFile.parent.create(recursive: true);
      if (await localFile.exists() && !await File('$localPath.part').exists()) {
        doneFiles++;
        report(entry.relativePath);
        return runNext();
      }

      final url = entry.item.downloadUrl;
      if (url == null || url.isEmpty) {
        throw Exception('文件缺少下载地址：${entry.item.path}');
      }

      await _downloader.downloadFileResumable(
        Uri.parse(url),
        localPath,
        cancelToken: cancelToken,
      );

      doneFiles++;
      report(entry.relativePath);
      await runNext();
    }

    if (totalFiles > 0) report(null);
    await Future.wait(List.generate(effectiveConcurrency, (_) => runNext()));

    if (onProgress != null) {
      onProgress(
        RepoFolderDownloadProgress(
          phase: RepoDownloadPhase.zipping,
          current: 0,
          total: totalFiles,
        ),
      );
    }

    final encoder = ZipFileEncoder();
    encoder.create(zipPartPath);
    try {
      for (final entry in out) {
        throwIfCancelled(cancelToken);
        final localPath = _joinPath(
          sessionDir.path,
          entry.relativePath.replaceAll('/', Platform.pathSeparator),
        );
        final file = File(localPath);
        if (await file.exists()) {
          await encoder.addFile(file, _zipPath(zipName, entry.relativePath));
        }
      }
    } finally {
      await encoder.close();
    }

    final zipFile = File(zipPartPath);
    if (await File(zipPath).exists()) {
      await File(zipPath).delete();
    }
    await zipFile.rename(zipPath);

    try {
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
      }
    } catch (_) {}

    return zipPath;
  }

  Future<String> downloadFolderAsZip({
    required String folderPath,
    required String folderName,
    int concurrency = 3,
    RepoFolderDownloadProgress Function(RepoFolderDownloadProgress progress)?
    onProgress,
    CancelToken? cancelToken,
  }) async {
    AppLogger.I.info(_tag, 'downloadFolderAsZip folderPath=$folderPath');

    final appDir = await resolveAppDownloadDir();
    final zipPath = buildUniqueSavePath(appDir.path, '$folderName.zip');
    final zipPartPath = '$zipPath.part';

    final sessionKey = sha1
        .convert(
          utf8.encode('$folderPath|${DateTime.now().millisecondsSinceEpoch}'),
        )
        .toString();
    final tempDir = await (_tempDirResolver?.call() ?? getTemporaryDirectory());
    final sessionDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}cqut_repo_zip${Platform.pathSeparator}$sessionKey',
    );
    await sessionDir.create(recursive: true);

    final items = <_RepoFileEntry>[];
    await _listFilesRecursively(
      folderPath,
      folderPath,
      items,
      onProgress: (current, total, name) {
        final cb = onProgress;
        if (cb == null) return;
        cb(
          RepoFolderDownloadProgress(
            phase: RepoDownloadPhase.listing,
            current: current,
            total: total,
            currentName: name,
          ),
        );
      },
      cancelToken: cancelToken,
    );

    final totalFiles = items.length;
    int doneFiles = 0;
    final effectiveConcurrency = max(1, min(concurrency, totalFiles));
    int nextIndex = 0;

    void report(String? name) {
      final cb = onProgress;
      if (cb == null) return;
      cb(
        RepoFolderDownloadProgress(
          phase: RepoDownloadPhase.downloading,
          current: doneFiles,
          total: totalFiles,
          currentName: name,
        ),
      );
    }

    Future<void> runNext() async {
      throwIfCancelled(cancelToken);
      if (nextIndex >= items.length) return;
      final entry = items[nextIndex++];
      report(entry.relativePath);

      final localPath = _joinPath(sessionDir.path, entry.relativePath);
      final localFile = File(localPath);
      await localFile.parent.create(recursive: true);
      if (await localFile.exists() && !await File('$localPath.part').exists()) {
        doneFiles++;
        report(entry.relativePath);
        return runNext();
      }

      final url = entry.item.downloadUrl;
      if (url == null || url.isEmpty) {
        throw Exception('文件缺少下载地址：${entry.item.path}');
      }

      await _downloader.downloadFileResumable(
        Uri.parse(url),
        localPath,
        cancelToken: cancelToken,
      );

      doneFiles++;
      report(entry.relativePath);
      await runNext();
    }

    if (totalFiles > 0) report(null);
    await Future.wait(List.generate(effectiveConcurrency, (_) => runNext()));

    final cb = onProgress;
    if (cb != null) {
      cb(
        RepoFolderDownloadProgress(
          phase: RepoDownloadPhase.zipping,
          current: 0,
          total: totalFiles,
        ),
      );
    }

    final encoder = ZipFileEncoder();
    encoder.create(zipPartPath);
    try {
      for (final entry in items) {
        throwIfCancelled(cancelToken);
        final localPath = _joinPath(sessionDir.path, entry.relativePath);
        final file = File(localPath);
        if (await file.exists()) {
          await encoder.addFile(file, _zipPath(folderName, entry.relativePath));
        }
      }
    } finally {
      await encoder.close();
    }

    final zipFile = File(zipPartPath);
    if (await File(zipPath).exists()) {
      await File(zipPath).delete();
    }
    await zipFile.rename(zipPath);

    try {
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
      }
    } catch (_) {}

    return zipPath;
  }

  Future<void> _listFilesRecursively(
    String currentPath,
    String rootPath,
    List<_RepoFileEntry> out, {
    required void Function(int current, int total, String? name) onProgress,
    CancelToken? cancelToken,
  }) async {
    throwIfCancelled(cancelToken);
    final items = await _api.getContents(currentPath);

    int visited = 0;
    for (final item in items) {
      throwIfCancelled(cancelToken);
      visited++;
      onProgress(visited, items.length, item.name);

      if (item.type == 'dir') {
        await _listFilesRecursively(
          item.path,
          rootPath,
          out,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
      } else {
        final relativePath = _toRelativePath(item.path, rootPath);
        out.add(_RepoFileEntry(item: item, relativePath: relativePath));
      }
    }
  }

  String _toRelativePath(String fullPath, String rootPath) {
    final root = rootPath.startsWith('/') ? rootPath.substring(1) : rootPath;
    final full = fullPath.startsWith('/') ? fullPath.substring(1) : fullPath;
    if (root.isEmpty) return full;
    if (!full.startsWith(root)) return full;
    final trimmed = full.substring(root.length);
    if (trimmed.startsWith('/')) return trimmed.substring(1);
    return trimmed;
  }

  String _joinPath(String a, String b) {
    final sep = Platform.pathSeparator;
    if (a.endsWith(sep)) return '$a$b';
    return '$a$sep$b';
  }

  String _zipPath(String rootName, String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    final safeRoot = sanitizeFileName(rootName);
    if (safeRoot.isEmpty) return normalized;
    return '$safeRoot/$normalized';
  }
}

class _RepoFileEntry {
  final GithubItem item;
  final String relativePath;

  const _RepoFileEntry({required this.item, required this.relativePath});
}

class RepoBatchDownloadResult {
  final Directory directory;
  final List<String> savedPaths;

  const RepoBatchDownloadResult({
    required this.directory,
    required this.savedPaths,
  });
}
