import 'dart:math';

/// Maps reference-art pixels to screenshot pixels, never Android dp or wm size.
/// A different aspect ratio requires an explicitly verified game content region.
class ScreenGeometry {
  ScreenGeometry({
    required this.width,
    required this.height,
    this.referenceWidth = 1280,
    this.referenceHeight = 720,
    Rectangle<int>? content,
  }) : content = content ?? Rectangle(0, 0, width, height) {
    if (width <= 0 ||
        height <= 0 ||
        referenceWidth <= 0 ||
        referenceHeight <= 0) {
      throw ArgumentError('画面尺寸必须为正数');
    }
    final area = this.content;
    if (area.left < 0 ||
        area.top < 0 ||
        area.width <= 0 ||
        area.height <= 0 ||
        area.right > width ||
        area.bottom > height) {
      throw ArgumentError('游戏内容区域超出截图');
    }
    final sx = area.width / referenceWidth, sy = area.height / referenceHeight;
    if ((sx / sy - 1).abs() > .005) {
      throw StateError('画面宽高比与参考资源不同，请先校准游戏内容区域或使用对应布局资源');
    }
  }
  final int width, height, referenceWidth, referenceHeight;
  final Rectangle<int> content;
  double get scale =>
      min(content.width / referenceWidth, content.height / referenceHeight);

  Point<int> point(num x, num y) {
    if (!x.isFinite ||
        !y.isFinite ||
        x < 0 ||
        y < 0 ||
        x >= referenceWidth ||
        y >= referenceHeight) {
      throw RangeError('参考坐标超出资源画面');
    }
    return Point(
      (content.left + x * scale).round().clamp(content.left, content.right - 1),
      (content.top + y * scale).round().clamp(content.top, content.bottom - 1),
    );
  }

  Rectangle<int> region(Rectangle<int> reference) {
    if (reference.width <= 0 ||
        reference.height <= 0 ||
        reference.left < 0 ||
        reference.top < 0 ||
        reference.right > referenceWidth ||
        reference.bottom > referenceHeight) {
      throw RangeError('参考识别区域越界');
    }
    final left = content.left + (reference.left * scale).floor();
    final top = content.top + (reference.top * scale).floor();
    final right = min(
      content.right,
      content.left + (reference.right * scale).ceil(),
    );
    final bottom = min(
      content.bottom,
      content.top + (reference.bottom * scale).ceil(),
    );
    return Rectangle(left, top, right - left, bottom - top);
  }
}
