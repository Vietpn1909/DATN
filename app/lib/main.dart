import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safewalk_hanoi/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Giữ màn hình luôn bật khi sử dụng (quan trọng cho người khiếm thị)
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Chỉ portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(
    const ProviderScope(
      child: SafeWalkApp(),
    ),
  );
}
