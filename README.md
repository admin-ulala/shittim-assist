# Shittim Assist · 什亭助手

面向《蔚蓝档案》的 Windows / Android 自动化工作台。名字取自「什亭之匣」，希望帮助老师处理重复事务。

**当前为 0.1 开发预览：基础设施已实现，国服 B 服日常仍在适配，暂不能一键清日常。**

## 已有能力

- Flutter 自适应界面：总览、设备、任务计划、日志、设置。
- PC：USB/模拟器 ADB 列表、网络连接、无线配对、截图、点击、滑动与返回 API。
- Android：MediaProjection 采集、通知停止、无障碍手势及前台包名桥接源码。
- 引擎：设备互斥、暂停、取消、超时检查、有限只读重试、输入前前台校验。
- 识别：独立 Dart 模板匹配参考实现，支持 ROI 与置信度门槛。
- 配置：JSON 校验、版本字段、导入导出、任务选择与资源预算。
- 日志：JSONL、滚动清理、搜索、凭据脱敏、诊断事件导出。

领奖、签到、扫荡仅有计划配置，没有可执行的游戏任务。OCR、OpenCV、主线、多区服流程、调度与伴侣连接尚未实现。完整状态见 [STATUS](docs/STATUS.md)。

## 开发运行

基线：Flutter **3.47.4** / Dart **3.13.3**。目标 Windows 10/11 x64、Android 11+。

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Windows 构建需 Visual Studio 的 Desktop development with C++ 工作负载及 Windows SDK。Android 构建需 Android SDK 与兼容 Gradle 的 JDK（CI 使用 JDK 21）。

```sh
flutter doctor -v
flutter build apk --debug
```

Android 正式签名未配置。CI 仅生成 debug APK，不是正式发布包。

### PC 诊断

1. 在设备页填写 ADB 路径，扫描或输入主机:端口连接。
2. 同一模拟器多个地址只选择一个。
3. 在设备打开国服 B 服，返回总览运行「只读诊断」。
4. 检查真实截图和日志；诊断不发送点击或消耗资源。

无线调试配对端口与连接端口通常不同，需要支持 `adb pair` 的 ADB。

### Android 本机模式

在设备页开启无障碍并授权屏幕采集。采集使用完整屏幕以保持手势坐标一致；通知提供停止入口。

**当前没有悬浮任务面板和后台流程宿主。** 本机模式用于服务联调，不能宣称已支持离开工作台后自动清日常。服务源码尚未经过 APK 编译和授权实机验证。

## 实机测试（只读）

默认测试不访问设备。显式设置环境变量后运行：

```powershell
$env:SHITTIM_LIVE_ADB = '完整路径\adb.exe'
$env:SHITTIM_LIVE_SERIAL = '127.0.0.1:16416'
flutter test test/live_device_test.dart
```

测试读取前台包名与截图，截图保存在 Git 忽略的 `runtime/`。裁剪匹配仅验证截图管线，不代表页面识别准确率。

## 数据

Windows 数据在 `%LOCALAPPDATA%/ShittimAssist`，Android 在应用私有 files 目录。每份日志约 2 MiB 后滚动，保留当前和上一份。界面截图只存在内存；导出诊断仅包含事件。没有游戏凭据存储、图片上传或青辉石消费入口。

## 文档

- [架构与后续阶段](docs/ARCHITECTURE.md)
- [实现与验证状态](docs/STATUS.md)
- [国服 B 服观察](docs/CN_BILIBILI.md)
- [贡献指南](CONTRIBUTING.md)
- [协作规约](AGENTS.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)

原创代码采用 [MIT](LICENSE)。非官方项目，与游戏开发、发行方无隶属关系；第三方依赖及游戏资产分别适用自己的许可证。
