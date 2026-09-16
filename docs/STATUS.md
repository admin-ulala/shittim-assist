# 实现与验证状态

## 2026-09-16 开发预览

### 0.1.1 冷启动修正（已验证）

初始 APK 在 MuMu 安装成功，但普通冷启动触发首页 LayoutBuilder 的 `debugNeedsLayout` 断言；调试暂停后启动正常。现已移除该布局回调，使用窗口尺寸计算统计卡片宽度，并增加 800×450、640×360 横屏测试。0.1.1 已在 MuMu 安装并正常冷启动，首页、设备页和原生权限状态查询通过。无障碍与屏幕采集权限未授予，实际采集/手势联调仍待完成。不要使用初始 0.1.0 APK。

| 模块 | 实现 | 验证 |
| --- | --- | --- |
| 自适应 UI | 已实现 | 桌面/竖屏/横屏布局及导航通过；Android 冷启动通过 |
| ADB 发现/连接/配对 | 已实现 | 发现实机通过，connect/pair 待实机 |
| ADB 截图/前台 | 已实现 | MuMu B 服通过 |
| 输入 API | 已实现 | 防误触测试通过，原生手势待验证 |
| 暂停/取消/互斥/重试 | 已实现 | 单元测试通过 |
| Dart 模板匹配 | 参考实现 | 合成样本与实际截图裁剪回放通过 |
| JSON 配置/JSONL 日志 | 已实现 | 校验、保存、脱敏通过 |
| Android 采集/无障碍 | 已实现 | APK 安装启动与状态桥接通过；实际采集/手势未验证 |
| 邮件/签到/日常/扫荡 | 仅配置 | 无可执行流程 |
| OCR/OpenCV/主线/其他区服 | 未实现 | — |
| CI | 已运行 | test / windows / android 全部成功 |

已完成 Flutter analyze（无问题）及 13 项测试：8 项核心、4 项布局、1 项显式开启的只读实机检查。默认 CI 跳过实机项。

## 构建缺项

- 本机 Windows 构建缺 Visual Studio C++ 工具链；GitHub CI 构建成功。
- 本机 APK 构建缺 Android SDK；GitHub CI debug APK 构建成功。
- Flutter SDK 已下载并通过官方 SHA-256 校验，保存在仓库外。
- CI 已产出 Windows preview ZIP 和 Android debug APK artifact。桌面预览图来自 Flutter 渲染测试，Android 图来自 MuMu 实际安装包。

## 仓库

公开仓库：https://github.com/admin-ulala/shittim-assist

修正版提交 `6f63b0f` 已通过 GitHub Git Database API 上传，blob、tree、commit 与本地哈希逐级核对一致，并以非强制方式更新 main。[CI run 35035264060](https://github.com/admin-ulala/shittim-assist/actions/runs/35035264060) 全部成功。

0.1.1 产物：Windows ZIP 12,225,362 bytes；Android artifact ZIP 72,189,218 bytes。两份下载均已与 GitHub artifact SHA-256 校验一致。正式 APK 签名、Android 权限联调和日常流程仍待完成。

## 0.1.2 悬浮控制（开发中）

新增无障碍悬浮球：拖动、展开、开始只读诊断、暂停/继续、停止、关闭；与工作台共用引擎。Application 持有 FlutterEngine，Activity 重建不销毁任务。前台包名实时查询 focused application window；截图要求移除悬浮控件后的新帧。停止采集或无障碍服务取消任务，进程重启不恢复运行。

无障碍声明新增窗口读取能力，仅取根节点包名，不遍历文本。Android 编译与 MuMu 回归待验证，不能视为实机通过。

## 0.1.3 悬浮工作台（开发中）

0.1.2 已通过 [CI 35058871914](https://github.com/admin-ulala/shittim-assist/actions/runs/35058871914)，MuMu 安装及权限流程通过；用户确认可正常获取截图。正在将文本悬浮球改为应用图标，并添加运行/任务/配置面板及同源配置同步。当前版本 Android 构建和新面板实机回归待验证。

预览 APK 目前使用 CI 临时 debug 签名，不同构建可能无法覆盖安装。此次经用户授权替换旧版，并在本地备份、恢复助手数据；未改动游戏数据。正式稳定签名仍待配置。

### 0.1.3 实机检查与截图修正

图标、三个页签、超时双向实时同步、任务勾选保存已在 MuMu 验证。游戏前台可完成 1280×720 诊断，助手前台会拒绝运行。实测发现仅设置 View.INVISIBLE 并比较隐藏前时间戳仍可能接收合成器尚未移除悬浮层的画面；改为暂时移除 overlay window，等待合成稳定后再要求新生产帧。修正版截图回归待完成。

## 0.1.4 分辨率适配（验证中）

修复宽矮窗口侧栏溢出和窄屏下拉框溢出；新增 13 组尺寸/DPI 布局测试，参考坐标与模板支持 960×540 至 2560×1440 的等比缩放。非 16:9 布局要求显式内容区域。悬浮面板按去除系统栏/缺口后的可用高度布局，内部滚动。Android 新版实机切换与干净截图回归待完成。
