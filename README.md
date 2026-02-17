<h1 align="center">CQUT Helper</h1>

<p align="center">
  <img src="https://img.shields.io/github/v/release/lhgr/CQUT-Helper?style=flat-square" alt="Release" />
  <img src="https://img.shields.io/badge/Platform-Android-green?style=flat-square" alt="Platform" />
  <img src="https://img.shields.io/badge/SDK-Flutter-blue?style=flat-square" alt="SDK" />
</p>

**CQUT-Helper** 是一款专为重庆理工大学学子打造的课表助手 App。采用 Flutter 开发，遵循 Material 3 设计规范，旨在提供美观、流畅、便捷的学习体验。

## ✨ 主要功能

*   **📅 课程表**：展示每周课程,添加桌面小部件后不打开应用也能看到课程信息。
*   **👤 个人中心**：实现"本科课表(测试)"中的[getUserInfo](https://timetable-cfc.cqut.edu.cn/api/courseSchedule/getUserInfo)接口,可以便捷查看个人信息。
*   **🎨 个性化主题**：支持 Material 3 动态取色(Dynamic Color)，界面随心而动。
*   **🚀 自动更新**：实现"本科课表(测试)"中的[listWeekEvents](https://timetable-cfc.cqut.edu.cn/api/courseSchedule/listWeekEvents)接口,自动请求并更新课表数据。
*   **📂 开源浏览**：实现简单的 GitHub 仓库浏览器,用于浏览[Royfor12](https://github.com/Royfor12)的[课程资料仓库](https://github.com/Royfor12/CQUT-Course-Guide-Sharing-Scheme),获得课程资料。

## 📱 下载安装

请前往 [Releases 页面](https://github.com/lhgr/CQUT-Helper/releases) 下载最新版本的 APK 安装包。

*   **Universal**: 通用版
*   **Arm64-v8a**: 适用于 64 位手机(一般下载这个)
*   **Armeabi-v7a**: 适用于 32 位手机

## 📄 开源协议

本项目采用 MIT 协议开源，详情请参阅 [LICENSE](LICENSE) 文件。

## 🔒 隐私说明

尊重并保护用户的个人隐私：

1. **核心数据本地化**：用户的账号、密码（经过加密处理）、课表详情等核心隐私数据**仅存储在本地设备上**，绝不会上传至除学校教务系统以外的任何第三方服务器。
2. **统计分析**：为了优化用户体验和修复 Bug，本项目集成了 **Firebase Analytics**。它仅收集**匿名**的使用数据（如崩溃日志、功能点击次数），**不包含**任何个人身份信息。
3. **网络请求**：应用仅在以下情况发起网络请求：
   - 访问学校教务系统 (用于获取数据)
   - 检查应用更新 (访问 GitHub Releases)
   - 浏览开源仓库 (访问 GitHub API)
   - 匿名统计数据 (发送至 Firebase)
4. **权限使用**：应用仅在必要时请求所需权限，并明确告知使用目的。

## ⚠️ 开发说明

本项目的绝大部分代码是在 AI 辅助下完成的，主要用于学习和实验目的。代码质量和设计模式可能存在不足，仅供参考。如果遇到问题或有任何建议,请通过[Issues](https://github.com/lhgr/CQUT-Helper/issues)或[邮件](mailto:3414950665lhgr@gmail.com)给出。

## 📚 参考资料

- [cqut-net-login](https://github.com/CQUT-handsomeboy/cqut-net-login)  
  参考了其中的[密码加密模块](https://github.com/CQUT-handsomeboy/cqut-net-login/blob/main/encrypt.py)

- [CQUT课程攻略共享计划](https://github.com/Royfor12/CQUT-Course-Guide-Sharing-Scheme)  
  集成了该项目的仓库文件结构，便于查找。感谢各位上传的资料，~~屡次救我狗命~~。

- [Wake Up课程表](https://www.wakeup.fun/)  
  参考了它的[桌面小部件](https://www.wakeup.fun/doc/widget.html)样式

---
*注：本项目为第三方非官方客户端，仅供学习交流使用,如有侵权问题请通过[邮件](mailto:3414950665lhgr@gmail.com)联系我们。*
