import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:safewalk_hanoi/core/constants/app_constants.dart';
import 'package:safewalk_hanoi/core/theme/app_theme.dart';
import 'package:safewalk_hanoi/models/navigation_step.dart';
import 'package:safewalk_hanoi/providers/navigation_provider.dart';

/// Màn hình chỉ đường với bản đồ Goong.
///
/// Layout (tối ưu cho người khiếm thị):
/// ┌─────────────────────────┐
/// │  [Bước hiện tại - lớn]  │  Instruction panel
/// │  Rẽ trái sau 100m       │
/// ├─────────────────────────┤
/// │                         │
/// │      Goong Map          │  Map view (flutter_map)
/// │   (route + position)    │
/// │                         │
/// ├─────────────────────────┤
/// │  [Bước tiếp theo]       │  Next step preview
/// │  [Dừng chỉ đường]       │  Stop button
/// └─────────────────────────┘
class NavigationScreen extends ConsumerStatefulWidget {
  const NavigationScreen({super.key});

  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  final MapController _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _stopNavigation() async {
    await ref.read(navigationProvider.notifier).stopNavigation();
    if (mounted) Navigator.of(context).pop();
  }

  /// Convert custom LatLng → latlong2 LatLng cho flutter_map
  ll.LatLng _toLLLatLng(LatLng p) => ll.LatLng(p.lat, p.lng);

  @override
  Widget build(BuildContext context) {
    final navState = ref.watch(navigationProvider);

    // Di chuyển camera khi vị trí thay đổi
    ref.listen<NavigationState>(navigationProvider, (prev, next) {
      if (next.currentPosition != null &&
          prev?.currentPosition != next.currentPosition) {
        _mapController.move(
          _toLLLatLng(next.currentPosition!),
          _mapController.camera.zoom,
        );
      }
      // Tự động pop khi arrived
      if (next.status == NavigationStatus.arrived && mounted) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });

    final route = navState.route;

    // Điểm giữa của bản đồ mặc định: Hồ Hoàn Kiếm
    final initialCenter = navState.currentPosition != null
        ? _toLLLatLng(navState.currentPosition!)
        : const ll.LatLng(21.0285, 105.8542);

    // Polyline points
    final routePoints = route?.polylinePoints
        .map(_toLLLatLng)
        .toList() ?? [];

    // Markers
    final markers = <Marker>[];
    if (navState.currentPosition != null) {
      markers.add(Marker(
        point: _toLLLatLng(navState.currentPosition!),
        child: const Icon(Icons.navigation, color: AppTheme.accent, size: 36),
      ));
    }
    if (route != null) {
      markers.add(Marker(
        point: _toLLLatLng(route.steps.last.endLocation),
        child: const Icon(Icons.location_on, color: AppTheme.danger, size: 40),
      ));
    }

    return Scaffold(
      backgroundColor: AppTheme.primaryDark,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryDark,
        title: Text(
          route?.destinationName ?? 'Đang chỉ đường',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _stopNavigation,
          tooltip: 'Dừng chỉ đường',
        ),
        actions: [
          if (route != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  route.totalDistanceText,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ─── Instruction panel ───────────────────────────────────────
          _InstructionPanel(navState: navState),

          // ─── Map ─────────────────────────────────────────────────────
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: initialCenter,
                initialZoom: 16,
                minZoom: 10,
                maxZoom: 20,
              ),
              children: [
                // Goong tile layer
                TileLayer(
                  urlTemplate: AppConstants.goongTileUrl,
                  userAgentPackageName: 'com.safewalk.hanoi',
                  // Fallback: nếu Goong tiles không load, dùng OSM
                  fallbackUrl:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                ),

                // Route polyline
                if (routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: routePoints,
                        color: AppTheme.safe,
                        strokeWidth: 5,
                      ),
                    ],
                  ),

                // Markers (current position + destination)
                if (markers.isNotEmpty)
                  MarkerLayer(markers: markers),
              ],
            ),
          ),

          // ─── Next step + Stop button ─────────────────────────────────
          _BottomPanel(
            navState: navState,
            onStop: _stopNavigation,
          ),
        ],
      ),
    );
  }
}

// ─── Instruction Panel ────────────────────────────────────────────────

class _InstructionPanel extends StatelessWidget {
  final NavigationState navState;

  const _InstructionPanel({required this.navState});

  IconData _getManeuverIcon(String? maneuver) {
    return switch (maneuver) {
      'turn-left' || 'turn-slight-left' || 'turn-sharp-left' => Icons.turn_left,
      'turn-right' || 'turn-slight-right' || 'turn-sharp-right' =>
        Icons.turn_right,
      'uturn-left' || 'uturn-right' => Icons.u_turn_left,
      'roundabout-left' || 'roundabout-right' => Icons.roundabout_left,
      _ => Icons.straight,
    };
  }

  @override
  Widget build(BuildContext context) {
    final step = navState.currentStep;
    final distM = navState.distanceToNextStepM;

    if (navState.status == NavigationStatus.arrived) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        color: AppTheme.safe,
        child: const Column(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 40),
            SizedBox(height: 8),
            Text(
              'Bạn đã đến nơi!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (navState.status == NavigationStatus.searching) {
      return Container(
        padding: const EdgeInsets.all(20),
        color: AppTheme.warningMedium,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 3),
            ),
            SizedBox(width: 16),
            Text(
              'Đang tìm đường...',
              style: TextStyle(color: Colors.white, fontSize: 22),
            ),
          ],
        ),
      );
    }

    if (step == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        color: AppTheme.surface,
        child: const Text(
          'Đang xác định vị trí...',
          style: TextStyle(color: Colors.white70, fontSize: 20),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: AppTheme.surface,
      child: Row(
        children: [
          Icon(
            _getManeuverIcon(step.maneuver),
            color: Colors.white,
            size: 48,
            semanticLabel: step.instructionText,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.instructionText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (distM != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    distM >= 1000
                        ? '${(distM / 1000).toStringAsFixed(1)} km'
                        : '${distM.round()} m',
                    style: const TextStyle(
                      color: AppTheme.safe,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom Panel ─────────────────────────────────────────────────────

class _BottomPanel extends StatelessWidget {
  final NavigationState navState;
  final VoidCallback onStop;

  const _BottomPanel({required this.navState, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final route = navState.route;
    final nextStepIndex = navState.currentStepIndex + 1;
    final hasNextStep =
        route != null && nextStepIndex < route.steps.length;

    return Container(
      padding: const EdgeInsets.all(16),
      color: AppTheme.primaryDark,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Next step preview
            if (hasNextStep)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.navigate_next,
                        color: Colors.white70, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Tiếp theo: ',
                      style:
                          TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                    Expanded(
                      child: Text(
                        route.steps[nextStepIndex].instructionText,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            // Stop navigation button
            Semantics(
              button: true,
              label: 'Dừng chỉ đường',
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onStop,
                  icon: const Icon(Icons.stop, size: 28),
                  label: const Text(
                    'Dừng chỉ đường',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
