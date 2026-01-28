class GithubItem {
  final String name;
  final String path;
  final String type; // 'file' or 'dir'
  final String? downloadUrl;
  final String htmlUrl;

  GithubItem({
    required this.name,
    required this.path,
    required this.type,
    this.downloadUrl,
    required this.htmlUrl,
  });

  factory GithubItem.fromJson(Map<String, dynamic> json) {
    return GithubItem(
      name: json['name'] as String,
      path: json['path'] as String,
      type: json['type'] as String,
      downloadUrl: json['download_url'] as String?,
      htmlUrl: json['html_url'] as String,
    );
  }
}
