# 实现与验证状态

## 2026-09-16 开发预览

| 模块 | 实现 | 验证 |
| --- | --- | --- |
| 自适应 UI | 已实现 | 1440×1000、390×844 渲染及导航通过 |
| ADB 发现/连接/配对 | 已实现 | 发现实机通过，connect/pair 待实机 |
| ADB 截图/前台 | 已实现 | MuMu B 服通过 |
| 输入 API | 已实现 | 防误触测试通过，原生手势待验证 |
| 暂停/取消/互斥/重试 | 已实现 | 单元测试通过 |
| Dart 模板匹配 | 参考实现 | 合成样本与实际截图裁剪回放通过 |
| JSON 配置/JSONL 日志 | 已实现 | 校验、保存、脱敏通过 |
| Android 采集/无障碍 | 已实现 | CI APK 编译通过；权限和手势未实机验证 |
| 邮件/签到/日常/扫荡 | 仅配置 | 无可执行流程 |
| OCR/OpenCV/主线/其他区服 | 未实现 | — |
| CI | 已运行 | test / windows / android 全部成功 |

已完成 Flutter analyze（无问题）及 11 项测试：8 项核心、2 项布局、1 项显式开启的只读实机检查。以最新实际检查更新本文件。

## 构建缺项

- 本机 Windows 构建缺 Visual Studio C++ 工具链；GitHub CI 构建成功。
- 本机 APK 构建缺 Android SDK；GitHub CI debug APK 构建成功。
- Flutter SDK 已下载并通过官方 SHA-256 校验，保存在仓库外。
- CI 已产出 Windows preview ZIP 和 Android debug APK artifact。界面图片仍来自 Flutter 渲染测试，不是安装包实机截图。

## 仓库

公开仓库：https://github.com/admin-ulala/shittim-assist

首个提交 `6fa2af3` 已推送，远端 main 与本地提交哈希核对一致。[CI run 35007095532](https://github.com/admin-ulala/shittim-assist/actions/runs/35007095532) 的 test、windows、android 三个任务均成功。此前审批服务暂时阻止查询，重新审批后已核实结果。

产物：Windows ZIP 12,226,774 bytes；Android artifact ZIP 72,189,292 bytes。正式 APK 签名、Android 权限联调和日常流程仍待完成。
