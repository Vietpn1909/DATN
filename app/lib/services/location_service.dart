import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:safewalk_hanoi/models/navigation_step.dart';

/// GPS location service dùng geolocator.
class LocationService {
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;

  Position? get lastPosition => _lastPosition;

  LatLng? get currentLatLng => _lastPosition != null
      ? LatLng(_lastPosition!.latitude, _lastPosition!.longitude)
      : null;

  /// Callback khi vị trí thay đổi
  void Function(LatLng position)? onLocationUpdate;

  /// Kiểm tra và xin permission GPS
  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[Location] GPS service disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('[Location] Permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('[Location] Permission denied forever');
      return false;
    }

    return true;
  }

  /// Lấy vị trí hiện tại một lần
  Future<LatLng?> getCurrentPosition() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      _lastPosition = pos;
      return LatLng(pos.latitude, pos.longitude);
    } catch (e) {
      debugPrint('[Location] Error getting position: $e');
      return null;
    }
  }

  /// Bắt đầu stream vị trí (dùng khi navigation active)
  Future<void> startTracking() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return;

    _positionSubscription?.cancel();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Cập nhật mỗi khi di chuyển >= 5m
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        _lastPosition = position;
        onLocationUpdate?.call(LatLng(position.latitude, position.longitude));
      },
      onError: (e) {
        debugPrint('[Location] Stream error: $e');
      },
    );

    debugPrint('[Location] Tracking started');
  }

  /// Dừng tracking
  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    debugPrint('[Location] Tracking stopped');
  }

  void dispose() {
    stopTracking();
  }
}
