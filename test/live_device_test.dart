import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shittim_assist/core/device.dart';
import 'package:shittim_assist/core/vision.dart';

void main() {
  final executable = Platform.environment['SHITTIM_LIVE_ADB'];
  final serial = Platform.environment['SHITTIM_LIVE_SERIAL'];
  test('B server read-only ADB capture and local template replay', () async {
    final client = AdbClient(executable!);
    expect(
      (await client.devices()).any((d) => d.ready && d.id == serial),
      isTrue,
    );
    final device = AdbDevice(client, serial!);
    expect(
      await device.foregroundPackage(),
      'com.RoamingStar.BlueArchive.bilibili',
    );
    final bytes = await device.screenshot();
    final frame = img.decodePng(bytes)!;
    expect(frame.width, greaterThan(frame.height));
    // This checks the real capture pipeline, not game-page recognition accuracy.
    final patch = img.copyCrop(frame, x: 20, y: 10, width: 32, height: 24);
    final found = TemplateMatcher().find(
      bytes,
      Uint8List.fromList(img.encodePng(patch)),
      left: 10,
      top: 0,
      right: 80,
      bottom: 60,
      threshold: .999,
    );
    expect(found?.x, 20);
    expect(found?.y, 10);
    await Directory('runtime').create(recursive: true);
    await File('runtime/live-capture.png').writeAsBytes(bytes);
  }, skip: executable == null || serial == null);
}
