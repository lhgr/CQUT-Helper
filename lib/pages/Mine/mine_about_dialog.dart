import 'dart:async';

import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cqut_helper/utils/github_proxy.dart';

const _developerAvatarUrl =
    'https://blog-assets.dawndrizzle.top/images/hero-avatar.png';
const _wingAvatarUrl = 'https://blog-assets.dawndrizzle.top/images/Wing.jpg';

final BaseCacheManager _aboutAvatarCacheManager = CacheManager(
  Config(
    'about_member_avatars_v1',
    stalePeriod: const Duration(days: 14),
    maxNrOfCacheObjects: 8,
  ),
);

CachedNetworkImageProvider _aboutAvatarProvider(String url) {
  return CachedNetworkImageProvider(
    url,
    cacheManager: _aboutAvatarCacheManager,
    maxWidth: 256,
    maxHeight: 256,
  );
}

Future<void> _precacheAboutAvatars(BuildContext context) async {
  await Future.wait(
    const [_developerAvatarUrl, _wingAvatarUrl].map((url) async {
      var errorHandled = false;
      try {
        await precacheImage(
          _aboutAvatarProvider(url),
          context,
          onError: (error, stackTrace) {
            errorHandled = true;
            AppLogger.I.debug(
              'MineAbout',
              'about avatar prefetch failed',
              error: error,
              stackTrace: stackTrace,
              fields: {'target_url': url},
            );
          },
        );
      } catch (error, stackTrace) {
        if (!errorHandled) {
          AppLogger.I.debug(
            'MineAbout',
            'about avatar prefetch failed',
            error: error,
            stackTrace: stackTrace,
            fields: {'target_url': url},
          );
        }
      }
    }),
  );
}

Future<void> showMineAboutDialog(BuildContext context) async {
  final packageInfo = await PackageInfo.fromPlatform();
  final version = packageInfo.version;

  if (!context.mounted) return;

  unawaited(_precacheAboutAvatars(context));

  showAboutDialog(
    context: context,
    applicationName: "CQUT Helper",
    applicationVersion: version,
    applicationIcon: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.asset(
        'lib/assets/Icon.png',
        width: 48,
        height: 48,
        fit: BoxFit.cover,
      ),
    ),
    children: [
      Text("CQUTer的小助手"),
      SizedBox(height: 24),
      Text("作者信息", style: Theme.of(context).textTheme.titleSmall),
      SizedBox(height: 12),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          const urlString = 'https://dawndrizzle.top/';
          if (!await GithubProxy.launchExternalUrlString(urlString)) {
            AppLogger.I.event(
              LogLevel.warn,
              'MineAbout',
              event: 'ui_about_open_url_fail',
              messageZh: '关于页打开开发者链接失败',
              message: 'open developer url failed',
              module: 'ui',
              action: 'open_url',
              status: 'fail',
              reason: 'launch_failed',
              fields: {'target_url': urlString},
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              const _MemberAvatar(
                imageUrl: _developerAvatarUrl,
                semanticLabel: 'Dawn Drizzle 头像',
                fallbackText: 'DD',
              ),
              SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Dawn Drizzle",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text("开发者", style: Theme.of(context).textTheme.bodySmall),
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
          const String urlString = 'https://space.bilibili.com/350065580';
          final Uri url = Uri.parse(urlString);
          if (!await launchUrl(url)) {
            AppLogger.I.event(
              LogLevel.warn,
              'MineAbout',
              event: 'ui_about_open_url_fail',
              messageZh: '关于页打开 Wing 链接失败',
              message: 'open Wing url failed',
              module: 'ui',
              action: 'open_url',
              status: 'fail',
              reason: 'launch_failed',
              fields: {'target_url': url.toString()},
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              const _MemberAvatar(
                imageUrl: _wingAvatarUrl,
                semanticLabel: 'Wing 头像',
                fallbackText: 'W',
                fallbackAsset: 'lib/assets/Wing.jpg',
              ),
              SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Wing", style: Theme.of(context).textTheme.titleMedium),
                  Text("氛围组", style: Theme.of(context).textTheme.bodySmall),
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
          const urlString = 'https://github.com/lhgr/CQUT-Helper';
          if (!await GithubProxy.launchExternalUrlString(urlString)) {
            AppLogger.I.event(
              LogLevel.warn,
              'MineAbout',
              event: 'ui_about_open_url_fail',
              messageZh: '关于页打开仓库链接失败',
              message: 'open repository url failed',
              module: 'ui',
              action: 'open_url',
              status: 'fail',
              reason: 'launch_failed',
              fields: {'target_url': urlString},
            );
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

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({
    required this.imageUrl,
    required this.semanticLabel,
    required this.fallbackText,
    this.fallbackAsset,
  });

  final String imageUrl;
  final String semanticLabel;
  final String fallbackText;
  final String? fallbackAsset;

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final decodeSize = (_size * devicePixelRatio).ceil().clamp(96, 256).toInt();

    Widget textFallback() {
      return ColoredBox(
        color: colors.surfaceContainerHigh,
        child: Center(
          child: Text(
            fallbackText,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    Widget errorFallback() {
      final asset = fallbackAsset;
      if (asset == null) return textFallback();
      return Image.asset(
        asset,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        cacheWidth: decodeSize,
        cacheHeight: decodeSize,
        errorBuilder: (context, error, stackTrace) => textFallback(),
      );
    }

    return Semantics(
      image: true,
      label: semanticLabel,
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.outlineVariant),
        ),
        padding: const EdgeInsets.all(1),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            cacheManager: _aboutAvatarCacheManager,
            width: _size,
            height: _size,
            fit: BoxFit.cover,
            memCacheWidth: decodeSize,
            memCacheHeight: decodeSize,
            maxWidthDiskCache: 256,
            maxHeightDiskCache: 256,
            fadeInDuration: const Duration(milliseconds: 180),
            fadeOutDuration: const Duration(milliseconds: 80),
            placeholderFadeInDuration: Duration.zero,
            useOldImageOnUrlChange: true,
            filterQuality: FilterQuality.medium,
            placeholder: (context, url) => ColoredBox(
              color: colors.surfaceContainerHigh,
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                ),
              ),
            ),
            errorWidget: (context, url, error) => errorFallback(),
          ),
        ),
      ),
    );
  }
}
