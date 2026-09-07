class DailyQuoteItem {
  final String id;
  final String text;
  final String? source;
  final bool enabled;
  final int priority;
  final int order;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? createdAt;
  final String? updatedAt;

  const DailyQuoteItem({
    required this.id,
    required this.text,
    this.source,
    this.enabled = true,
    this.priority = 0,
    this.order = 0,
    this.startsAt,
    this.endsAt,
    this.createdAt,
    this.updatedAt,
  });

  factory DailyQuoteItem.fromJson(Map<String, dynamic> json) {
    final rawSource = (json['source'] as String?)?.trim();
    return DailyQuoteItem(
      id: (json['id'] as String? ?? '').trim(),
      text: (json['text'] as String? ?? '').trim(),
      source: rawSource == null || rawSource.isEmpty ? null : rawSource,
      enabled: json['enabled'] as bool? ?? true,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      order: (json['order'] as num?)?.toInt() ?? 0,
      startsAt: _tryParseDate(json['startsAt']),
      endsAt: _tryParseDate(json['endsAt']),
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'source': source,
    'enabled': enabled,
    'priority': priority,
    'order': order,
    'startsAt': startsAt?.toIso8601String(),
    'endsAt': endsAt?.toIso8601String(),
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  bool isActiveAt(DateTime now) {
    if (!enabled || id.isEmpty || text.isEmpty) return false;
    final instant = now.toUtc();
    final start = startsAt?.toUtc();
    final end = endsAt?.toUtc();
    if (start != null && instant.isBefore(start)) return false;
    if (end != null && !instant.isBefore(end)) return false;
    return true;
  }

  static DateTime? _tryParseDate(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim());
  }
}

class DailyQuoteConfig {
  final bool enabled;
  final int revision;
  final String rotationMode;
  final DateTime? updatedAt;
  final DateTime? nextRefreshAt;
  final List<DailyQuoteItem> items;

  const DailyQuoteConfig({
    required this.enabled,
    required this.revision,
    required this.rotationMode,
    required this.items,
    this.updatedAt,
    this.nextRefreshAt,
  });

  factory DailyQuoteConfig.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return DailyQuoteConfig(
      enabled: json['enabled'] as bool? ?? true,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      rotationMode: (json['rotationMode'] as String?)?.trim().isNotEmpty == true
          ? (json['rotationMode'] as String).trim()
          : 'daily',
      updatedAt: DailyQuoteItem._tryParseDate(json['updatedAt']),
      nextRefreshAt: DailyQuoteItem._tryParseDate(json['nextRefreshAt']),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) =>
                      DailyQuoteItem.fromJson(item.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'revision': revision,
    'rotationMode': rotationMode,
    'updatedAt': updatedAt?.toIso8601String(),
    'nextRefreshAt': nextRefreshAt?.toIso8601String(),
    'items': items.map((item) => item.toJson()).toList(growable: false),
  };
}

List<DailyQuoteItem> buildDailyQuoteQueue(
  DailyQuoteConfig config, {
  required DateTime now,
}) {
  if (!config.enabled) return const [];

  final active = config.items
      .where((item) => item.isActiveAt(now))
      .toList(growable: false);
  final priorityItems = active
      .where((item) => item.priority > 0)
      .toList(growable: true);
  final normalItems = active
      .where((item) => item.priority <= 0)
      .toList(growable: true);

  int compareItems(DailyQuoteItem a, DailyQuoteItem b) {
    final byPriority = b.priority.compareTo(a.priority);
    if (byPriority != 0) return byPriority;
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    return a.id.compareTo(b.id);
  }

  priorityItems.sort(compareItems);
  normalItems.sort(compareItems);
  if (normalItems.length > 1 && config.rotationMode == 'daily') {
    final dayNumber = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime.utc(1970)).inDays;
    final offset = dayNumber % normalItems.length;
    final rotated = <DailyQuoteItem>[
      ...normalItems.skip(offset),
      ...normalItems.take(offset),
    ];
    normalItems
      ..clear()
      ..addAll(rotated);
  }

  return List.unmodifiable([...priorityItems, ...normalItems]);
}
