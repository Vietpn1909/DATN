import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:safewalk_hanoi/core/constants/class_labels.dart';
import 'package:safewalk_hanoi/models/detection.dart';

/// Decode raw YOLO11 TFLite output thành List<Detection>.
class YoloPostprocessor {
  final int inputSize;
  final int numClasses;
  final double confThreshold;
  final double iouThreshold;

  const YoloPostprocessor({
    required this.inputSize,
    required this.numClasses,
    required this.confThreshold,
    required this.iouThreshold,
  });

  /// Xử lý output tensors từ TFLite
  List<Detection> process(Map<int, Object> outputs, [Map<int, List<int>>? outputShapes]) {
    final List<List<double>> candidates = _parseOutput(outputs, outputShapes);
    debugPrint('[YOLO] Extracted ${candidates.length} candidates from tensor');
    if (candidates.isEmpty) return [];

    // Lọc theo confidence
    final filtered = <_RawDetection>[];
    for (final candidate in candidates) {
      if (candidate.length < 4 + numClasses) continue;

      // Kiểm tra xem model trả về toạ độ normalized (0-1) hay pixel (0-320)
      // Thông thường object có width/height > 1.5 pixel trừ khi nó là noise cực nhỏ.
      final bool isNormalized = candidate[2] <= 1.5 && candidate[3] <= 1.5;
      final double scale = isNormalized ? inputSize.toDouble() : 1.0;

      final cx = candidate[0] * scale;
      final cy = candidate[1] * scale;
      final w = candidate[2] * scale;
      final h = candidate[3] * scale;

      double maxScore = 0;
      int maxClassId = 0;
      for (int c = 0; c < numClasses; c++) {
        final score = candidate[4 + c];
        if (score > maxScore) {
          maxScore = score;
          maxClassId = c;
        }
      }

      // Sử dụng ngưỡng động theo class (nếu có), nếu không có thì dùng ngưỡng mặc định (confThreshold)
      final dynamicThreshold = ClassLabels.confThresholds[maxClassId] ?? confThreshold;
      if (maxScore < dynamicThreshold) continue;

      // Bộ lọc hình học (Heuristic Aspect Ratio Filter)
      // Ô tô (3) và Xe buýt (4) thường nằm ngang hoặc vuông, rất hiếm khi là một hình chữ nhật đứng hẹp.
      // Nếu tỷ lệ width/height < 0.6 (quá hẹp và cao), đó thường là cánh cửa, cột nhà, hoặc người bị nhận diện nhầm.
      if (maxClassId == 3 || maxClassId == 4) {
        final aspectRatio = w / h;
        if (aspectRatio < 0.6) {
          continue; // Bỏ qua vật thể quá hẹp và cao (không thể là ô tô)
        }
        // Ô tô/xe buýt thật phải chiếm ít nhất 2% diện tích khung hình
        final bboxArea = w * h;
        final imageArea = inputSize * inputSize;
        if (bboxArea / imageArea < 0.02) {
          continue; // Bỏ qua bbox quá nhỏ (noise)
        }
      }

      // Bộ lọc hình học cho xe máy (5) và người đi xe máy (2)
      // Xe máy thật phải chiếm ít nhất 1.5% diện tích khung hình
      if (maxClassId == 2 || maxClassId == 5) {
        final bboxArea = w * h;
        final imageArea = inputSize * inputSize;
        if (bboxArea / imageArea < 0.015) {
          continue; // Bỏ qua bbox quá nhỏ (noise)
        }
      }

      filtered.add(_RawDetection(
        x1: cx - w / 2,
        y1: cy - h / 2,
        x2: cx + w / 2,
        y2: cy + h / 2,
        classId: maxClassId,
        confidence: maxScore,
      ));
    }
    
    debugPrint('[YOLO] Passed confidence threshold: ${filtered.length} boxes');

    // NMS
    final nmsResult = _nms(filtered);

    // Convert to Detection objects + Filter only relevant classes
    final results = <Detection>[];
    for (final raw in nmsResult) {
      final nameVi = ClassLabels.namesVi[raw.classId];
      if (nameVi == null) continue; 

      results.add(Detection(
        classId: raw.classId,
        className: ClassLabels.names[raw.classId] ?? 'unknown',
        classNameVi: nameVi,
        confidence: raw.confidence,
        bbox: BBox(x1: raw.x1, y1: raw.y1, x2: raw.x2, y2: raw.y2),
      ));
    }
    return results;
  }

