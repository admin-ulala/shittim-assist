import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shittim_assist/core/overlay.dart';

void main() {
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
