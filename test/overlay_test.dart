import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shittim_assist/core/overlay.dart';
import 'package:shittim_assist/core/storage.dart';

void main() {
  test('overlay edits preserve the main configuration and validate values', () {
    final original = AppConfig(adbPath: 'custom-adb', address: 'device:5555');
    final edited = applyOverlayPatch(original, {
      'timeoutSeconds': 60,
      'selected': ['signin', 'sweep'],
      'dryRun': false,
    });
    expect(edited.adbPath, 'custom-adb');
    expect(edited.address, 'device:5555');
    expect(edited.timeoutSeconds, 60);
    expect(edited.selected, ['signin', 'sweep']);
    expect(edited.dryRun, false);
    expect(original.timeoutSeconds, 30);
    expect(AppConfig.fromJson(edited.toJson()).toJson(), edited.toJson());
    for (final patch in [
      {'timeoutSeconds': 0},
      {
        'selected': ['unimplemented'],
      },
      {'premiumCurrencyBudget': 100},
      {'adbPath': 'overwritten'},
      {'channel': 'jp'},
    ]) {
      expect(() => applyOverlayPatch(original, patch), throwsFormatException);
    }
  });

  test(
    'overlay stop and pause remain available during a pending task',
    () async {
      final done = Completer<void>();
      final actions = <String>[];
      final controls = OverlayCommands(
        start: () async {
          actions.add('start');
          await done.future;
        },
        pause: () => actions.add('pause'),
        resume: () => actions.add('resume'),
        cancel: () {
          actions.add('cancel');
          done.complete();
        },
      );
      final run = controls.handle(const MethodCall('overlayCommand', 'start'));
      await controls.handle(const MethodCall('overlayCommand', 'start'));
      await controls.handle(const MethodCall('overlayCommand', 'pause'));
      await controls.handle(const MethodCall('overlayCommand', 'resume'));
      await controls.handle(const MethodCall('overlayCommand', 'cancel'));
      await run;
      expect(actions, ['start', 'pause', 'resume', 'cancel']);
    },
  );

  test('failed start releases the gate and reports its error', () async {
    var attempts = 0;
    final controls = OverlayCommands(
      start: () async {
        attempts++;
        if (attempts == 1) throw StateError('capture unavailable');
      },
      pause: () {},
      resume: () {},
      cancel: () {},
    );
    await expectLater(
      controls.handle(const MethodCall('overlayCommand', 'start')),
      throwsStateError,
    );
    await controls.handle(const MethodCall('overlayCommand', 'start'));
    expect(attempts, 2);
    await expectLater(
      controls.handle(const MethodCall('overlayCommand', 'unknown')),
      throwsA(isA<PlatformException>()),
    );
  });
}
