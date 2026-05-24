import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safewalk_hanoi/models/detection.dart';
import 'package:safewalk_hanoi/services/camera_service.dart';
import 'package:safewalk_hanoi/services/tflite_service.dart';
import 'package:safewalk_hanoi/services/mock_tflite_service.dart';
import 'package:safewalk_hanoi/services/tts_service.dart';
import 'package:safewalk_hanoi/services/stt_service.dart';
import 'package:safewalk_hanoi/services/warning_service.dart';
import 'package:safewalk_hanoi/services/danger_zone_service.dart';
import 'package:safewalk_hanoi/core/config/app_config.dart';
import 'package:safewalk_hanoi/core/constants/app_constants.dart';

// ============================================================
// App State
// ============================================================

enum AppMode { idle, detecting, navigating }

final appModeProvider = StateProvider<AppMode>((ref) => AppMode.idle);

// ============================================================
// Services (singleton)
// ============================================================

final cameraServiceProvider = Provider<CameraService>((ref) {
  final service = CameraService();
  ref.onDispose(() => service.dispose());
  return service;
});

final tfliteServiceProvider = Provider<dynamic>((ref) {
  // Use MockTFLiteService if configured for testing UI flow
  if (AppConfig.useMockServices) {
    final service = MockTFLiteService();
    ref.onDispose(() => service.dispose());
    return service;
  } else {
    final service = TfliteService();
    ref.onDispose(() => service.dispose());
    return service;
  }
});

final ttsServiceProvider = Provider<TtsService>((ref) {
  final service = TtsService();
  ref.onDispose(() => service.dispose());
  return service;
});

final sttServiceProvider = Provider<SttService>((ref) {
  final service = SttService();
  ref.onDispose(() => service.dispose());
  return service;
});

final warningServiceProvider = Provider<WarningService>((ref) {
  return WarningService();
});

final dangerZoneServiceProvider = Provider<DangerZoneService>((ref) {
  final service = DangerZoneService(imageSize: AppConstants.modelInputSize);
  return service;
});

// ============================================================
// Detection Stream
// ============================================================

/// Stream kết quả detection real-time
final detectionStreamProvider = StreamProvider<FrameResult>((ref) {
  final controller = StreamController<FrameResult>();
  final tfliteService = ref.watch(tfliteServiceProvider);

  tfliteService.onResult = (result) {
    if (!controller.isClosed) {
      controller.add(result);
    }
  };

  ref.onDispose(() => controller.close());
  return controller.stream;
});

// ============================================================
// Status
// ============================================================

/// Trạng thái khởi tạo app
final initializationProvider = FutureProvider<bool>((ref) async {
  final tts = ref.read(ttsServiceProvider);
  await tts.initialize();

  final camera = ref.read(cameraServiceProvider);
  await camera.initialize();

  final tflite = ref.read(tfliteServiceProvider);
  await tflite.initialize();

  return true;
});

/// Số FPS inference hiện tại
final fpsProvider = StateProvider<double>((ref) => 0.0);

/// Text đang được nói
final currentSpeechProvider = StateProvider<String>((ref) => '');

/// Text từ STT
final sttTextProvider = StateProvider<String>((ref) => '');