  List<List<double>> _parseOutput(Map<int, Object> outputs, Map<int, List<int>>? shapes) {
    try {
      // Find the detection tensor (the one with the largest number of elements or matching [1, 47, 8400])
      Object? targetOutput;
      List<int>? targetShape;

      if (shapes != null) {
        for (final entry in outputs.entries) {
          final shape = shapes[entry.key];
          if (shape != null && shape.length == 3 && shape[0] == 1 && (shape[1] >= 4 + numClasses || shape[2] >= 4 + numClasses)) {
            targetOutput = entry.value;
            targetShape = shape;
            break;
          }
        }
      } else {
        targetOutput = outputs[0];
      }

      if (targetOutput == null) return [];

      if (targetOutput is Float32List) {
        // Xử lý output dạng phẳng (đã tối ưu bằng Float32List trong isolate)
        if (targetShape == null) {
           // Đoán shape từ số lượng phần tử
           final int total = targetOutput.length;
           // YOLO11-seg: 47 features * 8400 boxes = 394800
           // YOLOv8: 84 features * 8400 boxes = 705600
           final int dim1 = 4 + numClasses; // 15
           // If it's a segmentation model, dim1 might be 47 or larger. We assume 8400 boxes.
           if (total % 8400 == 0) {
              targetShape = [1, total ~/ 8400, 8400];
           } else {
              return [];
           }
        }

        final int dim1 = targetShape[1];
        final int dim2 = targetShape[2];
        final expectedMinDim = 4 + numClasses;

        if (dim1 >= expectedMinDim && dim2 > dim1) {
          // [1, 47, 8400] -> Mảng phẳng kích thước dim1 * dim2. Cột là boxes.
          final candidates = <List<double>>[];
          for (int j = 0; j < dim2; j++) {
            final box = <double>[];
            for (int i = 0; i < expectedMinDim; i++) {
              box.add(targetOutput[i * dim2 + j]);
            }
            candidates.add(box);
          }
          return candidates;
        } else if (dim2 >= expectedMinDim && dim1 > dim2) {
          // [1, 8400, 47] -> Mảng phẳng kích thước dim1 * dim2. Hàng là boxes.
          final candidates = <List<double>>[];
          for (int i = 0; i < dim1; i++) {
            final box = <double>[];
            for (int j = 0; j < expectedMinDim; j++) {
              box.add(targetOutput[i * dim2 + j]);
            }
            candidates.add(box);
          }
          return candidates;
        }
      } else {
        // Fallback for nested lists (Legacy mode)
        final rawOutput = targetOutput;
        final batch = (rawOutput as List)[0] as List;
        final int dim1 = batch.length;
        final int dim2 = (batch[0] as List).length;
        final int expectedMinDim = 4 + numClasses;

        if (dim1 >= expectedMinDim && dim2 > dim1) {
          final candidates = <List<double>>[];
          for (int i = 0; i < dim2; i++) {
            final box = <double>[];
            for (int j = 0; j < expectedMinDim; j++) {
              box.add((batch[j] as List)[i].toDouble());
            }
            candidates.add(box);
          }
          return candidates;
        }
      }
    } catch (e) {
      debugPrint('[YOLO] ERROR parsing: $e');
    }
    return [];
  }

  static const _humanGroup = {0, 1, 2}; // person, bicyclist, motorcyclist
  static const _vehicleGroup = {3, 4, 5}; // car, bus, motorcycle

  List<_RawDetection> _nms(List<_RawDetection> detections) {
    if (detections.isEmpty) return [];
    detections.sort((a, b) => b.confidence.compareTo(a.confidence));
    if (detections.length > 50) detections = detections.sublist(0, 50);

    final keep = <_RawDetection>[];
    while (detections.isNotEmpty) {
      final best = detections.removeAt(0);
      keep.add(best);
      detections.removeWhere((det) {
        final sameHumanGroup = _humanGroup.contains(best.classId) && _humanGroup.contains(det.classId);
        final sameVehicleGroup = _vehicleGroup.contains(best.classId) && _vehicleGroup.contains(det.classId);
        if (!(sameHumanGroup || sameVehicleGroup) && det.classId != best.classId) return false;
        return _iou(best, det) > iouThreshold;
      });
    }
    return keep;
  }

  double _iou(_RawDetection a, _RawDetection b) {
    final x1 = max(a.x1, b.x1);
    final y1 = max(a.y1, b.y1);
    final x2 = min(a.x2, b.x2);
    final y2 = min(a.y2, b.y2);
    final intersection = max(0.0, x2 - x1) * max(0.0, y2 - y1);
    final areaA = (a.x2 - a.x1) * (a.y2 - a.y1);
    final areaB = (b.x2 - b.x1) * (b.y2 - b.y1);
    final union = areaA + areaB - intersection;
    return union > 0 ? intersection / union : 0;
  }
}

class _RawDetection {
  final double x1, y1, x2, y2;
  final int classId;
  final double confidence;
  const _RawDetection({required this.x1, required this.y1, required this.x2, required this.y2, required this.classId, required this.confidence});
}
