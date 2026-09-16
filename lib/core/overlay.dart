import 'dart:async';
import 'package:flutter/services.dart';

/// Native controls share the existing engine. A pending start must not block stop.
class OverlayCommands {
  OverlayCommands({
    required this.start,
    required this.pause,
    required this.resume,
    required this.cancel,
  });
  final Future<void> Function() start;
  final void Function() pause, resume, cancel;
  bool _starting = false;

  Future<void> handle(MethodCall call) async {
    if (call.method != 'overlayCommand') throw MissingPluginException();
    switch (call.arguments) {
      case 'start':
        if (_starting) return;
        _starting = true;
        try {
          await start();
        } finally {
          _starting = false;
        }
      case 'pause':
        pause();
      case 'resume':
        resume();
      case 'cancel':
        cancel();
      default:
        throw PlatformException(code: 'UNKNOWN_COMMAND', message: '未知悬浮窗操作');
    }
  }
}
