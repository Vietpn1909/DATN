import 'package:safewalk_hanoi/core/constants/app_constants.dart';
import 'package:safewalk_hanoi/models/detection.dart';
import 'package:safewalk_hanoi/services/danger_zone_service.dart';
import 'package:safewalk_hanoi/services/tts_service.dart';

/// Kết quả cảnh báo kèm mức ưu tiên TTS
class WarningResult {
  final String text;
  final TtsMessageType type;

  const WarningResult({required this.text, required this.type});
}

/// Quản lý cảnh báo: cooldown, ưu tiên, tránh spam.
///
/// Rules nâng cấp:
/// - Zone warning (đông đúc) được ưu tiên hơn individual warning
/// - Zone warning có cooldown riêng (5 giây) để tránh spam
/// - Individual warning chỉ phát cho confirmed detections (qua temporal filter)
/// - Mỗi class chỉ được cảnh báo 1 lần / 2 giây (hoặc 1 giây nếu close)
/// - Close warning có thể bypass cooldown
/// - Adaptive cooldown: khu vực đông → cảnh báo thưa hơn để tránh rối
///
/// Phân cấp ưu tiên:
/// - urgentWarning (classId 2,3,4,5): Ô tô, xe máy, xe buýt → ngắt navigation
/// - warning (classId 0,1): Người đi bộ, xe đạp → ngắt navigation
/// - lowWarning (classId 6,7,8,9,10): Vạch kẻ, đèn, biển báo... → không ngắt navigation
class WarningService {
  /// Thời điểm cảnh báo cuối cùng cho mỗi class (milliseconds since epoch)
  final Map<int, int> _lastWarningTime = {};

  /// Thời điểm cảnh báo cuối cùng (bất kỳ class nào)
  int _lastAnyWarningTime = 0;

  /// Thời điểm zone warning cuối cùng
  int _lastZoneWarningTime = 0;

  /// Cooldown cho zone warning (ms) — dài hơn individual
  static const int _zoneWarningCooldownMs = 5000;

  /// Class IDs cho mức ưu tiên cao nhất (phương tiện giao thông)
  /// motorcyclist=2, car=3, bus=4, motorcycle=5
  static const Set<int> _urgentClassIds = {2, 3, 4, 5};

  /// Class IDs cho mức ưu tiên trung bình (người)
  /// person=0, bicyclist=1
  static const Set<int> _warningClassIds = {0, 1};

  /// Xác định mức ưu tiên TTS dựa trên classId
  TtsMessageType _getWarningType(int classId) {
    if (_urgentClassIds.contains(classId)) return TtsMessageType.urgentWarning;
    if (_warningClassIds.contains(classId)) return TtsMessageType.warning;
    return TtsMessageType.lowWarning;
  }

  /// Lấy warning tiếp theo dựa trên DangerZoneResult
  ///
  /// Ưu tiên:
  /// 1. Zone warning (khu vực đông đúc)
  /// 2. Close warning (ngắt ngay)
  /// 3. Medium warning (queue)
  WarningResult? getNextWarning(
    FrameResult frameResult, {
    DangerZoneResult? dangerZone,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;

    // ──────────────────────────────────────────────────────────
    // Ưu tiên 1: Zone warning (khu vực đông đúc)
    // ──────────────────────────────────────────────────────────
    if (dangerZone != null &&
        dangerZone.hasZoneWarning &&
        dangerZone.level.index >= DangerLevel.dangerous.index) {
      if (now - _lastZoneWarningTime >= _zoneWarningCooldownMs) {
        _lastZoneWarningTime = now;
        _lastAnyWarningTime = now;
        return WarningResult(
          text: dangerZone.zoneWarningVi!,
          type: TtsMessageType.urgentWarning,
        );
      }
    }

    // Dùng confirmed detections nếu có dangerZone, nếu không dùng raw
    final detections = dangerZone?.confirmedDetections ??
        frameResult.detections;

    if (detections.isEmpty) return null;

    // ──────────────────────────────────────────────────────────
    // Adaptive cooldown: khu vực đông → cảnh báo thưa hơn
    // ──────────────────────────────────────────────────────────
    final adaptiveCooldown = _getAdaptiveCooldown(
      dangerZone?.confirmedCount ?? detections.length,
    );

    // Kiểm tra cooldown toàn cục
    if (now - _lastAnyWarningTime < adaptiveCooldown) {
      return null;
    }

    // ──────────────────────────────────────────────────────────
    // Ưu tiên 2: Individual warning (theo thứ tự list đã sort by area)
    // ──────────────────────────────────────────────────────────
    for (final det in detections) {
      final classId = det.detection.classId;
      final lastTime = _lastWarningTime[classId] ?? 0;

      if (now - lastTime >= adaptiveCooldown) {
        _lastWarningTime[classId] = now;
        _lastAnyWarningTime = now;
        return WarningResult(
          text: det.warningTextVi,
          type: _getWarningType(classId),
        );
      }
    }

    return null;
  }

  /// Adaptive cooldown dựa trên mật độ vật cản
  ///
  /// Khu vực đông → tăng cooldown để TTS không nói liên tục gây rối.
  /// Khu vực vắng → cooldown ngắn để phản hồi nhanh.
  int _getAdaptiveCooldown(int obstacleCount) {
    if (obstacleCount >= 8) return 2000;  // Rất đông: 2s giữa mỗi cảnh báo
    if (obstacleCount >= 5) return 1500;  // Đông: 1.5s
    if (obstacleCount >= 3) return 1200;  // Vừa: 1.2s
    return 1000; // Bình thường: 1s (AppConstants.warningCooldownMs là 3s nên bỏ đi)
  }

  /// Reset cooldown (khi dừng detection)
  void reset() {
    _lastWarningTime.clear();
    _lastAnyWarningTime = 0;
    _lastZoneWarningTime = 0;
  }
}


