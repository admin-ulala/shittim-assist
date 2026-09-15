# 贡献指南

先阅读 AGENTS.md 与 docs/STATUS.md。

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

默认 CI 不访问设备。实机检查使用显式环境变量，不提交账号截图。平台变更报告实际编译和安装验证版本。

识别变更包含合法来源的正负样本；流程验证未知页面、断线、取消、超时、资源不足与已完成状态。提交描述问题、最终行为和测试结果，不把尚未实现的流程标成可用。
