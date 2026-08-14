# Android 发布说明

Release 构建不再使用 debug 签名。缺少正式签名配置时，Gradle 会直接终止 Release 构建，避免生成无法稳定升级的安装包。

## 首次准备

1. 生成并离线备份长期有效的 Android 上传密钥。密钥遗失后，GitHub APK 用户将无法直接覆盖升级。
2. 在 GitHub Actions 配置以下 Secrets：
   - `ANDROID_KEYSTORE_BASE64`
   - `ANDROID_KEYSTORE_PASSWORD`
   - `ANDROID_KEY_ALIAS`
   - `ANDROID_KEY_PASSWORD`
3. `ANDROID_KEYSTORE_BASE64` 是 JKS 文件的单行 Base64 内容。

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
flutter build appbundle --release
flutter build apk --release
```

推送与 `pubspec.yaml` 版本一致的 `v*` 标签后，Release 工作流会先运行格式检查、静态分析、Flutter/Kotlin 测试，再构建正式签名的 AAB、通用 APK、分架构 APK 和 SHA-256 校验文件。产物默认进入 Draft Release，发布前仍需在真机验证覆盖安装、登录、课表刷新、通知和三种桌面小组件。

## 应用内更新日志语法

应用直接读取 GitHub Release 正文，并支持标准 Markdown 及以下增强语法。

行内语义强调：

```markdown
{{danger:旧版本将不再兼容}}
{{warning:升级前请先同步数据}}
{{success:数据迁移已完成}}
{{info:该功能需要 Android 12 以上}}
{{accent:全新的课表自定义功能}}
{{muted:此功能仍处于测试阶段}}
```

更新类型标签：

```markdown
[[NEW]] 新增功能
[[FIX]] 问题修复
[[OPTIMIZE]] 性能优化
[[BREAKING]] 重大调整
[[BETA]] 测试功能
```

GitHub 风格提示框：

```markdown
> [!WARNING]
> 升级前请先同步数据。

> [!CAUTION]
> 此操作可能导致数据丢失。
```

提示框支持 `NOTE`、`TIP`、`IMPORTANT`、`WARNING` 和 `CAUTION`。图片与 GIF 使用标准 Markdown 图片语法，必须提供可公开访问、直接返回图片内容的 HTTP/HTTPS 地址：

```markdown
![课表预览](https://example.com/preview.png)
![操作演示](https://example.com/demo.gif)
```

发布前应在应用内检查浅色与深色主题下的显示效果，并确认所有媒体地址无需登录即可访问。
