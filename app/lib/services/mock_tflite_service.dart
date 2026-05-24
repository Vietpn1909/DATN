import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:safewalk_hanoi/models/detection.dart';
import 'package:safewalk_hanoi/core/constants/class_labels.dart';

/// Mock TFLite Service để test UI flow trên máy tính
/// Simulate realistic detection results mà không cần GPU
class MockTFLiteService {
  bool _isReady = false;
  void Function(FrameResult result)? onResult;
  void Function(String message)? onDebugLog;

  bool get isReady => _isReady;

  int _frameCount = 0;
  final _random = DateTime.now().millisecond;

  /// Giả lập initialize
  Future<void> initialize() async {
    debugPrint('[MockTFLite] Initializing mock service...');
    await Future.delayed(const Duration(milliseconds: 500));
    _isReady = true;
    onDebugLog?.call('[MockTFLite] Model loaded (simulated) ✓');
    onDebugLog?.call('[MockTFLite] Isolate ready (simulated) ✓');
    debugPrint('[MockTFLite] Ready ✓');
  }

  /// Simulate frame processing - generates realistic detections
  /// Accepts CameraImage or mock object for testing
  void processFrame(dynamic image) {
    if (!_isReady) return;

    _frameCount++;

    // Get dimensions from CameraImage or mock
    final (width, height) = _getImageDimensions(image);

    // Simulate inference delay (40-70ms)
    Future.delayed(Duration(milliseconds: 40 + (_frameCount % 30)), () {
      final result = _generateMockDetections(_frameCount, width, height);
      onResult?.call(result);

      // Log every 30 frames
      if (_frameCount % 30 == 0) {
        onDebugLog?.call(
          '[MockTFLite] Frame #$_frameCount: ${result.detections.length} detections, '
          '${result.inferenceTimeMs}ms',
        );
      }
    });
  }

  /// Extract dimensions from CameraImage or mock
  (int, int) _getImageDimensions(dynamic image) {
    if (image is CameraImage) {
      return (image.width, image.height);
    }
    // For mock testing - default dimensions
    return (480, 640);
  }

  /// Tạo mock detections theo scenario
  FrameResult _generateMockDetections(int frameNum, int imgW, int imgH) {
    // Vary detections theo frame number để mô phỏng realistic
    final cycle = frameNum % 120; // 120 frame cycle

    List<DetectionResult> detections = [];

    // Scenario cycles:
    if (cycle < 30) {
      // Frame 0-30: Empty street (occasional pole)
      if (cycle % 15 == 0 && cycle > 5) {
        detections = [
          _createDetection(
            classId: 8, // pole
            className: 'pole',
            classNameVi: 'cột',
            confidence: 0.75,
            bboxNorm: (0.3, 0.1, 0.5, 0.8),
            imgSize: (imgW, imgH),
          ),
        ];
      }
    } else if (cycle < 60) {
      // Frame 30-60: Person walking towards
      final progress = (cycle - 30) / 30;

      detections = [
        _createDetection(
          classId: 0, // person
          className: 'person',
          classNameVi: 'người',
          confidence: 0.85 + progress * 0.1,
          bboxNorm: (0.35 - progress * 0.1, 0.2, 0.65 + progress * 0.1, 0.9),
          imgSize: (imgW, imgH),
        ),
      ];
    } else if (cycle < 90) {
      // Frame 60-90: Multiple vehicles
      detections = [
        _createDetection(
          classId: 3, // car
          className: 'car',
          classNameVi: 'ô tô',
          confidence: 0.88,
          bboxNorm: (0.1, 0.35, 0.45, 0.75),
          imgSize: (imgW, imgH),
        ),
        _createDetection(
          classId: 5, // motorcycle
          className: 'motorcycle',
          classNameVi: 'xe máy',
          confidence: 0.82,
          bboxNorm: (0.55, 0.4, 0.8, 0.8),
          imgSize: (imgW, imgH),
        ),
      ];
    } else {
      // Frame 90-120: Busy street with many objects
      detections = [
        _createDetection(
          classId: 0, // person
          className: 'person',
          classNameVi: 'người',
          confidence: 0.9,
          bboxNorm: (0.2, 0.15, 0.4, 0.85),
          imgSize: (imgW, imgH),
        ),
        _createDetection(
          classId: 5, // motorcycle
          className: 'motorcycle',
          classNameVi: 'xe máy',
          confidence: 0.85,
          bboxNorm: (0.5, 0.3, 0.75, 0.75),
          imgSize: (imgW, imgH),
        ),
      ];
    }

    return FrameResult(
      detections: detections,
      priorityDetection: detections.isEmpty ? null : detections.first,
      warningsVi: [],
      inferenceTimeMs: 45 + (_random % 30),
    );
  }

  /// Helper: Create a detection with normalized bbox
  DetectionResult _createDetection({
    required int classId,
    required String className,
    required String classNameVi,
    required double confidence,
    required (double, double, double, double) bboxNorm, // x1, y1, x2, y2 normalized
    required (int, int) imgSize,
  }) {
    final (x1, y1, x2, y2) = bboxNorm;
    final (w, h) = imgSize;

    final bbox = BBox(
      x1: x1 * w,
      y1: y1 * h,
      x2: x2 * w,
      y2: y2 * h,
    );

    return DetectionResult(
      detection: Detection(
        classId: classId,
        className: className,
        classNameVi: classNameVi,
        confidence: confidence,
        bbox: bbox,
      ),
      warningTextVi: 'Phía trước có $classNameVi',
    );
  }

  /// Giả lập dispose
  Future<void> dispose() async {
    _isReady = false;
  }
}
