import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shittim_assist/core/geometry.dart';
import 'package:shittim_assist/core/vision.dart';

void main() {
  for (final size in [
    (960, 540),
    (1280, 720),
    (1600, 900),
    (1920, 1080),
    (2560, 1440),
  ]) {
    test(
      'maps reference coordinates and template at ${size.$1}x${size.$2}',
      () {
        final geometry = ScreenGeometry(width: size.$1, height: size.$2);
        expect(geometry.point(640, 360), Point(size.$1 ~/ 2, size.$2 ~/ 2));
        final edge = geometry.point(1279, 719);
        expect(edge.x, lessThan(size.$1));
        expect(edge.y, lessThan(size.$2));
        final template = img.Image(width: 12, height: 8);
        for (var y = 0; y < 8; y++) {
          for (var x = 0; x < 12; x++) {
            template.setPixelRgb(x, y, x * 21, y * 31, (x + y) * 12);
          }
        }
        final scaled = img.copyResize(
          template,
          width: (12 * geometry.scale).round(),
          height: (8 * geometry.scale).round(),
          interpolation: img.Interpolation.linear,
        );
        final point = geometry.point(480, 220);
        final source = img.Image(width: size.$1, height: size.$2);
        img.compositeImage(source, scaled, dstX: point.x, dstY: point.y);
        final match = TemplateMatcher().findReference(
          Uint8List.fromList(img.encodePng(source)),
          Uint8List.fromList(img.encodePng(template)),
          geometry: geometry,
          referenceRegion: const Rectangle(470, 210, 40, 30),
          threshold: .999,
        );
        expect(match, isNotNull);
        expect((match!.x, match.y), (point.x, point.y));
      },
    );
  }
  test(
    'letterbox requires an explicit valid viewport; aspect ratio is not guessed',
    () {
      expect(() => ScreenGeometry(width: 2400, height: 1080), throwsStateError);
      final wide = ScreenGeometry(
        width: 2400,
        height: 1080,
        content: const Rectangle(240, 0, 1920, 1080),
      );
      expect(wide.point(640, 360), const Point(1200, 540));
      final portrait = ScreenGeometry(
        width: 720,
        height: 1280,
        content: const Rectangle(0, 437, 720, 405),
      );
      expect(
        portrait.region(const Rectangle(0, 0, 1280, 720)),
        const Rectangle(0, 437, 720, 405),
      );
      expect(() => wide.point(1280, 0), throwsRangeError);
      expect(() => wide.point(double.nan, 0), throwsRangeError);
      expect(
        () => wide.region(const Rectangle(1200, 0, 100, 40)),
        throwsRangeError,
      );
      expect(
        () => ScreenGeometry(
          width: 1280,
          height: 720,
          content: const Rectangle(-1, 0, 1280, 720),
        ),
        throwsArgumentError,
      );
    },
  );
  test('matching rejects stale geometry after a resolution change', () {
    final frame = Uint8List.fromList(
      img.encodePng(img.Image(width: 32, height: 18)),
    );
    expect(
      () => TemplateMatcher().findReference(
        frame,
        frame,
        geometry: ScreenGeometry(width: 1280, height: 720),
        referenceRegion: const Rectangle(0, 0, 1280, 720),
      ),
      throwsStateError,
    );
  });
}
