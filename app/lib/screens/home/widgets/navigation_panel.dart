import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safewalk_hanoi/core/theme/app_theme.dart';
import 'package:safewalk_hanoi/models/navigation_step.dart';
import 'package:safewalk_hanoi/providers/navigation_provider.dart';
import 'package:safewalk_hanoi/screens/navigation/navigation_screen.dart';

/// Panel nhỏ hiển thị trên HomeScreen khi đang navigate.
/// Tap vào để mở NavigationScreen đầy đủ.
class NavigationPanel extends ConsumerWidget {
  const NavigationPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navState = ref.watch(navigationProvider);

    if (!navState.isNavigating && navState.status != NavigationStatus.searching) {
      return const SizedBox.shrink();
    }

    final step = navState.currentStep;
    final distM = navState.distanceToNextStepM;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NavigationScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: AppTheme.safe.withOpacity(0.9),
        child: Row(
          children: [
            const Icon(Icons.navigation, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    step?.instructionText ?? 'Đang tìm đường...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (distM != null)
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
            const Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}
