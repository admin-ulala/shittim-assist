import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

Future<Directory> applicationDirectory() async {
  if (Platform.isAndroid) {
    final path = await AndroidDevice.channel.invokeMethod<String>(
      'dataDirectory',
    );
    if (path == null) throw StateError('无法获取应用数据目录');
    return Directory(path);
  }
  final base = Platform.environment['LOCALAPPDATA'];
  if (base == null) throw StateError('无法获取 LOCALAPPDATA');
  return Directory('$base/ShittimAssist');
}

class DeviceInfo {
  const DeviceInfo(this.id, this.name, this.ready);
  final String id, name;
  final bool ready;
}

abstract interface class DeviceBackend {
  String get id;
  Future<Uint8List> screenshot();
  Future<void> tap(int x, int y);
  Future<void> swipe(int x1, int y1, int x2, int y2, Duration duration);
  Future<void> back();
  Future<String> foregroundPackage();
}

class AdbClient {
  AdbClient(this.executable);
  final String executable;
  Future<ProcessResult> run(List<String> args, {bool binary = false}) async {
    final process = await Process.start(executable, args, runInShell: false);
    final output = process.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
    final error = process.stderr.transform(utf8.decoder).join();
    try {
      final code = await process.exitCode.timeout(const Duration(seconds: 15));
      final bytes = await output;
      final stderr = await error;
      if (code != 0) throw StateError('ADB 执行失败 ($code): $stderr');
      return ProcessResult(
        process.pid,
        code,
        binary ? Uint8List.fromList(bytes) : utf8.decode(bytes),
        stderr,
      );
    } on TimeoutException {
      process.kill();
      await Future.wait([output, error]);
      throw TimeoutException('ADB 超时，请检查设备授权与连接');
    }
  }

  Future<List<DeviceInfo>> devices() async {
    final result = await run(['devices', '-l']);
    return (result.stdout as String)
        .split('\n')
        .skip(1)
        .where((line) => line.trim().isNotEmpty && !line.startsWith('*'))
        .map((line) {
          final parts = line.trim().split(RegExp(r'\s+'));
          return DeviceInfo(
            parts.first,
            parts
                .firstWhere(
                  (p) => p.startsWith('model:'),
                  orElse: () => parts.first,
                )
                .replaceFirst('model:', ''),
            parts.length > 1 && parts[1] == 'device',
          );
        })
        .toList();
  }

  Future<String> connect(String address) async {
    if (!RegExp(r'^[a-zA-Z0-9.\-]+:\d{1,5}$').hasMatch(address)) {
      throw const FormatException('请输入主机:端口');
    }
    return (await run(['connect', address])).stdout as String;
  }

  Future<String> pair(String address, String code) async {
    if (!RegExp(r'^[a-zA-Z0-9.\-]+:\d{1,5}$').hasMatch(address) ||
        !RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const FormatException('请检查配对地址与六位配对码');
    }
    return (await run(['pair', address, code])).stdout as String;
  }
}

class AdbDevice implements DeviceBackend {
  AdbDevice(this.client, this.id);
  final AdbClient client;
  @override
  final String id;
  Future<ProcessResult> _run(List<String> args, {bool binary = false}) =>
      client.run(['-s', id, ...args], binary: binary);
  @override
  Future<Uint8List> screenshot() async =>
      (await _run(['exec-out', 'screencap', '-p'], binary: true)).stdout
          as Uint8List;
  @override
  Future<void> tap(int x, int y) async {
    await _run(['shell', 'input', 'tap', '$x', '$y']);
  }

  @override
  Future<void> swipe(int x1, int y1, int x2, int y2, Duration duration) async {
    await _run([
      'shell',
      'input',
      'swipe',
      '$x1',
      '$y1',
      '$x2',
      '$y2',
      '${duration.inMilliseconds.clamp(1, 5000)}',
    ]);
  }

  @override
  Future<void> back() async {
    await _run(['shell', 'input', 'keyevent', '4']);
  }

  @override
  Future<String> foregroundPackage() async {
    final result = await _run(['shell', 'dumpsys', 'window']);
    final match = RegExp(
      r'mCurrentFocus=.*?\s([a-zA-Z][\w.]+)/',
    ).firstMatch(result.stdout as String);
    if (match == null) throw StateError('无法确认前台应用，停止输入');
    return match.group(1)!;
  }
}

class AndroidDevice implements DeviceBackend {
  static const channel = MethodChannel('org.shittim.assist/device');
  @override
  String get id => 'android-local';
  Future<Map<String, dynamic>> capabilities() async =>
      Map<String, dynamic>.from(
        await channel.invokeMapMethod('capabilities') ?? {},
      );
  Future<void> requestCapture() => channel.invokeMethod('requestCapture');
  Future<void> openAccessibility() => channel.invokeMethod('openAccessibility');
  Future<void> stopCapture() => channel.invokeMethod('stopCapture');
  @override
  Future<Uint8List> screenshot() async {
    final bytes = await channel.invokeMethod<Uint8List>('screenshot');
    if (bytes == null || bytes.isEmpty) throw StateError('屏幕采集尚未就绪');
    return bytes;
  }

  @override
  Future<void> tap(int x, int y) =>
      channel.invokeMethod('tap', {'x': x, 'y': y});
  @override
  Future<void> swipe(int x1, int y1, int x2, int y2, Duration duration) =>
      channel.invokeMethod('swipe', {
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
        'duration': duration.inMilliseconds.clamp(1, 5000),
      });
  @override
  Future<void> back() => channel.invokeMethod('back');
  @override
  Future<String> foregroundPackage() async =>
      await channel.invokeMethod<String>('foregroundPackage') ?? '';
}
