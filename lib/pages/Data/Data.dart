import 'package:cqut/pages/Data/repo_browser.dart';
import 'package:cqut/manager/favorites_manager.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

class DataView extends StatefulWidget {
  DataView({Key? key}) : super(key: key);

  @override
  _DataViewState createState() => _DataViewState();
}

class _DataViewState extends State<DataView> {
  final String _repoUrl =
      "https://github.com/Royfor12/CQUT-Course-Guide-Sharing-Scheme";
  final String _ownerName = "Royfor12";
  final String _ownerAvatarUrl = "https://github.com/Royfor12.png";
  final String _ownerProfileUrl = "https://github.com/Royfor12";

  final FavoritesManager _favoritesManager = FavoritesManager();

  @override
  void initState() {
    super.initState();
    _favoritesManager.init();
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

  void _navigateToRepoBrowser(String path, String title) {
    FirebaseAnalytics.instance.logEvent(
      name: 'view_material',
      parameters: {'path': path, 'title': title},
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RepoBrowserPage(path: path, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("资料"),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          _buildProjectCard(),
          SizedBox(height: 24),
          Text(
            "收藏内容",
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          _buildFavoritesList(),
        ],
      ),
    );
  }

  Widget _buildProjectCard() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text("CQUT 课程攻略共享计划"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("仓库地址:"),
                  SizedBox(height: 4),
                  InkWell(
                    onTap: () => _launchUrl(_repoUrl),
                    child: Text(
                      _repoUrl,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  Text("作者:"),
                  SizedBox(height: 8),
                  InkWell(
                    onTap: () => _launchUrl(_ownerProfileUrl),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CachedNetworkImage(
                          imageUrl: _ownerAvatarUrl,
                          imageBuilder: (context, imageProvider) =>
                              CircleAvatar(
                                radius: 16,
                                backgroundImage: imageProvider,
                              ),
                          placeholder: (context, url) => CircleAvatar(
                            radius: 16,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (context, url, error) => CircleAvatar(
                            radius: 16,
                            child: Icon(Icons.person, size: 20),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          _ownerName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  Text("简介:"),
                  SizedBox(height: 4),
                  Text("收录历年期末试卷、复习资料、实验报告等，旨在推动知识传播、提升资源质量。"),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("关闭"),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _launchUrl(_repoUrl);
                  },
                  child: Text("打开链接"),
                ),
              ],
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.school_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "CQUT 课程攻略共享计划",
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                "收录历年期末试卷、复习资料、实验报告等，旨在推动知识传播、提升资源质量。前人栽树，后人乘凉。",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _navigateToRepoBrowser("", "CQUT 课程攻略共享计划"),
                  icon: Icon(Icons.folder_open, size: 18),
                  label: Text("浏览仓库目录"),
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoritesList() {
    return ListenableBuilder(
      listenable: _favoritesManager,
      builder: (context, child) {
        final favorites = _favoritesManager.favorites;

        if (favorites.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32.0),
              child: Column(
                children: [
                  Icon(
                    Icons.bookmark_border,
                    size: 48,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  SizedBox(height: 12),
                  Text(
                    "暂无收藏内容",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "在仓库目录中长按文件夹可添加到此处",
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: favorites.map((item) {
            return Card(
              elevation: 0,
              margin: EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: 1,
                ),
              ),
              child: InkWell(
                onTap: () {
                  if (item.type == 'dir') {
                    _navigateToRepoBrowser(item.path, item.title);
                  } else {
                    // 对于文件，我们可能需要完整 URL 或者在 RepoBrowser 中处理
                    // 目前假设用户主要收藏文件夹
                    _navigateToRepoBrowser(item.path, item.title);
                  }
                },
                onLongPress: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text("取消收藏"),
                      content: Text("确定要将 '${item.title}' 移出收藏吗？"),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text("取消"),
                        ),
                        TextButton(
                          onPressed: () {
                            _favoritesManager.removeFavorite(item.path);
                            Navigator.pop(context);
                          },
                          child: Text("确定"),
                        ),
                      ],
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          item.type == 'dir'
                              ? Icons.folder
                              : Icons.insert_drive_file,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            if (item.subtitle.isNotEmpty) ...[
                              SizedBox(height: 2),
                              Text(
                                item.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
