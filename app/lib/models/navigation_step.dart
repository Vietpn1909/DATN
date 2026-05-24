/// Models cho navigation Phase 2

class LatLng {
  final double lat;
  final double lng;

  const LatLng(this.lat, this.lng);

  @override
  String toString() => '($lat, $lng)';
}

/// Một bước chỉ đường
class NavigationStep {
  final String instructionText;   // Tiếng Việt, đã strip HTML
  final String instructionHtml;   // Raw HTML từ Directions API
  final double distanceM;         // Khoảng cách bước này (mét)
  final int durationSec;          // Thời gian dự kiến (giây)
  final LatLng endLocation;       // Điểm cuối bước này
  final String? maneuver;         // turn-left, turn-right, straight...

  const NavigationStep({
    required this.instructionText,
    required this.instructionHtml,
    required this.distanceM,
    required this.durationSec,
    required this.endLocation,
    this.maneuver,
  });

  /// Tạo câu thông báo tiếng Việt đầy đủ
  String toSpeechText() {
    final dist = distanceM >= 1000
        ? '${(distanceM / 1000).toStringAsFixed(1)} ki lô mét'
        : '${distanceM.round()} mét';
    return '$instructionText, sau $dist';
  }
}

/// Thông tin tổng thể tuyến đường
class RouteInfo {
  final String destinationName;
  final double totalDistanceM;
  final int totalDurationSec;
  final List<NavigationStep> steps;
  final List<LatLng> polylinePoints;

  const RouteInfo({
    required this.destinationName,
    required this.totalDistanceM,
    required this.totalDurationSec,
    required this.steps,
    required this.polylinePoints,
  });

  String get totalDistanceText {
    if (totalDistanceM >= 1000) {
      return '${(totalDistanceM / 1000).toStringAsFixed(1)} km';
    }
    return '${totalDistanceM.round()} m';
  }

  String get totalDurationText {
    final mins = (totalDurationSec / 60).ceil();
    if (mins >= 60) {
      final h = mins ~/ 60;
      final m = mins % 60;
      return m > 0 ? '$h giờ $m phút' : '$h giờ';
    }
    return '$mins phút';
  }
}

/// Trạng thái navigation
enum NavigationStatus {
  idle,
  searching,    // Đang tìm đường
  navigating,   // Đang chỉ đường
  arrived,      // Đã đến nơi
  error,        // Lỗi (không tìm thấy đường, mất GPS...)
}

/// State của navigation
class NavigationState {
  final NavigationStatus status;
  final RouteInfo? route;
  final int currentStepIndex;
  final LatLng? currentPosition;
  final double? distanceToNextStepM;
  final String? errorMessage;

  const NavigationState({
    required this.status,
    this.route,
    this.currentStepIndex = 0,
    this.currentPosition,
    this.distanceToNextStepM,
    this.errorMessage,
  });

  static const initial = NavigationState(status: NavigationStatus.idle);

  NavigationStep? get currentStep =>
      route != null && currentStepIndex < route!.steps.length
          ? route!.steps[currentStepIndex]
          : null;

  bool get isNavigating => status == NavigationStatus.navigating;

  NavigationState copyWith({
    NavigationStatus? status,
    RouteInfo? route,
    int? currentStepIndex,
    LatLng? currentPosition,
    double? distanceToNextStepM,
    String? errorMessage,
  }) {
    return NavigationState(
      status: status ?? this.status,
      route: route ?? this.route,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      currentPosition: currentPosition ?? this.currentPosition,
      distanceToNextStepM: distanceToNextStepM ?? this.distanceToNextStepM,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
