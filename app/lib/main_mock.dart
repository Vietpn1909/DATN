import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:safewalk_hanoi/app.dart';
import 'package:safewalk_hanoi/models/detection.dart';
import 'package:safewalk_hanoi/services/mock_tflite_service.dart';
import 'package:safewalk_hanoi/services/tflite_service.dart';
import 'package:safewalk_hanoi/providers/providers.dart';

/// Mock providers override - dùng MockTFLiteService thay vì real TFLite
final mockTfliteServiceProvider = Provider<MockTFLiteService>((ref) {
  final service = MockTFLiteService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Entry point cho Mock Mode - test UI flow trên máy tính
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(
    const ProviderScope(
      child: MockModeApp(),
    ),
  );
}

/// Overrides providers để dùng mock services
class MockModeApp extends StatelessWidget {
  const MockModeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        // Override TFLite service bằng Mock version
        tfliteServiceProvider.overrideWithValue(MockTFLiteService()),
      ],
      child: const SafeWalkApp(),
    );
  }
}
