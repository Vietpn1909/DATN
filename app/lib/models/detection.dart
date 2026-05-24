/// Data models cho detection results.
/// Không dùng freezed cho các model nhẹ này để tránh code generation complexity.

/// Bounding box (x1, y1, x2, y2) trong pixel
class BBox {
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const BBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  double get height => y2 - y1;
  double get width => x2 - x1;
  double get centerX => (x1 + x2) / 2;
  double get centerY => (y1 + y2) / 2;
  double get area => width * height;
}

/// Kết quả detection từ YOLO
class Detection {
  final int classId;
  final String className;
  final String classNameVi;
  final double confidence;
  final BBox bbox;

  const Detection({
    required this.classId,
    required this.className,
    required this.classNameVi,
    required this.confidence,
    required this.bbox,
  });
}

/// Kết quả detection kèm text cảnh báo (không còn khoảng cách)
class DetectionResult {
  final Detection detection;
  final String warningTextVi;

  const DetectionResult({
    required this.detection,
    required this.warningTextVi,
  });
}

/// Kết quả xử lý 1 frame
class FrameResult {
  final List<DetectionResult> detections;
  final DetectionResult? priorityDetection;
  final List<String> warningsVi;
  final int inferenceTimeMs;

  const FrameResult({
    required this.detections,
    this.priorityDetection,
    required this.warningsVi,
    required this.inferenceTimeMs,
  });

  static const empty = FrameResult(
    detections: [],
    warningsVi: [],
    inferenceTimeMs: 0,
  );
}
