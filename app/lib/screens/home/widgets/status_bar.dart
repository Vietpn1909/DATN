import 'package:flutter/material.dart';
import 'package:safewalk_hanoi/core/theme/app_theme.dart';
import 'package:safewalk_hanoi/models/detection.dart';

/// Thanh trạng thái ở dưới màn hình.
/// Hiển thị: cảnh báo gần nhất, FPS, trạng thái detection.
/// Font >= 24sp, contrast cao cho low vision.
class StatusBar extends StatelessWidget {
  final bool isDetecting;
  final DetectionResult? priorityDetection;
  final double fps;
  final String? currentWarning;

  const StatusBar({
    super.key,
    required this.isDetecting,
    this.priorityDetection,
    this.fps = 0,
    this.currentWarning,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppTheme.primaryDark,
        border: Border(
          top: BorderSide(color: AppTheme.accent, width: 2),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Trạng thái chính
            Semantics(
              liveRegion: true,
              child: Text(
                _getStatusText(),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: _getStatusColor(),
                ),
              ),
            ),

            if (currentWarning != null) ...[
              const SizedBox(height: 4),
              Semantics(
                liveRegion: true,
                child: Text(
                  currentWarning!,
                  style: const TextStyle(
                    fontSize: 24,
                    color: AppTheme.warning,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],

            const SizedBox(height: 4),
            // FPS (nhỏ hơn, cho developer/caregiver)
            Text(
              '${fps.toStringAsFixed(0)} FPS',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusText() {
    if (!isDetecting) return 'Chạm để bắt đầu';

    if (priorityDetection != null) {
      final name = priorityDetection!.detection.classNameVi;
      return 'Phía trước có: $name';
    }

    return 'Đang phát hiện vật cản...';
  }

  Color _getStatusColor() {
    if (!isDetecting) return AppTheme.accent;

    if (priorityDetection != null) {
      return AppTheme.warning;
    }
    return AppTheme.safe;
  }
}
