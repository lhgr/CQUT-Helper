import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cqut_helper/utils/github_proxy.dart';

Future<void> showMineAboutDialog(BuildContext context) async {
  final packageInfo = await PackageInfo.fromPlatform();
  final version = packageInfo.version;

  if (!context.mounted) return;

  showAboutDialog(
    context: context,
    applicationName: "CQUT 助手",
    applicationVersion: version,
    applicationIcon: Icon(
      Icons.school,
      size: 48,
      color: Theme.of(context).colorScheme.primary,
    ),
    children: [
      Text("CQUTer的小助手"),
      SizedBox(height: 24),
      Text("作者信息", style: Theme.of(context).textTheme.titleSmall),
      SizedBox(height: 12),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await FirebaseAnalytics.instance.logEvent(name: 'about_us_developer_click');
          const urlString = 'https://github.com/lhgr';
          if (!await GithubProxy.launchExternalUrlString(urlString)) {
            debugPrint('Could not launch $urlString');
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: CachedNetworkImage(
                  imageUrl: GithubProxy.proxyUrlOf('https://github.com/lhgr.png'),
                  imageBuilder: (context, imageProvider) => CircleAvatar(
                    radius: 24,
                    backgroundImage: imageProvider,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHigh,
                  ),
                  placeholder: (context, url) => CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHigh,
                    child: Icon(Icons.person),
                  ),
                  errorWidget: (context, url, error) => CachedNetworkImage(
                    imageUrl: 'https://github.com/lhgr.png',
                    imageBuilder: (context, imageProvider) => CircleAvatar(
                      radius: 24,
                      backgroundImage: imageProvider,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHigh,
                    ),
                    placeholder: (context, url) => CircleAvatar(
                      radius: 24,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHigh,
                      child: Icon(Icons.person),
                    ),
                    errorWidget: (context, url, error) => CircleAvatar(
                      radius: 24,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHigh,
                      child: Icon(Icons.person),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Dawn Drizzle",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    "开发者",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      SizedBox(height: 8),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await FirebaseAnalytics.instance.logEvent(name: 'about_us_mascot_click');
          const String urlString =
              'https://weibo.com/5401723589?refer_flag=1001030103_';
          final Uri url = Uri.parse(urlString);
          if (!await launchUrl(url)) {
            debugPrint('Could not launch $url');
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHigh,
                  backgroundImage: AssetImage('lib/assets/Wing.jpg'),
                ),
              ),
              SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Wing",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    "吉祥物",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      SizedBox(height: 24),
      Text("开源地址", style: Theme.of(context).textTheme.titleSmall),
      SizedBox(height: 8),
      InkWell(
        onTap: () async {
          await FirebaseAnalytics.instance.logEvent(name: 'click_repo_link');
          const urlString = 'https://github.com/lhgr/CQUT-Helper';
          if (!await GithubProxy.launchExternalUrlString(urlString)) {
            debugPrint('Could not launch $urlString');
          }
        },
        child: Text(
          'https://github.com/lhgr/CQUT-Helper',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    ],
  );
}
