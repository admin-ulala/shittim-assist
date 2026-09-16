import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shittim_assist/main.dart';

void main() {
  setUpAll(() async {
    if (Platform.environment['SHITTIM_RENDER'] == '1') {
      final chinese = Platform.environment['SHITTIM_TEST_FONT'];
      final sdk = Platform.environment['FLUTTER_ROOT'];
      if (chinese != null) {
        await (FontLoader('Microsoft YaHei')..addFont(
              File(
                chinese,
              ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            ))
            .load();
      }
      if (sdk != null) {
        await (FontLoader('MaterialIcons')..addFont(
              File(
                '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            ))
            .load();
      }
    }
  });
  for (final display in [
    (const Size(1440, 1000), 1.0),
    (const Size(390, 844), 1.0),
    (const Size(800, 450), 1.0),
    (const Size(640, 360), 1.0),
    (const Size(1280, 720), 1.5),
    (const Size(1920, 1080), 2.0),
    (const Size(1600, 900), 1.5),
    (const Size(2560, 1440), 2.0),
    (const Size(960, 540), 1.5),
    (const Size(1080, 2400), 3.0),
    (const Size(720, 1280), 2.0),
    (const Size(1280, 720), 3.0),
    (const Size(2400, 1080), 2.5),
  ]) {
    final size = display.$1;
    testWidgets('workbench fits $size at DPR ${display.$2}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = display.$2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: const ShittimApp()),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('老师，工作台已就绪。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (Platform.environment['SHITTIM_RENDER'] == '1') {
        await tester.runAsync(() async {
          final object =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await object.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('runtime').create(recursive: true);
          await File(
            'runtime/workbench-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      for (final title in ['设备连接', '任务计划', '运行日志', '设置']) {
        await tester.tap(find.text(title).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: title);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
