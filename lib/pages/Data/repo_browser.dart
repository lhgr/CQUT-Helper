import 'dart:io';

import 'package:cqut/api/github/github_api.dart';
import 'package:cqut/manager/repo_download_manager.dart';
import 'package:cqut/manager/cache_cleanup_manager.dart';
import 'package:cqut/manager/favorites_manager.dart';
import 'package:cqut/model/github_item.dart';
import 'package:cqut/pages/Data/repo_file_preview.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cqut/utils/github_proxy.dart';

class RepoBrowserPage extends StatefulWidget {
  final String path;
  final String title;

  const RepoBrowserPage({super.key, required this.path, required this.title});

  @override
  State<RepoBrowserPage> createState() => _RepoBrowserPageState();
}

class _RepoBrowserPageState extends State<RepoBrowserPage> {
  final GithubApi _githubApi = GithubApi();
  final RepoDownloadManager _downloadManager = RepoDownloadManager();
  static const MethodChannel _downloadsChannel = MethodChannel(
    'cqut/downloads',
  );
  late Future<List<GithubItem>> _contentsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchText = "";
  final FavoritesManager _favoritesManager = FavoritesManager();
  int _lastFavoritesCacheEpoch = CacheCleanupManager.favoritesCacheEpoch.value;
  bool _selectionMode = false;
  final Set<String> _selectedPaths = {};
  List<GithubItem> _currentItems = const [];

  @override
  void initState() {
    super.initState();
    _contentsFuture = _githubApi.getContents(widget.path);
    _favoritesManager.init(); // Ensure initialized if accessed directly
    CacheCleanupManager.favoritesCacheEpoch.addListener(
      _onFavoritesCacheCleared,
    );
  }

  @override
  void dispose() {
    CacheCleanupManager.favoritesCacheEpoch.removeListener(
      _onFavoritesCacheCleared,
    );
    _searchController.dispose();
    super.dispose();
  }

  void _onFavoritesCacheCleared() {
    final epoch = CacheCleanupManager.favoritesCacheEpoch.value;
    if (epoch == _lastFavoritesCacheEpoch) return;
    _lastFavoritesCacheEpoch = epoch;
    if (!mounted) return;
    _favoritesManager.init();
    setState(() {});
  }

