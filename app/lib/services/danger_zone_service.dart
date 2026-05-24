import 'package:safewalk_hanoi/models/detection.dart';

/// Mức nguy hiểm tổng hợp của khu vực
enum DangerLevel { safe, moderate, dangerous, veryDangerous }

/// Kết quả phân tích DangerZone
class DangerZoneResult {
  final DangerLevel level;
  final double score; // 0.0 - 1.0
  final String? zoneWarningVi; // Cảnh báo mức khu vực
  final String? spatialAdviceVi; // Gợi ý hướng di chuyển
  final int confirmedCount; // Số vật cản đã xác nhận (qua temporal filter)
  final int rawCount; // Số vật cản raw (trước filter)
  final List<DetectionResult> confirmedDetections;

  const DangerZoneResult({
    required this.level,
    required this.score,
    this.zoneWarningVi,
    this.spatialAdviceVi,
    required this.confirmedCount,
    required this.rawCount,
    required this.confirmedDetections,
  });

  static const safe = DangerZoneResult(
    level: DangerLevel.safe,
    score: 0.0,
    confirmedCount: 0,
    rawCount: 0,
    confirmedDetections: [],
  );

  bool get hasSpatialAdvice => spatialAdviceVi != null;
  bool get hasZoneWarning => zoneWarningVi != null;
}

class DangerZoneService {
  final int imageSize;

  final List<List<_TrackedObject>> _recentFrames = [];
  static const int _temporalWindowSize = 3;
  static const int _minFramesToConfirm = 2;
  static const double _minBboxAreaRatio = 0.005;

  DangerZoneService({required this.imageSize});

  DangerZoneResult analyze(List<DetectionResult> detections) {
    if (detections.isEmpty) {
      _pushFrame([]);
      return DangerZoneResult.safe;
    }

    final totalArea = imageSize * imageSize;

    final sizeFiltered = detections.where((det) {
      final areaRatio = det.detection.bbox.area / (imageSize * imageSize);
      return areaRatio >= _minBboxAreaRatio;
    }).toList();

    final currentTracked = sizeFiltered.map((det) {
      final zone = _getZone(det.detection.bbox.centerX);
      return _TrackedObject(
        classId: det.detection.classId,
        zone: zone,
        detection: det,
      );
    }).toList();

    _pushFrame(currentTracked);

    final confirmed = <DetectionResult>[];
    for (final tracked in currentTracked) {
      if (_isConfirmed(tracked.classId, tracked.zone)) {
        confirmed.add(tracked.detection);
      }
    }

    if (confirmed.isEmpty) {
      return DangerZoneResult(
        level: DangerLevel.safe,
        score: 0.0,
        confirmedCount: 0,
        rawCount: detections.length,
        confirmedDetections: [],
      );
    }

    double totalScore = 0;
    int dangerousCount = 0;

    for (final det in confirmed) {
      final classWeight = _classWeights[det.detection.classId] ?? 0.5;
      
      // Proximity weight dựa trên area ratio (0.05 - 0.20+)
      final areaRatio = det.detection.bbox.area / (imageSize * imageSize);
      double proximityWeight;
      if (areaRatio > 0.15) {
        proximityWeight = 1.0;
        dangerousCount++;
      } else if (areaRatio > 0.05) {
        proximityWeight = 0.5;
        dangerousCount++;
      } else {
        proximityWeight = 0.1;
      }

      totalScore += classWeight * proximityWeight;
    }

    final normalizedScore = (totalScore / 5.0).clamp(0.0, 1.0);
    final spatialAdvice = _analyzeSpatial(confirmed);

    DangerLevel level;
    String? zoneWarning;

    if (normalizedScore > 0.8 || dangerousCount >= 5) {
      level = DangerLevel.veryDangerous;
      zoneWarning = 'Cảnh báo! Khu vực rất đông đúc. Hãy đi chậm và cẩn thận.';
    } else if (normalizedScore > 0.5 || dangerousCount >= 3) {
      level = DangerLevel.dangerous;
      zoneWarning = 'Khu vực đông đúc. Hãy chú ý.';
    } else if (normalizedScore > 0.2) {
      level = DangerLevel.moderate;
    } else {
      level = DangerLevel.safe;
    }

    String? fullZoneWarning = zoneWarning;
    if (spatialAdvice != null && level.index >= DangerLevel.dangerous.index) {
      fullZoneWarning = '${zoneWarning ?? ''} $spatialAdvice';
    }

    return DangerZoneResult(
      level: level,
      score: normalizedScore,
      zoneWarningVi: fullZoneWarning?.trim(),
      spatialAdviceVi: spatialAdvice,
      confirmedCount: confirmed.length,
      rawCount: detections.length,
      confirmedDetections: confirmed,
    );
  }

  void reset() {
    _recentFrames.clear();
  }

  String? _analyzeSpatial(List<DetectionResult> confirmed) {
    int left = 0, center = 0, right = 0;

    for (final det in confirmed) {
      final areaRatio = det.detection.bbox.area / (imageSize * imageSize);
      if (areaRatio < 0.05) continue; // Bỏ qua vật ở xa

      final zone = _getZone(det.detection.bbox.centerX);
      switch (zone) {
        case _Zone.left: left++;
        case _Zone.center: center++;
        case _Zone.right: right++;
      }
    }

    final total = left + center + right;
    if (total < 2) return null;

    if (left == 0 && (center > 0 || right > 0)) {
      return 'Bên trái trống hơn, hãy đi sang trái.';
    } else if (right == 0 && (center > 0 || left > 0)) {
      return 'Bên phải trống hơn, hãy đi sang phải.';
    } else if (center == 0 && left > 0 && right > 0) {
      return 'Phía trước trống, hãy đi thẳng.';
    }

    return null;
  }

  _Zone _getZone(double centerX) {
    final normalized = centerX / imageSize;
    if (normalized < 0.33) return _Zone.left;
    if (normalized > 0.67) return _Zone.right;
    return _Zone.center;
  }

  void _pushFrame(List<_TrackedObject> tracked) {
    _recentFrames.add(tracked);
    if (_recentFrames.length > _temporalWindowSize) {
      _recentFrames.removeAt(0);
    }
  }

  bool _isConfirmed(int classId, _Zone zone) {
    if (_recentFrames.length < _minFramesToConfirm) return true;
    int count = 0;
    for (final frame in _recentFrames) {
      final found = frame.any((obj) => obj.classId == classId && obj.zone == zone);
      if (found) count++;
    }
    return count >= _minFramesToConfirm;
  }

  static const Map<int, double> _classWeights = {
    0: 0.6, 1: 0.7, 2: 0.8, 3: 1.0, 4: 1.0, 5: 0.9,
    6: 0.05, 7: 0.2, 8: 0.05, 9: 0.05, 10: 0.3,
  };
}

enum _Zone { left, center, right }

class _TrackedObject {
  final int classId;
  final _Zone zone;
  final DetectionResult detection;

  const _TrackedObject({
    required this.classId,
    required this.zone,
    required this.detection,
  });
}
