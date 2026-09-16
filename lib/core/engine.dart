import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'device.dart';
import 'storage.dart';
import 'geometry.dart';

enum RunState { idle, running, paused, stopping, succeeded, cancelled, failed }

class RunCancelled implements Exception {}

class RunControl {
  bool cancelled = false, paused = false;
  final DateTime deadline;
  RunControl(Duration timeout) : deadline = DateTime.now().add(timeout);
  Future<void> checkpoint() async {
    do {
      if (cancelled) throw RunCancelled();
      if (DateTime.now().isAfter(deadline)) throw TimeoutException('任务达到时间上限');
      if (!paused) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } while (true);
  }

  Future<void> delay(Duration duration) async {
    final until = DateTime.now().add(duration);
    while (DateTime.now().isBefore(until)) {
      await checkpoint();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await checkpoint();
  }
}

class RunContext {
  RunContext(
    this.device,
    this.control,
    this.log,
    this.runId, {
    required this.dryRun,
    required this.expectedPackage,
  });
  final DeviceBackend device;
  final RunControl control;
  final EventLog log;
  final String runId, expectedPackage;
  final bool dryRun;
  Uint8List? lastFrame;
  DateTime? capturedAt;

  Future<Uint8List> capture() async {
    await control.checkpoint();
    final data = await device.screenshot();
    await control.checkpoint();
    if (img.decodeImage(data) == null) throw StateError('设备返回无效截图');
    lastFrame = data;
    capturedAt = DateTime.now();
    return data;
  }

  /// Input is never retried implicitly. Callers must re-observe and verify.
  Future<void> tapReference(
    int x,
    int y, {
    int referenceWidth = 1280,
    int referenceHeight = 720,
    Rectangle<int>? content,
  }) async {
    final frame = lastFrame == null ? null : img.decodeImage(lastFrame!);
    if (frame == null) throw StateError('需要新的截图才能映射坐标');
    final geometry = ScreenGeometry(
      width: frame.width,
      height: frame.height,
      referenceWidth: referenceWidth,
      referenceHeight: referenceHeight,
      content: content,
    );
    final mapped = geometry.point(x, y);
    await tap(mapped.x, mapped.y);
  }

  /// Coordinates here are physical pixels in the current screenshot.
  Future<void> tap(int x, int y) async {
    await control.checkpoint();
    final frame = lastFrame == null ? null : img.decodeImage(lastFrame!);
    if (frame == null ||
        capturedAt == null ||
        DateTime.now().difference(capturedAt!) > const Duration(seconds: 2)) {
      throw StateError('需要新的截图才能点击');
    }
    if (x < 0 || y < 0 || x >= frame.width || y >= frame.height) {
      throw RangeError('点击坐标超出截图');
    }
    if (expectedPackage.isEmpty ||
        await device.foregroundPackage() != expectedPackage) {
      throw StateError('当前前台应用与目标区服不符');
    }
    await control.checkpoint();
    if (DateTime.now().difference(capturedAt!) > const Duration(seconds: 2)) {
      throw StateError('验证期间画面已过期，请重新识别');
    }
    await log.add(dryRun ? '预览点击 ($x, $y)，未发送输入' : '点击 ($x, $y)', runId: runId);
    await control.checkpoint();
    if (!dryRun) await device.tap(x, y);
    lastFrame = null;
  }

  Future<T> retryRead<T>(
    Future<T> Function() action, {
    int attempts = 3,
  }) async {
    if (attempts < 1 || attempts > 5) throw ArgumentError('attempts');
    for (var attempt = 1; ; attempt++) {
      await control.checkpoint();
      try {
        return await action();
      } on RunCancelled {
        rethrow;
      } catch (_) {
        if (attempt >= attempts) rethrow;
        await control.delay(Duration(milliseconds: 150 * attempt));
      }
    }
  }
}

typedef Workflow = Future<void> Function(RunContext context);

class AutomationEngine {
  AutomationEngine(this.log, {this.onChanged});
  final EventLog log;
  final void Function()? onChanged;
  static final Set<String> _lockedDevices = {};
  RunState state = RunState.idle;
  RunControl? _control;
  String? error;
  bool get busy =>
      [RunState.running, RunState.paused, RunState.stopping].contains(state);
  void _state(RunState value) {
    state = value;
    onChanged?.call();
  }

  void pause() {
    if (state == RunState.running) {
      _control!.paused = true;
      _state(RunState.paused);
    }
  }

  void resume() {
    if (state == RunState.paused) {
      _control!.paused = false;
      _state(RunState.running);
    }
  }

  void cancel() {
    if (busy) {
      _control!.cancelled = true;
      _state(RunState.stopping);
    }
  }

  Future<void> run(
    DeviceBackend device,
    Workflow workflow, {
    required AppConfig config,
    required String expectedPackage,
  }) async {
    if (busy || !_lockedDevices.add(device.id)) throw StateError('设备已有运行中的任务');
    final runId = DateTime.now().microsecondsSinceEpoch.toString();
    _control = RunControl(Duration(seconds: config.timeoutSeconds));
    error = null;
    _state(RunState.running);
    try {
      await log.add('开始运行', runId: runId);
      final context = RunContext(
        device,
        _control!,
        log,
        runId,
        dryRun: config.dryRun,
        expectedPackage: expectedPackage,
      );
      await workflow(context);
      await _control!.checkpoint();
      await log.add('运行完成', runId: runId);
      _state(RunState.succeeded);
    } on RunCancelled {
      _state(RunState.cancelled);
      await log.add('任务已停止', runId: runId);
    } catch (e) {
      error = redact(e.toString());
      _state(RunState.failed);
      try {
        await log.add(error!, level: 'error', runId: runId);
      } catch (_) {}
    } finally {
      _lockedDevices.remove(device.id);
      _control = null;
      onChanged?.call();
    }
  }
}

Future<void> inspectDevice(RunContext context) async {
  final foreground = await context.retryRead(context.device.foregroundPackage);
  if (foreground != context.expectedPackage) {
    throw StateError('请先在设备上打开国服 B 服游戏');
  }
  final frame = await context.retryRead(context.capture);
  final decoded = img.decodeImage(frame)!;
  await context.log.add(
    '截图验证通过：${decoded.width} × ${decoded.height}；前台应用匹配。未发送点击。',
    runId: context.runId,
    step: 'inspect',
  );
}