  void _navigateToSubDir(GithubItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            RepoBrowserPage(path: item.path, title: item.name),
      ),
    );
  }

  void _enterSelectionMode() {
    setState(() {
      _selectionMode = true;
      _selectedPaths.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
    });
  }

  void _toggleSelected(GithubItem item) {
    setState(() {
      if (_selectedPaths.contains(item.path)) {
        _selectedPaths.remove(item.path);
      } else {
        _selectedPaths.add(item.path);
      }
    });
  }

  void _selectAllItems() {
    setState(() {
      _selectedPaths
        ..clear()
        ..addAll(_currentItems.map((e) => e.path));
    });
  }

  String _sanitizeFileName(String name) {
    final sanitized = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\u0000-\u001F]'), '_')
        .trim();
    return sanitized.isEmpty ? 'file' : sanitized;
  }

  Future<Map<String, dynamic>?> _enqueueAndroidDownload({
    required String url,
    required String fileName,
  }) {
    return _downloadsChannel.invokeMapMethod<String, dynamic>(
      'enqueueDownload',
      {'url': url, 'fileName': _sanitizeFileName(fileName)},
    );
  }

  Future<Map<String, dynamic>?> _exportToAndroidDownloads({
    required String srcPath,
    required String fileName,
    String? mimeType,
  }) {
    return _downloadsChannel.invokeMapMethod<String, dynamic>(
      'exportToDownloads',
      {
        'srcPath': srcPath,
        'fileName': _sanitizeFileName(fileName),
        if (mimeType != null) 'mimeType': mimeType,
      },
    );
  }

  Future<void> _downloadFile(GithubItem item) async {
    if (item.type == 'dir') {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('文件夹不支持下载')));
      }
      return;
    }

    final url = item.downloadUrl;
    if (url == null || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('该文件没有可用的下载地址')));
      }
      return;
    }

    if (Platform.isAndroid) {
      try {
        final preferredUrl = await GithubProxy.preferUrl(url);
        final res = await _enqueueAndroidDownload(
          url: preferredUrl,
          fileName: item.name,
        );
        if (!mounted) return;
        final savedPath = res?['path']?.toString();
        final message = savedPath == null || savedPath.isEmpty
            ? '文件已保存在 /Download/CQUT-Helper 中'
            : '文件已保存在 /Download/CQUT-Helper 中';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('下载失败：$e')));
      }
      return;
    }

    final appDownloadDir = await _downloadManager.resolveAppDownloadDir();
    final savePath = _downloadManager.buildUniqueSavePath(
      appDownloadDir.path,
      item.name,
    );

    StateSetter? dialogSetState;
    double? progress;
    final cancelToken = CancelToken();
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              dialogSetState = setState;
              final percent = progress == null
                  ? null
                  : (progress! * 100).toStringAsFixed(0);
              return AlertDialog(
                title: Text('正在下载'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('保存到：${appDownloadDir.path}'),
                    SizedBox(height: 8),
                    Text(item.name),
                    SizedBox(height: 12),
                    LinearProgressIndicator(value: progress),
                    SizedBox(height: 8),
                    Text(percent == null ? '请稍候…' : '$percent%'),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      cancelToken.cancel('user_cancelled');
                    },
                    child: Text('取消'),
                  ),
                ],
              );
            },
          );
        },
      );
    }

    try {
      await _downloadManager.downloadUrlToPath(
        url: Uri.parse(url),
        savePath: savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          final next = received / total;
          final updater = dialogSetState;
          if (updater != null) {
            updater(() {
              progress = next.clamp(0.0, 1.0);
            });
          }
        },
      );

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        final msg = e is DioException && CancelToken.isCancel(e)
            ? '已取消下载'
            : '下载失败：$e';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _downloadFolderZip(GithubItem item) async {
    if (item.type != 'dir') return;

    final cancelToken = CancelToken();
    RepoFolderDownloadProgress? progress;
    StateSetter? dialogSetState;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              dialogSetState = setState;

              final p = progress;
              String phaseText = '准备中…';
              double? value;

              if (p != null) {
                switch (p.phase) {
                  case RepoDownloadPhase.listing:
                    phaseText = '正在扫描文件…';
                    value = null;
                    break;
                  case RepoDownloadPhase.downloading:
                    phaseText = '正在下载文件…';
                    value = p.total <= 0 ? null : (p.current / p.total);
                    break;
                  case RepoDownloadPhase.zipping:
                    phaseText = '正在打包 ZIP…';
                    value = null;
                    break;
                }
              }

              final detail = p?.currentName;
              final countText = p == null
                  ? null
                  : (p.total <= 0 ? '${p.current}' : '${p.current}/${p.total}');

              return AlertDialog(
                title: Text('下载文件夹'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(phaseText),
                    SizedBox(height: 12),
                    LinearProgressIndicator(value: value?.clamp(0.0, 1.0)),
                    SizedBox(height: 8),
                    if (countText != null) Text(countText),
                    if (detail != null) ...[SizedBox(height: 8), Text(detail)],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      cancelToken.cancel('user_cancelled');
                    },
                    child: Text('取消'),
                  ),
                ],
              );
            },
          );
        },
      );
    }

    try {
      final zipPath = await _downloadManager.downloadFolderAsZip(
        folderPath: item.path,
        folderName: item.name,
        cancelToken: cancelToken,
        onProgress: (p) {
          final updater = dialogSetState;
          if (updater != null) {
            updater(() {
              progress = p;
            });
          } else {
            progress = p;
          }
          return p;
        },
      );

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        final messenger = ScaffoldMessenger.of(context);
        if (Platform.isAndroid) {
          final fileName = zipPath.split(Platform.pathSeparator).last;
          final res = await _downloadsChannel.invokeMapMethod<String, dynamic>(
            'exportToDownloads',
            {
              'srcPath': zipPath,
              'fileName': fileName,
              'mimeType': 'application/zip',
            },
          );
          if (!mounted) return;
          final savedPath = res?['path']?.toString();
          if (savedPath != null && savedPath.isNotEmpty) {
            try {
              await File(zipPath).delete();
            } catch (_) {}
            messenger.showSnackBar(SnackBar(content: Text('已保存：$savedPath')));
          } else {
            messenger.showSnackBar(SnackBar(content: Text('已保存：$zipPath')));
          }
        } else {
          messenger.showSnackBar(SnackBar(content: Text('已保存：$zipPath')));
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        final msg = e is DioException && CancelToken.isCancel(e)
            ? '已取消下载'
            : '下载失败：$e';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _downloadSelected() async {
    final selected = _currentItems
        .where((e) => _selectedPaths.contains(e.path))
        .toList();
    if (selected.isEmpty) return;
    if (selected.any((e) => e.type == 'dir')) {
      return _downloadSelectedAsZip(selected);
    }
    return _downloadSelectedFiles(selected);
  }

  Future<void> _downloadSelectedFiles(List<GithubItem> files) async {
    if (files.isEmpty) return;

    final cancelToken = CancelToken();
    RepoBatchDownloadProgress? progress;
    StateSetter? dialogSetState;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              dialogSetState = setState;
              final p = progress;
              final value = p == null || p.total <= 0
                  ? null
                  : (p.done / p.total);
              final title = p == null ? '批量下载' : '批量下载（${p.done}/${p.total}）';

              return AlertDialog(
                title: Text(title),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: value?.clamp(0.0, 1.0)),
                    SizedBox(height: 12),
                    Text(p?.currentName ?? '准备中…'),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      cancelToken.cancel('user_cancelled');
                    },
                    child: Text('取消'),
                  ),
                ],
              );
            },
          );
        },
      );
    }

    try {
      final batch = await _downloadManager.downloadFilesBatch(
        files: files,
        concurrency: 3,
        cancelToken: cancelToken,
        onProgress: (p) {
          final updater = dialogSetState;
          if (updater != null) {
            updater(() {
              progress = p;
            });
          } else {
            progress = p;
          }
        },
      );

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        final messenger = ScaffoldMessenger.of(context);
        if (Platform.isAndroid) {
          int exported = 0;
          for (final path in batch.savedPaths) {
            final fileName = path.split(Platform.pathSeparator).last;
            final res = await _exportToAndroidDownloads(
              srcPath: path,
              fileName: fileName,
            );
            final savedPath = res?['path']?.toString();
            if (savedPath != null && savedPath.isNotEmpty) {
              exported++;
              try {
                await File(path).delete();
              } catch (_) {}
            }
          }
          if (!mounted) return;
          if (exported > 0) {
            messenger.showSnackBar(
              SnackBar(content: Text('已保存到：/Download/CQUT-Helper/')),
            );
            _exitSelectionMode();
            return;
          }
        }
        messenger.showSnackBar(SnackBar(content: Text('已保存到：${batch.directory.path}')));
        _exitSelectionMode();
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        final msg = e is DioException && CancelToken.isCancel(e)
            ? '已取消下载'
            : '下载失败：$e';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _downloadSelectedAsZip(List<GithubItem> selected) async {
    if (selected.isEmpty) return;

    final cancelToken = CancelToken();
    RepoFolderDownloadProgress? progress;
    StateSetter? dialogSetState;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              dialogSetState = setState;

              final p = progress;
              String phaseText = '准备中…';
              double? value;

              if (p != null) {
                switch (p.phase) {
                  case RepoDownloadPhase.listing:
                    phaseText = '正在扫描文件…';
                    value = null;
                    break;
                  case RepoDownloadPhase.downloading:
                    phaseText = '正在下载文件…';
                    value = p.total <= 0 ? null : (p.current / p.total);
                    break;
                  case RepoDownloadPhase.zipping:
                    phaseText = '正在打包 ZIP…';
                    value = null;
                    break;
                }
              }

              final detail = p?.currentName;
              final countText = p == null
                  ? null
                  : (p.total <= 0 ? '${p.current}' : '${p.current}/${p.total}');

              return AlertDialog(
                title: Text('批量下载（ZIP）'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(phaseText),
                    SizedBox(height: 12),
                    LinearProgressIndicator(value: value?.clamp(0.0, 1.0)),
                    SizedBox(height: 8),
                    if (countText != null) Text(countText),
                    if (detail != null) ...[SizedBox(height: 8), Text(detail)],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      cancelToken.cancel('user_cancelled');
                    },
                    child: Text('取消'),
                  ),
                ],
              );
            },
          );
        },
      );
    }

    try {
      final zipPath = await _downloadManager.downloadItemsAsZip(
        items: selected,
        zipName: '${widget.title}_selected',
        concurrency: 3,
        cancelToken: cancelToken,
        onProgress: (p) {
          final updater = dialogSetState;
          if (updater != null) {
            updater(() {
              progress = p;
            });
          } else {
            progress = p;
          }
          return p;
        },
      );

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        final messenger = ScaffoldMessenger.of(context);
        if (Platform.isAndroid) {
          final fileName = zipPath.split(Platform.pathSeparator).last;
          final res = await _exportToAndroidDownloads(
            srcPath: zipPath,
            fileName: fileName,
            mimeType: 'application/zip',
          );
          if (!mounted) return;
          final savedPath = res?['path']?.toString();
          if (savedPath != null && savedPath.isNotEmpty) {
            try {
              await File(zipPath).delete();
            } catch (_) {}
            messenger.showSnackBar(SnackBar(content: Text('已保存：$savedPath')));
            _exitSelectionMode();
            return;
          }
        }
        messenger.showSnackBar(SnackBar(content: Text('已保存：$zipPath')));
        _exitSelectionMode();
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        final msg = e is DioException && CancelToken.isCancel(e)
            ? '已取消下载'
            : '下载失败：$e';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  void _showAddToFavoritesDialog(GithubItem item) {
    final bool isAlreadyFavorite = _favoritesManager.isFavorite(item.path);

    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(isAlreadyFavorite ? "从收藏中移除" : "添加到收藏"),
                leading: Icon(
                  isAlreadyFavorite
                      ? Icons.bookmark_remove
                      : Icons.bookmark_add,
                  color: Theme.of(sheetContext).colorScheme.primary,
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  if (isAlreadyFavorite) {
                    await _favoritesManager.removeFavorite(item.path);
                    if (!mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text("已移除收藏")));
                  } else {
                    await _favoritesManager.addFavorite(
                      FavoriteItem(
                        title: item.name,
                        path: item.path,
                        type: item.type,
                        subtitle: widget.title, // 使用当前文件夹名称作为副标题/上下文
                        url: item.htmlUrl,
                      ),
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text("已添加到收藏")));
                  }
                },
              ),
              if (item.type != 'dir')
                ListTile(
                  title: Text('下载'),
                  leading: Icon(
                    Icons.download,
                    color: Theme.of(sheetContext).colorScheme.primary,
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _downloadFile(item);
                  },
                ),
              if (item.type == 'dir')
                ListTile(
                  title: Text('下载文件夹（ZIP）'),
                  leading: Icon(
                    Icons.folder_zip,
                    color: Theme.of(sheetContext).colorScheme.primary,
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _downloadFolderZip(item);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode ? '已选择 ${_selectedPaths.length}' : widget.title,
        ),
        centerTitle: true,
        actions: [
          if (!_selectionMode)
            IconButton(
              icon: Icon(Icons.checklist),
              onPressed: () => _enterSelectionMode(),
            ),
          if (_selectionMode) ...[
            IconButton(
              icon: Icon(Icons.select_all),
              onPressed: _selectAllItems,
            ),
            IconButton(
              icon: Icon(Icons.download),
              onPressed: _selectedPaths.isEmpty ? null : _downloadSelected,
            ),
            IconButton(
              icon: Icon(Icons.close),
              onPressed: () => _exitSelectionMode(),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索当前目录...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchText = value.toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<GithubItem>>(
              future: _contentsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.red),
                        SizedBox(height: 16),
                        Text('加载失败', style: TextStyle(fontSize: 18)),
                        SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32.0),
                          child: Text(
                            snapshot.error.toString(),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        SizedBox(height: 16),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              _contentsFuture = _githubApi.getContents(
                                widget.path,
                              );
                            });
                          },
                          child: Text('重试'),
                        ),
                      ],
                    ),
                  );
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(child: Text('文件夹为空'));
                }

                final allItems = snapshot.data!;
                _currentItems = allItems;
                final items = _searchText.isEmpty
                    ? allItems
                    : allItems
                          .where(
                            (item) =>
                                item.name.toLowerCase().contains(_searchText),
                          )
                          .toList();

                if (items.isEmpty && _searchText.isNotEmpty) {
                  return Center(child: Text('未找到匹配项'));
                }

                // 排序：文件夹在前，文件在后
                items.sort((a, b) {
                  if (a.type == b.type) {
                    return a.name.compareTo(b.name);
                  }
                  return a.type == 'dir' ? -1 : 1;
                });

                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isDir = item.type == 'dir';
                    final isSelected = _selectedPaths.contains(item.path);

                    return ListTile(
                      leading: Icon(
                        isDir ? Icons.folder : Icons.insert_drive_file,
                        color: isDir
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                      ),
                      title: Text(item.name),
                      trailing: _selectionMode
                          ? Checkbox(
                              value: isSelected,
                              onChanged: (_) => _toggleSelected(item),
                            )
                          : (isDir ? Icon(Icons.chevron_right) : null),
                      onTap: () {
                        if (_selectionMode) {
                          _toggleSelected(item);
                          return;
                        }

                        if (isDir) {
                          _navigateToSubDir(item);
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  RepoFilePreviewPage(item: item),
                            ),
                          );
                        }
                      },
                      onLongPress: () {
                        if (_selectionMode) {
                          _toggleSelected(item);
                          return;
                        }
                        _showAddToFavoritesDialog(item);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
