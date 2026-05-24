import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safewalk_hanoi/core/theme/app_theme.dart';
import 'package:safewalk_hanoi/screens/test/ui_flow_test_screen.dart';

/// Entry point để test UI flow - chạy trên máy tính without Android device
/// 
/// Run with: flutter run -t lib/main_test.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const UIFlowTestApp());
}

class UIFlowTestApp extends StatelessWidget {
  const UIFlowTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeWalk - UI Flow Test',
      theme: AppTheme.darkTheme,
      home: const UIFlowTestScreen(),
      debugShowCheckedModeBanner: true,
    );
  }
}
