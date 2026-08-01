# Android 发布说明

Release 构建不再使用 debug 签名。缺少正式签名配置时，Gradle 会直接终止 Release 构建，避免生成无法稳定升级的安装包。

## 首次准备

1. 生成并离线备份长期有效的 Android 上传密钥。密钥遗失后，GitHub APK 用户将无法直接覆盖升级。
2. 在 GitHub Actions 配置以下 Secrets：
   - `ANDROID_KEYSTORE_BASE64`
   - `ANDROID_KEYSTORE_PASSWORD`
   - `ANDROID_KEY_ALIAS`
   - `ANDROID_KEY_PASSWORD`
   - `NOTICE_API_KEY`
3. `ANDROID_KEYSTORE_BASE64` 是 JKS 文件的单行 Base64 内容；密钥文件和 `android/key.properties` 均已加入 `.gitignore`，不得提交。
4. `NOTICE_API_KEY` 应与调课服务端 `JWXT_API_KEYS` 中的当前令牌一致。

## 本地 Release 构建

在 `android/key.properties` 写入：

```properties
storeFile=upload-keystore.jks
storePassword=...
keyAlias=...
keyPassword=...
```

将密钥保存为 `android/app/upload-keystore.jks`，然后执行：

```shell
flutter build appbundle --release --dart-define=NOTICE_API_KEY=...
flutter build apk --release --dart-define=NOTICE_API_KEY=...
```

推送与 `pubspec.yaml` 版本一致的 `v*` 标签后，Release 工作流会先运行格式检查、静态分析、Flutter/Kotlin 测试，再构建正式签名的 AAB、通用 APK、分架构 APK 和 SHA-256 校验文件。产物默认进入 Draft Release，发布前仍需在真机验证覆盖安装、登录、课表刷新、通知和三种桌面小组件。
