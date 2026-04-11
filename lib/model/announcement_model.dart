class AnnouncementModel {
  final String id;
  final String title;
  final String contentMarkdown;
  final String? linkUrl;
  final bool? force;
  final int? priority;
  final String? startsAt;
  final String? endsAt;
  final String? minVersion;
  final String? maxVersion;
  final String createdAt;
  final String updatedAt;

  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.contentMarkdown,
    required this.createdAt,
    required this.updatedAt,
    this.linkUrl,
    this.force,
    this.priority,
    this.startsAt,
    this.endsAt,
    this.minVersion,
    this.maxVersion,
  });

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
    return AnnouncementModel(
      id: json['id'] as String,
      title: json['title'] as String,
      contentMarkdown: (json['contentMarkdown'] as String?) ?? '',
      linkUrl: json['linkUrl'] as String?,
      force: json['force'] as bool?,
      priority: json['priority'] as int?,
      startsAt: json['startsAt'] as String?,
      endsAt: json['endsAt'] as String?,
      minVersion: json['minVersion'] as String?,
      maxVersion: json['maxVersion'] as String?,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'contentMarkdown': contentMarkdown,
      'linkUrl': linkUrl,
      'force': force,
      'priority': priority,
      'startsAt': startsAt,
      'endsAt': endsAt,
      'minVersion': minVersion,
      'maxVersion': maxVersion,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
