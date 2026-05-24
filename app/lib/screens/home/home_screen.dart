import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safewalk_hanoi/core/constants/app_constants.dart';
import 'package:safewalk_hanoi/core/theme/app_theme.dart';
import 'package:safewalk_hanoi/models/detection.dart';
import 'package:safewalk_hanoi/services/danger_zone_service.dart';
import 'package:safewalk_hanoi/providers/providers.dart';
import 'package:safewalk_hanoi/providers/navigation_provider.dart';
import 'package:safewalk_hanoi/services/warning_service.dart';

import 'package:safewalk_hanoi/screens/home/widgets/navigation_panel.dart';
import 'package:safewalk_hanoi/screens/home/widgets/status_bar.dart';
import 'package:safewalk_hanoi/screens/home/widgets/voice_button.dart';
import 'package:safewalk_hanoi/screens/navigation/navigation_screen.dart';

/// Màn hình chính của SafeWalk Hanoi.
///
/// Layout:
/// ┌─────────────────┐
/// │                  │
/// │  Camera Preview  │  (chiếm phần lớn màn hình)
/// │  + Detection     │
/// │    Overlay       │
/// │                  │
/// ├─────────────────┤
/// │  Status Bar      │  (cảnh báo + trạng thái)
/// ├─────────────────┤
/// │  [Mic]  [Start]  │  (nút điều khiển lớn)
/// └─────────────────┘
///
/// Gesture:
/// - Tap: nghe trạng thái
/// - Double tap: voice input
/// - Swipe up: bật detection
/// - Swipe down: tắt detection
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  List<DetectionResult> _detections = [];
  DetectionResult? _priority;
  String? _currentWarning;
  double _fps = 0;
  int _frameCount = 0;
  DateTime _lastFpsUpdate = DateTime.now();

  // ═══════════════════════════════════════════════════════════════════
  // Bottleneck 6: Throttle UI updates — max 10 FPS rebuild
  // Mắt người không phân biệt được obstacle labels update nhanh hơn.
  // ═══════════════════════════════════════════════════════════════════
  DateTime _lastUiUpdate = DateTime.now();
  static const int _uiUpdateIntervalMs = 100; // 10 FPS UI max

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      // Khởi tạo TTS
      final tts = ref.read(ttsServiceProvider);
      await tts.initialize();

      // Khởi tạo Camera
      final camera = ref.read(cameraServiceProvider);
      await camera.initialize();

      // Khởi tạo TFLite
      final tflite = ref.read(tfliteServiceProvider);
      await tflite.initialize();

      // Setup inference callback
      tflite.onResult = _onInferenceResult;

      // Setup camera -> inference pipeline
      camera.onFrameAvailable = (CameraImage image) {
        tflite.processFrame(image);
      };

      if (mounted) {
        setState(() {});
        // Tự động bật phát hiện vật cản ngay khi mở app
        _toggleDetection();
        // Chào mừng
        await tts.speak('Chào mừng bạn đến SafeWalk Hà Nội. Hệ thống phát hiện vật cản đã tự động kích hoạt.');
      }
    } catch (e) {
      debugPrint('Lỗi khởi tạo: $e');
      final tts = ref.read(ttsServiceProvider);
      await tts.speak('Lỗi khởi tạo ứng dụng. Vui lòng thử lại.');
    }
  }

  /// Callback khi inference hoàn thành
  ///
  /// ═══════════════════════════════════════════════════════════════════
  /// Bottleneck 6: Ba cải tiến quan trọng:
  /// 1. frameProcessed() gọi NGAY ĐẦU → unblock camera pipeline
  ///    (trước đây gọi cuối, sau setState → pipeline bị block ~16-33ms)
  /// 2. Warning processing tách riêng, không phụ thuộc UI
  /// 3. setState throttled → max 10 FPS rebuild UI
  /// ═══════════════════════════════════════════════════════════════════
  void _onInferenceResult(FrameResult result) {
    if (!mounted) return;

    // ★ QUAN TRỌNG: Đánh dấu frame đã xử lý NGAY LẬP TỨC
    // → camera có thể gửi frame tiếp trong khi ta xử lý warning + UI
    ref.read(cameraServiceProvider).frameProcessed();

    // Cập nhật FPS
    _frameCount++;
    final now = DateTime.now();
    final elapsed = now.difference(_lastFpsUpdate).inMilliseconds;
    if (elapsed > 1000) {
      _fps = _frameCount * 1000.0 / elapsed;
      _frameCount = 0;
      _lastFpsUpdate = now;
    }

    // Xử lý warning trực tiếp từ raw detections (bỏ qua temporal filter để phản ứng nhanh nhất)
    final warningService = ref.read(warningServiceProvider);
    final warningResult = warningService.getNextWarning(
      result,
      dangerZone: null,
    );

    if (warningResult != null) {
      final tts = ref.read(ttsServiceProvider);
      // Phát cảnh báo với mức ưu tiên phù hợp:
      // - urgentWarning (ô tô, xe máy, xe buýt): ngắt navigation ngay
      // - warning (người đi bộ, xe đạp): ngắt navigation ngay
      // - lowWarning (vạch kẻ, đèn, biển...): chỉ phát khi TTS rảnh
      tts.speak(warningResult.text, type: warningResult.type);
    }

    // Throttle UI updates: chỉ rebuild mỗi 100ms (10 FPS)
    final uiElapsed = now.difference(_lastUiUpdate).inMilliseconds;
    if (uiElapsed >= _uiUpdateIntervalMs) {
      _lastUiUpdate = now;
      setState(() {
        _detections = result.detections;
        _priority = result.priorityDetection;
        _currentWarning = warningResult?.text ?? _currentWarning;
      });
    } else {
      // Vẫn cập nhật state nội bộ (cho warning logic) nhưng không rebuild
      _detections = result.detections;
      _priority = result.priorityDetection;
      if (warningResult != null) _currentWarning = warningResult.text;
    }
  }

  /// Bật/tắt detection
  void _toggleDetection() {
    final camera = ref.read(cameraServiceProvider);
    final tts = ref.read(ttsServiceProvider);
    final mode = ref.read(appModeProvider);

    if (mode == AppMode.detecting) {
      camera.stopImageStream();
      ref.read(appModeProvider.notifier).state = AppMode.idle;
      ref.read(warningServiceProvider).reset();
      ref.read(dangerZoneServiceProvider).reset();
      tts.speak('Đã tắt phát hiện vật cản');
      setState(() {
        _detections = [];
        _priority = null;
        _currentWarning = null;
      });
    } else {
      camera.startImageStream();
      ref.read(appModeProvider.notifier).state = AppMode.detecting;
      tts.speak('Đang bật phát hiện vật cản');
      HapticFeedback.mediumImpact();
    }
  }

  /// Xử lý voice input → bắt đầu navigation
  void _toggleVoiceInput() async {
    final stt = ref.read(sttServiceProvider);
    final tts = ref.read(ttsServiceProvider);
    final navState = ref.read(navigationProvider);

    // Nếu đang navigate → đọc lại bước chỉ đường hiện tại bằng TTS
    if (navState.isNavigating) {
      _speakCurrentNavigationStep();
      return;
    }

    // Nếu đang nghe → dừng
    if (stt.isListening) {
      await stt.stopListening();
      return;
    }

    // Bắt đầu nghe địa chỉ
    final available = await stt.initialize();
    if (!available) {
      tts.speak('Không thể sử dụng giọng nói. Vui lòng kiểm tra quyền microphone.');
      return;
    }

    tts.speak('Hãy nói địa chỉ bạn muốn đến');
    await Future.delayed(const Duration(milliseconds: 1500));

    stt.onResult = (text, isFinal) async {
      if (isFinal && text.isNotEmpty) {
        ref.read(sttTextProvider.notifier).state = text;
        await stt.stopListening();
        // Bắt đầu tìm đường (navigation chạy nền bằng TTS + GPS)
        await ref.read(navigationProvider.notifier).startNavigation(text);
        // KHÔNG push NavigationScreen → detection tiếp tục chạy song song
        // NavigationPanel trên HomeScreen sẽ hiển thị bước hiện tại
        // Người dùng có thể tap vào panel để xem bản đồ
      }
    };

    await stt.startListening();
  }

  /// Đọc lại bước chỉ đường hiện tại bằng TTS
  /// (khi người dùng nhấn mic trong lúc đang navigate)
  void _speakCurrentNavigationStep() {
    final navState = ref.read(navigationProvider);
    final tts = ref.read(ttsServiceProvider);
    final step = navState.currentStep;
    if (step != null) {
      final distM = navState.distanceToNextStepM;
      String message = step.instructionText;
      if (distM != null) {
        final distText = distM >= 1000
            ? '${(distM / 1000).toStringAsFixed(1)} ki lô mét'
            : '${distM.round()} mét';
        message += ', còn $distText';
      }
      tts.speak(message);
    } else {
      tts.speak('Đang xác định vị trí, vui lòng chờ');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Tắt camera khi app vào background để tiết kiệm pin
    if (state == AppLifecycleState.paused) {
      ref.read(cameraServiceProvider).stopImageStream();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = ref.watch(cameraServiceProvider);
    final mode = ref.watch(appModeProvider);
    final isDetecting = mode == AppMode.detecting;
    final stt = ref.watch(sttServiceProvider);

    return Scaffold(
      backgroundColor: AppTheme.primaryDark,
      body: GestureDetector(
        // Swipe up: bật detection
        // Swipe down: tắt detection
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! < -200) {
            // Swipe up
            if (!isDetecting) _toggleDetection();
          } else if (details.primaryVelocity! > 200) {
            // Swipe down
            if (isDetecting) _toggleDetection();
          }
        },
        child: Column(
          children: [
            // Camera preview + overlay
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Camera preview
                  if (camera.isInitialized)
                    CameraPreview(camera.controller!)
                  else
                    const Center(
                      child: Text(
                        'Đang khởi tạo camera...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Navigation panel (chỉ hiện khi đang navigate)
            const NavigationPanel(),

            // Status bar
            StatusBar(
              isDetecting: isDetecting,
              priorityDetection: _priority,
              fps: _fps,
              currentWarning: _currentWarning,
            ),

            // Control buttons
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              color: AppTheme.primaryDark,
              child: SafeArea(
                top: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Nút voice input
                    VoiceButton(
                      isListening: stt.isListening,
                      onTap: _toggleVoiceInput,
                    ),

                    // Nút bật/tắt detection
                    Semantics(
                      button: true,
                      label: isDetecting
                          ? 'Đang phát hiện, chạm để tắt'
                          : 'Chạm để bật phát hiện vật cản',
                      child: GestureDetector(
                        onTap: _toggleDetection,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDetecting ? AppTheme.danger : AppTheme.safe,
                            boxShadow: [
                              BoxShadow(
                                color: (isDetecting ? AppTheme.danger : AppTheme.safe)
                                    .withOpacity(0.4),
                                blurRadius: 20,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(
                            isDetecting ? Icons.stop : Icons.play_arrow,
                            color: Colors.white,
                            size: 50,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
