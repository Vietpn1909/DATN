import 'package:safewalk_hanoi/core/constants/app_constants.dart';
import 'package:safewalk_hanoi/models/detection.dart';
import 'package:safewalk_hanoi/services/danger_zone_service.dart';

/// Quản lý cảnh báo: cooldown, ưu tiên, tránh spam.
///
/// Rules nâng cấp:
/// - Zone warning (đông đúc) được ưu tiên hơn individual warning
/// - Zone warning có cooldown riêng (5 giây) để tránh spam
/// - Individual warning chỉ phát cho confirmed detections (qua temporal filter)
/// - Mỗi class chỉ được cảnh báo 1 lần / 2 giây (hoặc 1 giây nếu close)
/// - Close warning có thể bypass cooldown
/// - Adaptive cooldown: khu vực đông → cảnh báo thưa hơn để tránh rối
class WarningService {
  /// Thời điểm cảnh báo cuối cùng cho mỗi class (milliseconds since epoch)
  final Map<int, int> _lastWarningTime = {};

  /// Thời điểm cảnh báo cuối cùng (bất kỳ class nào)
  int _lastAnyWarningTime = 0;

  /// Thời điểm zone warning cuối cùng
  int _lastZoneWarningTime = 0;

  /// Cooldown cho zone warning (ms) — dài hơn individual
  static const int _zoneWarningCooldownMs = 5000;

  /// Lấy warning tiếp theo dựa trên DangerZoneResult
  ///
  /// Ưu tiên:
  /// 1. Zone warning (khu vực đông đúc + spatial advice)
  /// 2. Close warning (ngắt ngay)
  /// 3. Medium warning (queue)
  String? getNextWarning(
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
        return dangerZone.zoneWarningVi;
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
        return det.warningTextVi;
      }
    }

    return null;
  }

  /// Adaptive cooldown dựa trên mật độ vật cản
  ///
  /// Khu vực đông → tăng cooldown để TTS không nói liên tục gây rối.
  /// Khu vực vắng → cooldown ngắn để phản hồi nhanh.
  int _getAdaptiveCooldown(int obstacleCount) {
    if (obstacleCount >= 8) return 3000;  // Rất đông: 3s giữa mỗi cảnh báo
    if (obstacleCount >= 5) return 2500;  // Đông: 2.5s
    if (obstacleCount >= 3) return 2000;  // Vừa: 2s (mặc định)
    return AppConstants.warningCooldownMs; // Bình thường: 2s
  }

  /// Reset cooldown (khi dừng detection)
  void reset() {
    _lastWarningTime.clear();
    _lastAnyWarningTime = 0;
    _lastZoneWarningTime = 0;
  }
}
