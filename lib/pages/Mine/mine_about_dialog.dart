import 'dart:async';

import 'package:cqut_helper/manager/app_network_image_cache.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/ios_release.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cqut_helper/utils/github_proxy.dart';

const _developerAvatarUrl =
    'https://blog-assets.dawndrizzle.top/images/hero-avatar.png';
const _wingAvatarUrl = 'https://blog-assets.dawndrizzle.top/images/Wing.jpg';

CachedNetworkImageProvider _aboutAvatarProvider(String url) {
  return CachedNetworkImageProvider(
    url,
    cacheManager: AppNetworkImageCache.aboutMemberAvatars,
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
  final version = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
      ? currentIosRelease.displayVersion(packageInfo.version)
      : packageInfo.version;

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
        color: Theme.of(context).colorScheme.primary,
        colorBlendMode: BlendMode.srcIn,
      ),
    ),
    children: [
      Text("CQUTer的课表小助手"),
      SizedBox(height: 24),
      Text("作者信息", style: Theme.of(context).textTheme.titleSmall),
      SizedBox(height: 12),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          const urlString = 'https://blog.dawndrizzle.top/';
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
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.filledTonal(
            tooltip: 'GitHub',
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () =>
                _openAboutLink('https://github.com/lhgr/CQUT-Helper', '仓库'),
            icon: SizedBox.square(
              dimension: 24,
              child: CustomPaint(
                painter: _GithubMarkPainter(
                  Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filledTonal(
            tooltip: '发送邮件',
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () =>
                _openAboutLink('mailto:dawndrizzle0104@gamil.com', '邮件'),
            icon: const Icon(Icons.mail_outline),
          ),
        ],
      ),
    ],
  );
}

Future<void> _openAboutLink(String url, String target) async {
  if (!await GithubProxy.launchExternalUrlString(url)) {
    AppLogger.I.event(
      LogLevel.warn,
      'MineAbout',
      event: 'ui_about_open_url_fail',
      messageZh: '关于页打开$target链接失败',
      message: 'open about link failed',
      module: 'ui',
      action: 'open_url',
      status: 'fail',
      reason: 'launch_failed',
      fields: {'target_url': url},
    );
  }
}

class _GithubMarkPainter extends CustomPainter {
  const _GithubMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final mark = Path()
      ..moveTo(12, 0)
      ..cubicTo(5.37, 0, 0, 5.37, 0, 12)
      ..cubicTo(0, 17.3, 3.44, 21.8, 8.21, 23.39)
      ..cubicTo(8.81, 23.5, 9.03, 23.13, 9.03, 22.81)
      ..lineTo(9.03, 20.58)
      ..cubicTo(5.69, 21.31, 4.99, 19.16, 4.99, 19.16)
      ..cubicTo(4.44, 17.77, 3.66, 17.4, 3.66, 17.4)
      ..cubicTo(2.57, 16.65, 3.74, 16.67, 3.74, 16.67)
      ..cubicTo(4.95, 16.75, 5.58, 17.91, 5.58, 17.91)
      ..cubicTo(6.65, 19.74, 8.39, 19.21, 9.07, 18.9)
      ..cubicTo(9.18, 18.12, 9.49, 17.59, 9.83, 17.29)
      ..cubicTo(7.16, 16.99, 4.36, 15.95, 4.36, 11.35)
      ..cubicTo(4.36, 10.04, 4.83, 8.97, 5.59, 8.13)
      ..cubicTo(5.47, 7.83, 5.05, 6.61, 5.71, 4.96)
      ..cubicTo(5.71, 4.96, 6.72, 4.64, 9.01, 6.19)
      ..cubicTo(9.97, 5.92, 10.99, 5.79, 12.01, 5.79)
      ..cubicTo(13.03, 5.79, 14.05, 5.93, 15.01, 6.19)
      ..cubicTo(17.3, 4.64, 18.31, 4.96, 18.31, 4.96)
      ..cubicTo(18.97, 6.61, 18.55, 7.83, 18.43, 8.13)
      ..cubicTo(19.2, 8.97, 19.66, 10.04, 19.66, 11.35)
      ..cubicTo(19.66, 15.96, 16.85, 16.98, 14.17, 17.28)
      ..cubicTo(14.6, 17.65, 14.98, 18.38, 14.98, 19.5)
      ..lineTo(14.98, 22.81)
      ..cubicTo(14.98, 23.13, 15.2, 23.51, 15.81, 23.39)
      ..cubicTo(20.57, 21.8, 24, 17.3, 24, 12)
      ..cubicTo(24, 5.37, 18.63, 0, 12, 0)
      ..close();
    canvas.drawPath(mark, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GithubMarkPainter oldDelegate) =>
      color != oldDelegate.color;
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
            cacheManager: AppNetworkImageCache.aboutMemberAvatars,
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
