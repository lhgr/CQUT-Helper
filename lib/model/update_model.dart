class UpdateModel {
  final String tagName;
  final String body;
  final String downloadUrl;
  final String htmlUrl;

  UpdateModel({
    required this.tagName,
    required this.body,
    required this.downloadUrl,
    required this.htmlUrl,
  });

  factory UpdateModel.fromJson(Map<String, dynamic> json) {
    String downloadUrl = "";
    // 尝试查找 apk 资源
    if (json['assets'] != null) {
      final assets = json['assets'] as List;
      final apkAsset = assets.firstWhere(
        (asset) => asset['name'].toString().endsWith('.apk'),
        orElse: () => null,
      );
      if (apkAsset != null) {
        downloadUrl = apkAsset['browser_download_url'];
      }
    }
    
    // 如果没有 APK，回退到 html_url
    if (downloadUrl.isEmpty) {
      downloadUrl = json['html_url'];
    }

    return UpdateModel(
      tagName: json['tag_name'] ?? '',
      body: json['body'] ?? '',
      downloadUrl: downloadUrl,
      htmlUrl: json['html_url'] ?? '',
    );
  }
}
