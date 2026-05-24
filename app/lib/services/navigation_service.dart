import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:safewalk_hanoi/models/navigation_step.dart';

/// Goong Maps API integration + route management.
///
/// Thay thế Google Maps API bằng Goong API (dịch vụ bản đồ Việt Nam).
/// Goong API docs: https://docs.goong.io/rest/
///
/// Sử dụng:
/// - Goong Place AutoComplete + Place Detail (tìm địa chỉ từ giọng nói)
/// - Goong Forward Geocoding (địa chỉ đầy đủ → tọa độ)
/// - Goong Direction API (tìm đường)
///
/// Lưu ý: Goong không có mode "walking", dùng "bike" thay thế
/// vì tuyến xe đạp gần giống đi bộ nhất (đường nhỏ, vỉa hè).
class NavigationService {
  final Dio _dio;
  final String apiKey;

  static const String _baseUrl = 'https://rsapi.goong.io';

  NavigationService({required this.apiKey})
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ));

  // ─── Maneuver → Tiếng Việt ───────────────────────────────────────────

  static const Map<String, String> _maneuverVi = {
    'turn-left': 'Rẽ trái',
    'turn-right': 'Rẽ phải',
    'turn-slight-left': 'Rẽ nhẹ sang trái',
    'turn-slight-right': 'Rẽ nhẹ sang phải',
    'turn-sharp-left': 'Rẽ gắt sang trái',
    'turn-sharp-right': 'Rẽ gắt sang phải',
    'straight': 'Đi thẳng',
    'roundabout-left': 'Vào bùng binh, rẽ trái',
    'roundabout-right': 'Vào bùng binh, rẽ phải',
    'uturn-left': 'Quay đầu',
    'uturn-right': 'Quay đầu',
    'merge': 'Nhập vào làn đường',
    'ramp-left': 'Ra đường dốc bên trái',
    'ramp-right': 'Ra đường dốc bên phải',
    'fork-left': 'Đi nhánh bên trái',
    'fork-right': 'Đi nhánh bên phải',
  };

  // ─── Place AutoComplete (tìm địa chỉ từ text input) ─────────────────

  /// Tìm kiếm địa chỉ bằng Goong Place AutoComplete.
  /// Trả về place_id của kết quả tốt nhất.
  /// Ưu tiên kết quả gần vị trí hiện tại nếu có.
  Future<String?> _placeAutoComplete(String query, {LatLng? nearLocation}) async {
    debugPrint('[Nav] Place AutoComplete: $query');

    try {
      final params = <String, dynamic>{
        'input': query,
        'api_key': apiKey,
      };

      // Thêm vị trí để ưu tiên kết quả gần đó
      if (nearLocation != null) {
        params['location'] = '${nearLocation.lat},${nearLocation.lng}';
      }

      final response = await _dio.get(
        '$_baseUrl/Place/AutoComplete',
        queryParameters: params,
      );

      final data = response.data as Map<String, dynamic>;
      if (data['status'] != 'OK') {
        debugPrint('[Nav] AutoComplete error: ${data['status']}');
        return null;
      }

      final predictions = data['predictions'] as List?;
      if (predictions == null || predictions.isEmpty) {
        debugPrint('[Nav] AutoComplete: no predictions');
        return null;
      }

      final placeId = predictions[0]['place_id'] as String?;
      final description = predictions[0]['description'] as String?;
      debugPrint('[Nav] AutoComplete best: $description (id=$placeId)');
      return placeId;
    } catch (e) {
      debugPrint('[Nav] AutoComplete exception: $e');
      return null;
    }
  }

  /// Lấy tọa độ từ place_id qua Goong Place Detail
  Future<LatLng?> _getPlaceDetail(String placeId) async {
    debugPrint('[Nav] Place Detail: $placeId');

    try {
      final response = await _dio.get(
        '$_baseUrl/Place/Detail',
        queryParameters: {
          'place_id': placeId,
          'api_key': apiKey,
        },
      );

      final data = response.data as Map<String, dynamic>;
      if (data['status'] != 'OK') {
        debugPrint('[Nav] PlaceDetail error: ${data['status']}');
        return null;
      }

      final result = data['result'] as Map<String, dynamic>?;
      if (result == null) return null;

      final location = result['geometry']?['location'];
      if (location == null) return null;

      final latLng = LatLng(
        (location['lat'] as num).toDouble(),
        (location['lng'] as num).toDouble(),
      );
      debugPrint('[Nav] PlaceDetail location: $latLng');
      return latLng;
    } catch (e) {
      debugPrint('[Nav] PlaceDetail exception: $e');
      return null;
    }
  }

  // ─── Geocoding (fallback) ────────────────────────────────────────────

  /// Forward Geocoding: địa chỉ text → tọa độ (fallback khi AutoComplete thất bại)
  Future<LatLng?> geocode(String query) async {
    final q = '$query, Hà Nội';
    debugPrint('[Nav] Geocoding: $q');

    try {
      final response = await _dio.get(
        '$_baseUrl/geocode',
        queryParameters: {
          'address': q,
          'api_key': apiKey,
        },
      );

      final data = response.data as Map<String, dynamic>;
      if (data['status'] != 'OK') {
        debugPrint('[Nav] Geocode error: ${data['status']}');
        return null;
      }

      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final location = results[0]['geometry']['location'];
      final latLng = LatLng(
        (location['lat'] as num).toDouble(),
        (location['lng'] as num).toDouble(),
      );
      debugPrint('[Nav] Geocoded to: $latLng');
      return latLng;
    } catch (e) {
      debugPrint('[Nav] Geocode exception: $e');
      return null;
    }
  }

  // ─── Directions ──────────────────────────────────────────────────────

  /// Lấy tuyến đường từ origin đến destination.
  /// Goong không có mode walking → dùng vehicle=bike (gần nhất với đi bộ).
  Future<RouteInfo?> getWalkingRoute({
    required LatLng origin,
    required LatLng destination,
    required String destinationName,
  }) async {
    debugPrint('[Nav] Getting route: $origin -> $destination');

    try {
      final response = await _dio.get(
        '$_baseUrl/Direction',
        queryParameters: {
          'origin': '${origin.lat},${origin.lng}',
          'destination': '${destination.lat},${destination.lng}',
          'vehicle': 'bike', // Goong không có walking, bike gần nhất
          'api_key': apiKey,
        },
      );

      final data = response.data as Map<String, dynamic>;

      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        debugPrint('[Nav] Directions: no routes found');
        return null;
      }

      final route = routes[0];
      final legs = route['legs'] as List?;
      if (legs == null || legs.isEmpty) {
        debugPrint('[Nav] Directions: no legs');
        return null;
      }

      final leg = legs[0];

      // Parse steps
      final stepsRaw = leg['steps'] as List? ?? [];
      final steps = stepsRaw.map((s) => _parseStep(s)).toList();

      // Decode polyline
      final overviewPolyline = route['overview_polyline'];
      final polylineStr = overviewPolyline?['points'] as String? ?? '';
      final polyline = polylineStr.isNotEmpty
          ? _decodePolyline(polylineStr)
          : <LatLng>[];

      final routeInfo = RouteInfo(
        destinationName: destinationName,
        totalDistanceM: (leg['distance']?['value'] as num?)?.toDouble() ?? 0.0,
        totalDurationSec: (leg['duration']?['value'] as num?)?.toInt() ?? 0,
        steps: steps,
        polylinePoints: polyline,
      );

      debugPrint('[Nav] Route: ${steps.length} steps, ${routeInfo.totalDistanceText}');
      return routeInfo;
    } catch (e) {
      debugPrint('[Nav] Directions exception: $e');
      return null;
    }
  }

  /// Tìm đường từ text query.
  /// Ưu tiên: AutoComplete + PlaceDetail → fallback Geocoding → Directions
  Future<RouteInfo?> searchAndRoute(String query, LatLng origin) async {
    LatLng? destination;

    // 1. Thử AutoComplete + PlaceDetail (tốt hơn cho input tiếng Việt từ giọng nói)
    final placeId = await _placeAutoComplete(query, nearLocation: origin);
    if (placeId != null) {
      destination = await _getPlaceDetail(placeId);
    }

    // 2. Fallback: Forward Geocoding
    if (destination == null) {
      debugPrint('[Nav] AutoComplete failed, trying geocode...');
      destination = await geocode(query);
    }

    if (destination == null) return null;

    return getWalkingRoute(
      origin: origin,
      destination: destination,
      destinationName: query,
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────

  NavigationStep _parseStep(Map<String, dynamic> s) {
    final htmlInstruction = s['html_instructions'] as String? ?? '';
    final cleanText = _stripHtml(htmlInstruction);
    final maneuver = s['maneuver'] as String?;
    final maneuverVi = _maneuverVi[maneuver] ?? cleanText;

    final endLoc = s['end_location'] ?? {};

    return NavigationStep(
      instructionText: maneuverVi.isNotEmpty ? maneuverVi : cleanText,
      instructionHtml: htmlInstruction,
      distanceM: (s['distance']?['value'] as num?)?.toDouble() ?? 0.0,
      durationSec: (s['duration']?['value'] as num?)?.toInt() ?? 0,
      endLocation: LatLng(
        (endLoc['lat'] as num?)?.toDouble() ?? 0.0,
        (endLoc['lng'] as num?)?.toDouble() ?? 0.0,
      ),
      maneuver: maneuver,
    );
  }

  /// Strip HTML tags
  String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ─── Haversine distance ───────────────────────────────────────────────

  /// Khoảng cách Haversine giữa 2 điểm GPS (mét)
  static double haversineDistance(LatLng a, LatLng b) {
    const r = 6371000.0; // Earth radius in meters
    final lat1 = a.lat * pi / 180;
    final lat2 = b.lat * pi / 180;
    final dLat = (b.lat - a.lat) * pi / 180;
    final dLng = (b.lng - a.lng) * pi / 180;

    final x = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(x), sqrt(1 - x));
    return r * c;
  }

  // ─── Polyline decoder ────────────────────────────────────────────────

  /// Decode Google/Goong encoded polyline → List<LatLng>
  /// Goong dùng cùng format encoded polyline với Google Maps.
  List<LatLng> _decodePolyline(String encoded) {
    final result = <LatLng>[];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result0 = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result0 |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLat = (result0 & 1) != 0 ? ~(result0 >> 1) : (result0 >> 1);
      lat += dLat;

      shift = 0;
      result0 = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result0 |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLng = (result0 & 1) != 0 ? ~(result0 >> 1) : (result0 >> 1);
      lng += dLng;

      result.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return result;
  }
}
