import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shittim_assist/core/device.dart';
import 'package:shittim_assist/core/engine.dart';
import 'package:shittim_assist/core/storage.dart';
import 'package:shittim_assist/core/vision.dart';

class FakeDevice implements DeviceBackend {
  @override
  final String id = 'fake';
  int taps = 0;
  String foreground = 'game';
  @override
  Future<String> foregroundPackage() async => foreground;
  @override
  Future<Uint8List> screenshot() async =>
      Uint8List.fromList(img.encodePng(img.Image(width: 20, height: 10)));
  @override
  Future<void> tap(int x, int y) async {
    taps++;
  }

  @override
  Future<void> back() async {}
  @override
  Future<void> swipe(int x1, int y1, int x2, int y2, Duration duration) async {}
}

void main() {
  late Directory temp;
  late EventLog log;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('shittim-test-');
    log = EventLog(temp);
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('preview never injects and validates screenshot bounds', () async {
    final d = FakeDevice();
    final c = RunContext(
      d,
      RunControl(const Duration(seconds: 5)),
      log,
      'test',
      dryRun: true,
      expectedPackage: 'game',
    );
    await c.capture();
    await expectLater(c.tap(20, 0), throwsRangeError);
    await c.tap(5, 5);
    expect(d.taps, 0);
    await expectLater(c.tap(5, 5), throwsStateError);
  });
  test('wrong foreground blocks real input', () async {
    final d = FakeDevice()..foreground = 'other';
    final c = RunContext(
      d,
      RunControl(const Duration(seconds: 5)),
      log,
      'test',
      dryRun: false,
      expectedPackage: 'game',
    );
    await c.capture();
    await expectLater(c.tap(5, 5), throwsStateError);
    expect(d.taps, 0);
  });
  test('cancel while paused wakes and releases device lock', () async {
    final d = FakeDevice(), entered = Completer<void>();
    final engine = AutomationEngine(log);
    final running = engine.run(
      d,
      (c) async {
        entered.complete();
        await c.control.delay(const Duration(seconds: 2));
      },
      config: AppConfig(),
      expectedPackage: 'game',
    );
    await entered.future;
    engine.pause();
    engine.cancel();
    await running;
    expect(engine.state, RunState.cancelled);
    await engine.run(
      d,
      (c) async {},
      config: AppConfig(),
      expectedPackage: 'game',
    );
    expect(engine.state, RunState.succeeded);
  });
  test('separate engines cannot control same device concurrently', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final a = AutomationEngine(log),
        b = AutomationEngine(log),
        d = FakeDevice();
    final running = a.run(
      d,
      (_) async {
        entered.complete();
        await release.future;
      },
      config: AppConfig(),
      expectedPackage: 'game',
    );
    await entered.future;
    await expectLater(
      b.run(d, (_) async {}, config: AppConfig(), expectedPackage: 'game'),
      throwsStateError,
    );
    release.complete();
    await running;
  });
  test('timeout and finite retries', () async {
    final control = RunControl(const Duration(milliseconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await expectLater(control.checkpoint(), throwsA(isA<TimeoutException>()));
    var calls = 0;
    final c = RunContext(
      FakeDevice(),
      RunControl(const Duration(seconds: 5)),
      log,
      'r',
      dryRun: true,
      expectedPackage: 'game',
    );
    await expectLater(
      c.retryRead(() async {
        calls++;
        throw StateError('offline');
      }, attempts: 2),
      throwsStateError,
    );
    expect(calls, 2);
  });
  test('configuration rejects unsupported versions and currency spending', () {
    expect(
      () => AppConfig.fromJson({...AppConfig().toJson(), 'schemaVersion': 99}),
      throwsFormatException,
    );
    expect(
      () => AppConfig.fromJson({
        ...AppConfig().toJson(),
        'premiumCurrencyBudget': 1,
      }),
      throwsFormatException,
    );
    expect(
      () => AppConfig.fromJson({...AppConfig().toJson(), 'maxRuns': 0}),
      throwsFormatException,
    );
  });
  test('configuration persists and log redacts credentials', () async {
    final store = ConfigStore(File('${temp.path}/config.json'));
    await store.save(AppConfig(maxRuns: 3));
    expect((await store.load()).maxRuns, 3);
    await log.add('github_pat_FAKE_TEST_TOKEN Bearer FAKE_TEST');
    final result = await File(await log.export()).readAsString();
    expect(result, isNot(contains('FAKE_TEST')));
  });
  test('matcher locates template and rejects mismatched ROI', () {
    final source = img.Image(width: 12, height: 10);
    final target = img.Image(width: 3, height: 3);
    img.fill(target, color: img.ColorRgb8(200, 100, 50));
    img.compositeImage(source, target, dstX: 7, dstY: 4);
    final matcher = TemplateMatcher();
    final found = matcher.find(
      Uint8List.fromList(img.encodePng(source)),
      Uint8List.fromList(img.encodePng(target)),
      threshold: .999,
    );
    expect(found?.x, 7);
    expect(found?.y, 4);
    expect(
      matcher.find(
        Uint8List.fromList(img.encodePng(source)),
        Uint8List.fromList(img.encodePng(target)),
        threshold: .999,
        right: 4,
      ),
      isNull,
    );
  });
}
