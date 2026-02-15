import 'dart:io';

import 'package:cqut/api/github/github_api.dart';
import 'package:cqut/manager/favorites_manager.dart';
import 'package:cqut/model/github_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class RepoBrowserPage extends StatefulWidget {
  final String path;
  final String title;

  const RepoBrowserPage({super.key, required this.path, required this.title});

  @override
  State<RepoBrowserPage> createState() => _RepoBrowserPageState();
}

class _RepoBrowserPageState extends State<RepoBrowserPage> {
  final GithubApi _githubApi = GithubApi();
  static const MethodChannel _downloadsChannel = MethodChannel(
    'cqut/downloads',
  );
  late Future<List<GithubItem>> _contentsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchText = "";
  final FavoritesManager _favoritesManager = FavoritesManager();

  @override
  void initState() {
    super.initState();
    _contentsFuture = _githubApi.getContents(widget.path);
    _favoritesManager.init(); // Ensure initialized if accessed directly
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法打开链接: $urlString')));
      }
    }
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

  String _sanitizeFileName(String name) {
    final sanitized = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\u0000-\u001F]'), '_')
        .trim();
    return sanitized.isEmpty ? 'file' : sanitized;
  }

  String _buildUniqueSavePath(String directoryPath, String fileName) {
    final safeName = _sanitizeFileName(fileName);
    final dotIndex = safeName.lastIndexOf('.');
    final base = dotIndex > 0 ? safeName.substring(0, dotIndex) : safeName;
    final ext = dotIndex > 0 ? safeName.substring(dotIndex) : '';

    String candidate = '$directoryPath${Platform.pathSeparator}$safeName';
    int i = 1;
    while (File(candidate).existsSync()) {
      candidate = '$directoryPath${Platform.pathSeparator}$base ($i)$ext';
      i++;
    }
    return candidate;
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
        final res = await _enqueueAndroidDownload(
          url: url,
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

    Directory? downloadDir = await getDownloadsDirectory();
    if (downloadDir == null) {
      final baseDir = await getApplicationDocumentsDirectory();
      downloadDir = Directory(
        '${baseDir.path}${Platform.pathSeparator}downloads',
      );
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
    }

    final appDownloadDir = Directory(
      '${downloadDir.path}${Platform.pathSeparator}CQUT-Helper',
    );
    if (!await appDownloadDir.exists()) {
      await appDownloadDir.create(recursive: true);
    }

    final savePath = _buildUniqueSavePath(appDownloadDir.path, item.name);

    StateSetter? dialogSetState;
    double? progress;
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
              );
            },
          );
        },
      );
    }

    try {
      await _githubApi.downloadFile(
        url,
        savePath,
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('下载失败：$e')));
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
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), centerTitle: true),
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

                    return ListTile(
                      leading: Icon(
                        isDir ? Icons.folder : Icons.insert_drive_file,
                        color: isDir
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                      ),
                      title: Text(item.name),
                      trailing: isDir ? Icon(Icons.chevron_right) : null,
                      onTap: () {
                        if (isDir) {
                          _navigateToSubDir(item);
                        } else {
                          _launchUrl(item.htmlUrl);
                        }
                      },
                      onLongPress: () {
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
