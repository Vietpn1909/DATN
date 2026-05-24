import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safewalk_hanoi/core/constants/app_constants.dart';
import 'package:safewalk_hanoi/models/navigation_step.dart';
import 'package:safewalk_hanoi/services/location_service.dart';
import 'package:safewalk_hanoi/services/navigation_service.dart';
import 'package:safewalk_hanoi/services/tts_service.dart';
import 'package:safewalk_hanoi/providers/providers.dart';

// ─── Service providers ────────────────────────────────────────────────

final locationServiceProvider = Provider<LocationService>((ref) {
  final service = LocationService();
  ref.onDispose(() => service.dispose());
  return service;
});

final navigationServiceProvider = Provider<NavigationService>((ref) {
  // Đọc API key từ AppConstants
  // → Paste key vào app_constants.dart: AppConstants.goongApiKey
  return NavigationService(apiKey: AppConstants.goongApiKey);
});

// ─── Navigation state notifier ────────────────────────────────────────

class NavigationNotifier extends StateNotifier<NavigationState> {
  final NavigationService _navService;
  final LocationService _locationService;
  final TtsService _tts;

  /// Khoảng cách tối thiểu để coi là đã đến waypoint tiếp theo (mét)
  static const double _stepAdvanceDistanceM = 20.0;

  /// Khoảng cách tối thiểu để coi là đã đến đích (mét)
  static const double _arrivalDistanceM = 30.0;

  NavigationNotifier({
    required NavigationService navService,
    required LocationService locationService,
    required TtsService tts,
  })  : _navService = navService,
        _locationService = locationService,
        _tts = tts,
        super(NavigationState.initial);

  // ─── Public API ─────────────────────────────────────────────────────

  /// Bắt đầu tìm đường từ giọng nói
  Future<void> startNavigation(String destinationQuery) async {
    state = state.copyWith(status: NavigationStatus.searching);
    await _tts.speak('Đang tìm đường đến $destinationQuery...', type: TtsMessageType.navigation);

    // Lấy vị trí hiện tại
    final currentPos = await _locationService.getCurrentPosition();
    if (currentPos == null) {
      state = state.copyWith(
        status: NavigationStatus.error,
        errorMessage: 'Không lấy được vị trí GPS. Vui lòng bật GPS.',
      );
      await _tts.speak('Không lấy được vị trí GPS. Vui lòng bật GPS và thử lại.', type: TtsMessageType.navigation);
      return;
    }

    // Tìm đường
    final route = await _navService.searchAndRoute(destinationQuery, currentPos);
    if (route == null) {
      state = state.copyWith(
        status: NavigationStatus.error,
        errorMessage: 'Không tìm thấy đường đến $destinationQuery.',
      );
      await _tts.speak('Không tìm thấy đường đến $destinationQuery. Vui lòng thử lại.', type: TtsMessageType.navigation);
      return;
    }

    // Bắt đầu navigate
    state = NavigationState(
      status: NavigationStatus.navigating,
      route: route,
      currentStepIndex: 0,
      currentPosition: currentPos,
    );

    // Thông báo tổng quan
    await _tts.speak(
      'Tìm thấy đường đến ${route.destinationName}. '
      'Khoảng cách ${route.totalDistanceText}, '
      'thời gian đi bộ khoảng ${route.totalDurationText}. '
      'Bắt đầu chỉ đường.',
      type: TtsMessageType.navigation,
    );

    // Thông báo bước đầu tiên
    await Future.delayed(const Duration(seconds: 2));
    if (state.isNavigating && route.steps.isNotEmpty) {
      await _tts.speak(route.steps[0].toSpeechText(), type: TtsMessageType.navigation);
    }

    // Bắt đầu GPS tracking
    _locationService.onLocationUpdate = _onLocationUpdate;
    await _locationService.startTracking();
  }

  /// Dừng navigation
  Future<void> stopNavigation() async {
    _locationService.stopTracking();
    _locationService.onLocationUpdate = null;
    state = NavigationState.initial;
    await _tts.speak('Đã dừng chỉ đường.', type: TtsMessageType.navigation);
    debugPrint('[Nav] Navigation stopped');
  }

  /// Lấy trạng thái hiện tại cho UI (không làm thay đổi state)
  NavigationState get currentState => state;

  // ─── Internal ────────────────────────────────────────────────────────

  void _onLocationUpdate(LatLng position) {
    if (!state.isNavigating || state.route == null) return;

    final route = state.route!;
    final currentStep = state.currentStep;
    if (currentStep == null) return;

    // Khoảng cách đến điểm cuối bước hiện tại
    final distToStep = NavigationService.haversineDistance(position, currentStep.endLocation);

    // Khoảng cách đến đích
    final lastStep = route.steps.last;
    final distToDest = NavigationService.haversineDistance(position, lastStep.endLocation);

    debugPrint('[Nav] Pos=$position, distToStep=${distToStep.round()}m, distToDest=${distToDest.round()}m');

    // Kiểm tra đã đến đích chưa
    if (distToDest < _arrivalDistanceM) {
      _onArrived();
      return;
    }

    // Kiểm tra qua waypoint tiếp theo chưa
    if (distToStep < _stepAdvanceDistanceM) {
      _advanceStep(position);
      return;
    }

    // Cập nhật khoảng cách
    state = state.copyWith(
      currentPosition: position,
      distanceToNextStepM: distToStep,
    );
  }

  void _advanceStep(LatLng position) {
    final route = state.route!;
    final nextIndex = state.currentStepIndex + 1;

    if (nextIndex >= route.steps.length) {
      _onArrived();
      return;
    }

    state = state.copyWith(
      currentStepIndex: nextIndex,
      currentPosition: position,
    );

    final nextStep = route.steps[nextIndex];
    debugPrint('[Nav] Step $nextIndex: ${nextStep.instructionText}');
    _tts.speak(nextStep.toSpeechText(), type: TtsMessageType.navigation);
  }

  void _onArrived() {
    _locationService.stopTracking();
    _locationService.onLocationUpdate = null;

    final destName = state.route?.destinationName ?? 'điểm đến';
    state = state.copyWith(status: NavigationStatus.arrived);
    _tts.speak('Bạn đã đến $destName!', type: TtsMessageType.navigation);
    debugPrint('[Nav] Arrived at $destName');
  }
}

// ─── Provider ─────────────────────────────────────────────────────────

final navigationProvider =
    StateNotifierProvider<NavigationNotifier, NavigationState>((ref) {
  return NavigationNotifier(
    navService: ref.watch(navigationServiceProvider),
    locationService: ref.watch(locationServiceProvider),
    tts: ref.watch(ttsServiceProvider),
  );
});
