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
  for (final size in [
    const Size(1440, 1000),
    const Size(390, 844),
    const Size(800, 450),
    const Size(640, 360),
  ]) {
    testWidgets('workbench navigation fits ${size.width}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
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
