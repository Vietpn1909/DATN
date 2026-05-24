import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:safewalk_hanoi/core/constants/app_constants.dart';

/// Text-to-Speech service cho cảnh báo và chỉ đường tiếng Việt.
///
/// Ưu tiên:
/// - Close warning có thể ngắt câu đang nói
/// - Navigation instruction được queue sau warning
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  bool _isInitialized = false;

  bool get isSpeaking => _isSpeaking;

  /// Khởi tạo TTS với giọng tiếng Việt
  Future<void> initialize() async {
    print('[TTS] --- Initializing TTS ---');
    try {
      // Log available engines (chỉ Android hỗ trợ getEngines)
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final engines = await _tts.getEngines;
          print('[TTS] Available engines: $engines');
        } catch (_) {}
      }

      // Thử dùng Google TTS Engine trên Android, cấu hình session cho iOS
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _tts.setEngine('com.google.android.tts');
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            IosTextToSpeechAudioCategoryOptions.duckOthers,
          ],
          IosTextToSpeechAudioMode.voicePrompt,
        );
      }
      
      await _tts.setLanguage(AppConstants.ttsLanguage);
      await _tts.setSpeechRate(AppConstants.ttsSpeechRate);
      await _tts.setVolume(AppConstants.ttsVolume);
      await _tts.setPitch(AppConstants.ttsPitch);

      // Callbacks
      _tts.setStartHandler(() {
        _isSpeaking = true;
        print('[TTS] Started speaking');
      });
      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        print('[TTS] Completed');
      });
      _tts.setErrorHandler((msg) {
        _isSpeaking = false;
        print('[TTS] ERROR: $msg');
      });

      _isInitialized = true;
      print('[TTS] Initialized successfully with ${AppConstants.ttsLanguage}');
    } catch (e) {
      print('[TTS] Init failed: $e');
    }
  }

  /// Nói text - queue sau câu hiện tại
  Future<void> speak(String text) async {
    if (!_isInitialized) {
      print('[TTS] Not initialized yet, cannot speak: $text');
      return;
    }
    if (text.isEmpty) return;
    print('[TTS] Calling speak: $text');
    await _tts.speak(text);
  }

  /// Nói ngay - ngắt câu đang nói (dùng cho close warning)
  Future<void> speakImmediate(String text) async {
    if (!_isInitialized || text.isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  /// Dừng nói
  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }

  /// Giải phóng
  Future<void> dispose() async {
    await _tts.stop();
  }
}
