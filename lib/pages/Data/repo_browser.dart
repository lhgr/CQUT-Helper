import 'package:cqut/api/github/github_api.dart';
import 'package:cqut/manager/favorites_manager.dart';
import 'package:cqut/model/github_item.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class RepoBrowserPage extends StatefulWidget {
  final String path;
  final String title;

  const RepoBrowserPage({Key? key, required this.path, required this.title})
    : super(key: key);

  @override
  _RepoBrowserPageState createState() => _RepoBrowserPageState();
}

class _RepoBrowserPageState extends State<RepoBrowserPage> {
  final GithubApi _githubApi = GithubApi();
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
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
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

  void _showAddToFavoritesDialog(GithubItem item) {
    final bool isAlreadyFavorite = _favoritesManager.isFavorite(item.path);

    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
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
                  color: Theme.of(context).colorScheme.primary,
                ),
                onTap: () async {
                  Navigator.pop(context);
                  if (isAlreadyFavorite) {
                    await _favoritesManager.removeFavorite(item.path);
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text("已移除收藏")));
                    }
                  } else {
                    await _favoritesManager.addFavorite(
                      FavoriteItem(
                        title: item.name,
                        path: item.path,
                        type: item.type,
                        subtitle: widget
                            .title, // 使用当前文件夹名称作为副标题/上下文
                      ),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text("已添加到收藏")));
                    }
                  }
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
