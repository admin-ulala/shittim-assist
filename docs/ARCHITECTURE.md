# 架构与阶段

## 当前分层

```text
Flutter 工作台 (lib/main.dart)
  ├─ ServerProfile / AppConfig / ConfigStore
  ├─ EventLog
  └─ AutomationEngine → RunContext → DeviceBackend
                                     ├─ AdbDevice → adb.exe
                                     └─ AndroidDevice → MethodChannel
                                                        ├─ GestureService
                                                        └─ CaptureService
TemplateMatcher：独立参考实现，用于回放与后续资源适配
```

接口稳定后再提取独立 packages；目前在单应用 core 下分层。

## 取舍与限制

1. 首版使用 Dart/image 参考匹配器，尚未接入 OpenCV/OCR。业务集成前增加 isolate、多尺度、锚点与负样本验证。
2. 首版配置为 JSON、日志为 JSONL。跨运行任务历史与调度落地时再接入 SQLite。
3. 区服资料通过资源 JSON 加载，未确认渠道拒绝运行。
4. 输入不隐式重试；只读重试遇到取消直接退出。
5. 坐标以当前截图为准；截图超过 2 秒、坐标越界或前台不匹配时拒绝点击。后续业务仍需目标再识别和执行后验证。
6. 锁按设备 ID 生效，ADB 别名可能指向同一设备。当前 UI 只开放单设备；多设备功能前需归一化硬件标识。
7. 流程必须调用 RunControl.checkpoint/delay，底层请求必须自行有界。不合作的任意 Future 无法由 Dart 强行取消；本版不接受不受信任的脚本。
8. Android 采集服务不等于后台流程引擎，服务托管流程和悬浮控制尚待实现。

## 阶段

### 0：双端基础验证（进行中）

已完成 PC 截图/前台检查、引擎约束测试与 UI 布局检查。尚需双端原生编译、Android 授权/手势验证。

### 1：国服 B 服日常

采集主页、邮件、工作任务、签到和扫荡的多状态样本；实现状态识别、已完成跳过、资源不足、断线和未知弹窗停止。扫荡校验关卡、三星条件、次数和体力预算。无模板不启用流程。

### 2：Android 独立运行

服务托管任务生命周期，通知/悬浮控制；验证 Android 11/14/15 的旋转、锁屏、授权撤销和进程回收。

### 3：扩展

OpenCV/OCR、定时队列、设备归一化、局域网伴侣连接、主线章节和其他区服。伴侣协议必须有配对、身份验证、加密及撤销，不开放无认证远程输入。

公开发行前完成原生构建、签名、资源许可和实机验证。CI 工作流已定义不代表已运行通过。
