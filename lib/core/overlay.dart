import 'dart:async';
import 'package:flutter/services.dart';
import 'storage.dart';

/// Both surfaces use AppConfig validation and the same persisted document.
/// Only mobile task fields can be patched; desktop connection data is preserved.
AppConfig applyOverlayPatch(AppConfig current, Map<String, dynamic> patch) {
  const editable = {
    'channel',
    'dryRun',
    'maxRuns',
    'staminaReserve',
    'timeoutSeconds',
    'selected',
  };
  if (patch.isEmpty || patch.keys.any((key) => !editable.contains(key))) {
    throw const FormatException('悬浮面板包含不支持的配置项');
  }
  return AppConfig.fromJson({...current.toJson(), ...patch});
}

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
