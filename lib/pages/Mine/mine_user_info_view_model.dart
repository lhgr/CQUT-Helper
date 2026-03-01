class MineUserInfoViewModel {
  final String username;
  final String realName;
  final String campusName;

  const MineUserInfoViewModel({
    required this.username,
    required this.realName,
    required this.campusName,
  });

  factory MineUserInfoViewModel.fromApi(Map<String, dynamic>? userInfo) {
    final username = userInfo?['username'] ?? '未知账号';
    final realName = userInfo?['userRealName'] ?? '未知姓名';
    final customSetting = userInfo?['userCustomSetting'];
    final campusName = (customSetting is Map)
        ? customSetting['campusName'] ?? '未知校区'
        : '未知校区';

    return MineUserInfoViewModel(
      username: username.toString(),
      realName: realName.toString(),
      campusName: campusName.toString(),
    );
  }
}
