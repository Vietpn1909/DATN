import 'package:flutter/material.dart';
import 'package:safewalk_hanoi/models/detection.dart';
import 'package:safewalk_hanoi/services/mock_tflite_service.dart';
import 'package:safewalk_hanoi/services/warning_service.dart';
import 'package:safewalk_hanoi/services/tts_service.dart';

/// Test screen để verify UI flow với mock detections
/// Chạy trên máy tính mà không cần Android device hoặc emulator
class UIFlowTestScreen extends StatefulWidget {
  const UIFlowTestScreen({super.key});

  @override
  State<UIFlowTestScreen> createState() => _UIFlowTestScreenState();
}

class _UIFlowTestScreenState extends State<UIFlowTestScreen> {
  late MockTFLiteService _mockService;
  List<DetectionResult> _detections = [];
  String? _lastWarning;
  double _fps = 0;
  int _frameCount = 0;
  DateTime _lastFpsUpdate = DateTime.now();
  bool _isDetecting = false;
  late WarningService _warningService;
  late TtsService _ttsService;

  @override
  void initState() {
    super.initState();
    _warningService = WarningService();
    _ttsService = TtsService();
    _setupMockService();
  }

  void _setupMockService() async {
    _mockService = MockTFLiteService();

    // Setup callbacks
    _mockService.onResult = (result) {
      if (!mounted) return;

      // Update FPS
      _frameCount++;
      final now = DateTime.now();
      final elapsed = now.difference(_lastFpsUpdate).inMilliseconds;
      if (elapsed > 1000) {
        _fps = _frameCount * 1000.0 / elapsed;
        _frameCount = 0;
        _lastFpsUpdate = now;
      }

      // Get warning
      final warning = _warningService.getNextWarning(result);

      setState(() {
        _detections = result.detections;
        _lastWarning = warning ?? _lastWarning;
      });

      // Play warning sound
      if (warning != null) {
        _ttsService.speak(warning);
      }

      // Print warning
      if (warning != null) {
        debugPrint('🔊 WARNING: $warning');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(warning),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    };

    _mockService.onDebugLog = (msg) {
      debugPrint('[UITest] $msg');
    };

    // Initialize
    await _ttsService.initialize();
    await _mockService.initialize();
    debugPrint('[UITest] Mock service & TTS ready ✓');
  }

  void _toggleDetection() {
    setState(() {
      _isDetecting = !_isDetecting;
    });

    if (_isDetecting) {
      debugPrint('[UITest] Detection started - simulating frames...');
      _simulateFrames();
    } else {
      debugPrint('[UITest] Detection stopped');
      _warningService.reset();
    }
  }

  /// Simulate camera frames
  void _simulateFrames() {
    if (!_isDetecting || !mounted) return;

    // Simulate frame with mock camera image (480x640)
    _mockService.processFrame(_createMockCameraImage());

    // Next frame after delay
    Future.delayed(const Duration(milliseconds: 66)).then((_) => _simulateFrames());
  }

  /// Create fake camera image for mock
  MockCameraImage _createMockCameraImage() {
    return MockCameraImage(width: 480, height: 640);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Màu trắng cho dễ nhìn
      appBar: AppBar(
        title: const Text('Test Audio & AI'),
        backgroundColor: Colors.blue,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Nhấn nút bên dưới để kiểm tra:',
              style: TextStyle(color: Colors.black, fontSize: 18),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                print('[UI] Button Test Audio pressed');
                _ttsService.speak('Xin chào, âm thanh đã hoạt động.');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              ),
              child: const Text('1. TEST ÂM THANH', style: TextStyle(fontSize: 20, color: Colors.white)),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                print('[UI] Button Start Detection pressed');
                _toggleDetection();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _isDetecting ? Colors.red : Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              ),
              child: Text(
                _isDetecting ? '2. DỪNG NHẬN DIỆN' : '2. BẮT ĐẦU NHẬN DIỆN',
                style: const TextStyle(fontSize: 20, color: Colors.white),
              ),
            ),
            const SizedBox(height: 30),
            if (_lastWarning != null)
              Container(
                padding: const EdgeInsets.all(10),
                color: Colors.yellow,
                child: Text(
                  'Cảnh báo: $_lastWarning',
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mockService.dispose();
    _isDetecting = false;
    super.dispose();
  }
}

/// Mock camera image for simulation
class MockCameraImage {
  final int width;
  final int height;

  MockCameraImage({required this.width, required this.height});
}
