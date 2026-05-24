import 'package:flutter/material.dart';
import 'package:safewalk_hanoi/core/theme/app_theme.dart';
import 'package:safewalk_hanoi/models/detection.dart';

/// Overlay vẽ bounding boxes + khoảng cách lên camera preview.
/// Dùng CustomPainter cho performance tốt.
class CameraOverlay extends StatelessWidget {
  final List<DetectionResult> detections;
  final Size imageSize;

  const CameraOverlay({
    super.key,
    required this.detections,
    required this.imageSize,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DetectionPainter(
        detections: detections,
        imageSize: imageSize,
      ),
      size: Size.infinite,
    );
  }
}

class _DetectionPainter extends CustomPainter {
  final List<DetectionResult> detections;
  final Size imageSize;

  _DetectionPainter({
    required this.detections,
    required this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final det in detections) {
      final color = AppTheme.warning;
      final bbox = det.detection.bbox;

      // Scale bbox từ model size sang screen size
      final scaleX = size.width / imageSize.width;
      final scaleY = size.height / imageSize.height;

      final rect = Rect.fromLTRB(
        bbox.x1 * scaleX,
        bbox.y1 * scaleY,
        bbox.x2 * scaleX,
        bbox.y2 * scaleY,
      );

      // Vẽ bbox
      final borderPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      canvas.drawRect(rect, borderPaint);

      // Label background
      final label = det.detection.classNameVi;

      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final bgRect = Rect.fromLTWH(
        rect.left,
        rect.top - textPainter.height - 4,
        textPainter.width + 8,
        textPainter.height + 4,
      );

      canvas.drawRect(bgRect, Paint()..color = color);
      textPainter.paint(canvas, Offset(rect.left + 4, rect.top - textPainter.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
