import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The disk caches used for images downloaded by the app.
///
/// Keep cache managers and their keys together so storage accounting and
/// cleanup always cover the same directories as image loading.
abstract final class AppNetworkImageCache {
  static const String aboutMemberAvatarsKey = 'about_member_avatars_v1';

  static const List<String> diskCacheKeys = <String>[
    DefaultCacheManager.key,
    aboutMemberAvatarsKey,
  ];

  static final BaseCacheManager aboutMemberAvatars = CacheManager(
    Config(
      aboutMemberAvatarsKey,
      stalePeriod: const Duration(days: 14),
      maxNrOfCacheObjects: 8,
    ),
  );

  static List<BaseCacheManager> get managers => <BaseCacheManager>[
    DefaultCacheManager(),
    aboutMemberAvatars,
  ];
}
