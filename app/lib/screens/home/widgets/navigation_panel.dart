import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safewalk_hanoi/core/theme/app_theme.dart';
import 'package:safewalk_hanoi/models/navigation_step.dart';
import 'package:safewalk_hanoi/providers/navigation_provider.dart';
import 'package:safewalk_hanoi/screens/navigation/navigation_screen.dart';

/// Panel nhỏ hiển thị trên HomeScreen khi đang navigate.
/// Tap vào để mở NavigationScreen đầy đủ (xem bản đồ).
/// Nút dừng để dừng chỉ đường.
///
/// Trạng thái hiển thị:
/// - searching: "Đang tìm đường..."
/// - navigating: Bước hiện tại + khoảng cách + nút dừng
/// - arrived: "Bạn đã đến nơi!"
/// - idle/error: Ẩn panel
class NavigationPanel extends ConsumerWidget {
  const NavigationPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navState = ref.watch(navigationProvider);

    // Chỉ hiển thị khi đang tìm đường, đang navigate, hoặc vừa đến nơi
    if (navState.status == NavigationStatus.idle ||
        navState.status == NavigationStatus.error) {
      return const SizedBox.shrink();
    }

    final step = navState.currentStep;
    final distM = navState.distanceToNextStepM;

    // Màu nền theo trạng thái
    final Color bgColor;
    switch (navState.status) {
      case NavigationStatus.searching:
        bgColor = AppTheme.warningMedium.withOpacity(0.9);
        break;
      case NavigationStatus.arrived:
        bgColor = AppTheme.safe;
        break;
      default:
        bgColor = AppTheme.safe.withOpacity(0.9);
        break;
    }

    // Nội dung text chính
    final String mainText;
    switch (navState.status) {
      case NavigationStatus.searching:
        mainText = 'Đang tìm đường...';
        break;
      case NavigationStatus.arrived:
        mainText = 'Bạn đã đến nơi!';
        break;
      default:
        mainText = step?.instructionText ?? 'Đang xác định vị trí...';
        break;
    }

    // Icon theo trạng thái
    final IconData iconData;
    switch (navState.status) {
      case NavigationStatus.arrived:
        iconData = Icons.check_circle;
        break;
      case NavigationStatus.searching:
        iconData = Icons.search;
        break;
      default:
        iconData = Icons.navigation;
        break;
    }

    return Semantics(
      label: navState.isNavigating
          ? 'Đang chỉ đường. $mainText. Chạm để xem bản đồ.'
          : mainText,
      child: GestureDetector(
        onTap: () {
          // Tap để mở NavigationScreen xem bản đồ
          if (navState.isNavigating ||
              navState.status == NavigationStatus.searching) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NavigationScreen()),
            );
          }
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: bgColor,
          child: Row(
            children: [
              Icon(iconData, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      mainText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (distM != null && navState.isNavigating)
                      Text(
                        distM >= 1000
                            ? '${(distM / 1000).toStringAsFixed(1)} km'
                            : '${distM.round()} m',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
              // Nút dừng chỉ đường (chỉ hiện khi đang navigate)
              if (navState.isNavigating)
                Semantics(
                  button: true,
                  label: 'Dừng chỉ đường',
                  child: GestureDetector(
                    onTap: () {
                      ref.read(navigationProvider.notifier).stopNavigation();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.stop,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}
