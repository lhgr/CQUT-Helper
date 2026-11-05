<div align="center">

<img src="lib/assets/Icon.png" alt="CQUT Helper 应用图标" width="112" />

# CQUT Helper

**西唯兵学子的课表小帮手**

面向重庆理工大学同学的第三方 Android / iPhone 课表助手。

[![Release](https://img.shields.io/github/v/release/lhgr/CQUT-Helper?style=flat-square)](https://github.com/lhgr/CQUT-Helper/releases)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%2015%2B-3DDC84?style=flat-square&logo=android&logoColor=white)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square)](LICENSE)

[下载应用](https://github.com/lhgr/CQUT-Helper/releases) ·
[功能介绍](#功能) ·
[应用截图](#应用截图) ·
[问题反馈](https://github.com/lhgr/CQUT-Helper/issues)

</div>

> [!NOTE]
> CQUT Helper 是第三方非官方应用。课程与调课安排请以学校官方信息为准。

## 功能

- 查看今日和周课表，切换教学周；课表同步后保存在本机，断网时仍可查看已有数据。
- 根据校历中的假期与调休日期映射课程安排，并用于今日页、课表、提醒和小组件。
- 使用 Android 桌面小组件或 iPhone WidgetKit 小组件查看课程。iOS 17 及以上，支持切换的样式可直接在组件内切换日期。
- 按本机课表安排课前提醒；iPhone 会优先安排近期提醒，待发送通知最多 64 条。可在“设置 → 同步与修复”查看实际覆盖时间，之后打开应用同步续排。
- 按需开启调课通知增强，查看通知变更并刷新受影响教学周。使用方式见[调课通知说明](FastAPI/README.md)。
- 自定义课程别名、备注、颜色和隐藏状态，调整课表布局、主题及背景。
- 导出或恢复应用设置和课程个性化。备份包含账号标识，不包含登录凭据、课表缓存、日志或自定义背景图片。

## 应用截图

<table align="center">
  <tr>
    <td align="center"><img src="assets/img/schedule.png" alt="周课表界面" width="260" /></td>
    <td align="center"><img src="assets/img/schedule-customization.png" alt="课表布局与外观设置" width="260" /></td>
    <td align="center"><img src="assets/img/schedule-notice.png" alt="课前提醒与调课通知设置" width="260" /></td>
  </tr>
  <tr>
    <td align="center"><sub>周课表与假期调休</sub></td>
    <td align="center"><sub>布局、背景与课程卡片</sub></td>
    <td align="center"><sub>课前提醒与调课通知</sub></td>
  </tr>
</table>

## 平台与限制

| 功能 | Android | iPhone |
| --- | --- | --- |
| 登录、课表、校历、个性化、主题与备份 | 支持 | 支持（iOS 15+） |
| 课表与调课同步 | 课表支持前台、手动及系统安排的后台刷新；调课通知也可后台检查 | 课表支持前台和手动同步；调课通知在启动、返回应用及手动同步时检查 |
| 课前提醒 | 需允许通知；精确提醒还需系统授权 | 需允许通知；应用会安排近期本地提醒 |
| 桌面小组件 | 支持 | 支持；iOS 17+ 部分样式可在组件内切换日期 |
| 课程期间自动勿扰或静音 | 部分设备支持，需允许访问系统勿扰设置及精确闹钟 | 不支持 |

> [!TIP]
> iPhone 提醒受系统待发送通知数量限制，课表较多时实际覆盖时间可能短于计划窗口。请定期打开应用同步，并在“设置 → 同步与修复”查看覆盖情况。

> [!NOTE]
> iPhone 小组件与应用通过 App Group 共享课表。若自行签名安装，主应用和小组件扩展必须由同一开发团队签名，并使用该团队已配置的同一个 App Group；否则小组件无法读取应用课表。

## 下载安装

### Android

从 [GitHub Releases](https://github.com/lhgr/CQUT-Helper/releases) 下载 APK。大多数现代 Android 手机请选择 **Arm64-v8a**；旧款 32 位设备可选 **Armeabi-v7a**，模拟器或 x86_64 设备可选对应版本。不确定设备架构时可下载 **Universal**，安装包较大但兼容范围更广。

### iPhone（个人侧载）

> [!WARNING]
> iOS 版本尚未经真机测试，功能可用性仍待验证，暂不能保证各项功能正常运行。使用中如遇问题，请通过 [GitHub Issues](https://github.com/lhgr/CQUT-Helper/issues) 反馈，并附上设备型号、iOS 版本和问题描述。

发行页提供当前 Alpha 阶段的未签名 IPA，文件名格式为 `CQUT-Helper-<版本号>-alpha-unsigned.ipa`；后续阶段会按发行版本调整。也可以在 GitHub Actions 手动运行 [Build unsigned iOS IPA](.github/workflows/ios-sideload.yml)，选择分支并下载 `CQUT-Helper-unsigned-ios` artifact。

使用 Sideloadly 等侧载工具，按工具说明连接 iPhone，并用自己的 Apple ID 完成签名和安装。iOS 16 及以上还需按系统提示开启开发者模式。签名有效期与续签方式取决于所用账号和工具。侧载工具说明见 [Sideloadly 官网](https://sideloadly.io/)。

## 首次使用

1. 使用学校账号登录，进入课表并完成首次同步。
2. 按需调整课表外观、主题和提醒设置。
3. 添加小组件；若显示尚未同步，回到应用同步课表后再查看。
4. 如需调课通知增强，在“设置 → 通知与提醒”或课表设置中开启并检查服务可用性。详细设置与服务说明见[调课通知说明](FastAPI/README.md)。

## 数据与隐私

学校账号和课表请求会发送到学校认证及课表服务。应用也会按需请求公开公告、每日一言、校历配置和 GitHub 版本信息。登录所需凭据使用系统安全存储保存在设备上；课表缓存、设置和消息记录保存在本机。

调课通知增强默认关闭。开启并确认说明后，应用才会向所选调课服务发送学号、教务系统加密密码和当前学期。加密密码仍可用于访问教务系统，请只使用信任的服务。备份文件包含账号标识、应用设置和课程个性化，不包含登录凭据、课表缓存、日志或自定义背景图片。

## 常见问题

- **Android 小组件没有及时刷新**: 打开应用并同步课表；仍未更新时，在“设置 → 同步与修复”查看后台状态，并检查系统的后台运行和电池优化设置。
- **调课日期与学校安排不一致**: 刷新校历并同步相关教学周；重要安排以学校通知和教务系统为准。
- **没有收到课前提醒**: 检查系统通知授权。iPhone 可在“设置 → 同步与修复”查看已安排数量和覆盖时间，并打开应用续排。
- **调课通知查询失败**: 确认已开启功能并通过“检查服务可用性”；自定义服务不会在失败时自动切换到官方服务。
- **如何配置自己的调课服务？** 请参阅[调课通知与服务说明](FastAPI/README.md)。

## 本地开发

建议使用与 CI 一致的 Flutter 3.47.7。项目约束为 Flutter >=3.47.0、Dart ^3.13.0。在项目根目录执行：

```bash
flutter pub get
flutter run
flutter analyze
flutter test
```

构建 Android Release APK 需要先在 `android/key.properties` 配置签名信息。`storeFile` 是相对于 `android/app` 的路径，例如 `../upload-keystore.jks`：

```properties
storeFile=../upload-keystore.jks
storePassword=<密钥库密码>
keyAlias=<密钥别名>
keyPassword=<密钥密码>
```

之后运行：

```bash
flutter build apk --release
```

iOS 构建需要 macOS；当前 CI 使用 `macos-15` 和 Xcode 26.3。项目最低支持 iOS 15。配置 Xcode 签名时，主应用 `Runner` 与 `CQUTWidgetsExtension` 需使用同一团队及同一 App Group。日常检查见 [Quality Gate workflow](.github/workflows/ci.yml)；发行构建见 [Build and Release workflow](.github/workflows/release.yml) 与 [iOS IPA workflow](.github/workflows/ios-sideload.yml)。

## 项目与协议

这是一个个人学习项目。欢迎通过 [GitHub Issues](https://github.com/lhgr/CQUT-Helper/issues) 提交问题或建议，也可以发送邮件至 <dawndrizzle0104@gmail.com>。

- [cqut-net-login](https://github.com/CQUT-handsomeboy/cqut-net-login)：密码加密模块参考。
- [Wake Up 课程表](https://www.wakeup.fun/) 与 [拾光课程表](https://github.com/XingHeYuZhuan/shiguangschedule)：小组件样式参考。
- [CQUT-Course-Guide-Sharing-Scheme](https://github.com/Royfor12/CQUT-Course-Guide-Sharing-Scheme)：感谢参与资料整理和分享的同学。

本项目采用 [Apache License 2.0](LICENSE) 开源。
