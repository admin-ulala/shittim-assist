import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class MatchResult {
  const MatchResult(this.x, this.y, this.width, this.height, this.confidence);
  final int x, y, width, height;
  final double confidence;
  int get centerX => x + width ~/ 2;
  int get centerY => y + height ~/ 2;
}

/// Portable reference matcher. Production OpenCV/OCR backends can replace it.
/// Searches within a bounded ROI at a fixed scale, never assumes wm size.
class TemplateMatcher {
  MatchResult? find(
    Uint8List frame,
    Uint8List template, {
    double threshold = .94,
    int? left,
    int? top,
    int? right,
    int? bottom,
  }) {
    if (threshold < 0 || threshold > 1) throw ArgumentError('threshold');
    final source = img.decodeImage(frame);
    final target = img.decodeImage(template);
    if (source == null || target == null) throw const FormatException('无效图片');
    final x0 = max(0, left ?? 0), y0 = max(0, top ?? 0);
    final xEnd = min(source.width, right ?? source.width) - target.width;
    final yEnd = min(source.height, bottom ?? source.height) - target.height;
    if (target.width == 0 || target.height == 0 || xEnd < x0 || yEnd < y0) {
      return null;
    }
    var best = -1.0;
    var bx = 0, by = 0;
    final sampleStep = max(1, min(target.width, target.height) ~/ 16);
    for (var y = y0; y <= yEnd; y++) {
      for (var x = x0; x <= xEnd; x++) {
        var error = 0.0, count = 0;
        for (var ty = 0; ty < target.height; ty += sampleStep) {
          for (var tx = 0; tx < target.width; tx += sampleStep) {
            final a = source.getPixel(x + tx, y + ty),
                b = target.getPixel(tx, ty);
            error += (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();
            count++;
          }
        }
        final score = 1 - error / (count * 765);
        if (score > best) {
          best = score;
          bx = x;
          by = y;
        }
      }
    }
    return best >= threshold
        ? MatchResult(bx, by, target.width, target.height, best)
        : null;
  }
}
