import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:safewalk_hanoi/core/constants/app_constants.dart';

/// Phân loại tin nhắn TTS theo mức ưu tiên.
///
/// Thứ tự ưu tiên (cao → thấp):
/// - [urgentWarning]: Ô tô, xe máy, xe buýt → ngắt mọi thứ
/// - [warning]: Người đi bộ, người đạp xe → ngắt navigation
/// - [lowWarning]: Vạch kẻ đường, đèn, biển báo, rào chắn, cột điện → KHÔNG ngắt navigation
/// - [navigation]: Chỉ đường → bị ngắt bởi warning/urgentWarning
enum TtsMessageType { navigation, lowWarning, warning, urgentWarning }

/// Text-to-Speech service cho cảnh báo và chỉ đường tiếng Việt.
///
/// Phân cấp ưu tiên:
/// - urgentWarning (ô tô, xe máy, xe buýt): Ngắt ngay lập tức mọi câu nói
/// - warning (người đi bộ, xe đạp): Ngắt navigation để cảnh báo
/// - lowWarning (vạch kẻ, đèn, biển báo...): Chỉ nói khi TTS rảnh
/// - navigation (chỉ đường): Bị ngắt bởi warning/urgentWarning
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeakingFlag = false;
  bool _isInitialized = false;

  /// Thời điểm bắt đầu speak hiện tại (để fallback khi completion handler bị miss)
  int _speakStartedAt = 0;

  /// Thời gian tối đa một câu nói được phép kéo dài.
  /// Nếu completion handler không fire (lỗi platform flutter_tts trên iOS),
  /// dùng timeout này để tự reset `_isSpeaking` → tránh kẹt trạng thái
  /// khiến mọi cảnh báo sau đó bị drop.
  static const int _maxSpeakDurationMs = 10000;

  /// Loại tin nhắn đang được phát
  TtsMessageType _currentType = TtsMessageType.navigation;

  /// Có đang phát không — tự reset nếu vượt quá `_maxSpeakDurationMs`
  /// (phòng trường hợp completion handler bị miss trên iOS).
  bool get _isSpeaking {
    if (!_isSpeakingFlag) return false;
    final elapsed = DateTime.now().millisecondsSinceEpoch - _speakStartedAt;
    if (elapsed > _maxSpeakDurationMs) {
      print('[TTS] ⏰ Speak watchdog timeout (${elapsed}ms) — force clearing stuck state');
      _isSpeakingFlag = false;
      return false;
    }
    return true;
  }

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

      // Callbacks — vẫn lắng nghe nhưng KHÔNG phụ thuộc 100% vào chúng,
      // vì flutter_tts trên iOS đôi khi không gọi completion handler sau
      // khi `stop()` được gọi liên tiếp trước `speak()` (pattern của cảnh báo).
      _tts.setStartHandler(() {
        _isSpeakingFlag = true;
        _speakStartedAt = DateTime.now().millisecondsSinceEpoch;
        print('[TTS] Started speaking');
      });
      _tts.setCompletionHandler(() {
        _isSpeakingFlag = false;
        print('[TTS] Completed');
      });
      _tts.setCancelHandler(() {
        _isSpeakingFlag = false;
        print('[TTS] Cancelled');
      });
      _tts.setErrorHandler((msg) {
        _isSpeakingFlag = false;
        print('[TTS] ERROR: $msg');
      });

      _isInitialized = true;
      print('[TTS] Initialized successfully with ${AppConstants.ttsLanguage}');
    } catch (e) {
      print('[TTS] Init failed: $e');
    }
  }

  /// Nói text với phân cấp ưu tiên.
  ///
  /// Logic ưu tiên:
  /// - [TtsMessageType.urgentWarning]: Ngắt mọi thứ, phát ngay
  /// - [TtsMessageType.warning]: Ngắt navigation, phát ngay.
  ///   Nếu đang phát warning/urgentWarning khác → bỏ qua (tránh chồng chéo)
  /// - [TtsMessageType.lowWarning]: Chỉ phát khi TTS đang rảnh.
  ///   Nếu đang phát bất kỳ thứ gì → bỏ qua
  /// - [TtsMessageType.navigation]: Phát bình thường (queue)
  Future<void> speak(String text, {TtsMessageType type = TtsMessageType.navigation}) async {
    if (!_isInitialized) {
      print('[TTS] Not initialized yet, cannot speak: $text');
      return;
    }
    if (text.isEmpty) return;

    switch (type) {
      case TtsMessageType.urgentWarning:
        // Ngắt mọi thứ, phát cảnh báo khẩn cấp ngay
        print('[TTS] ⚠️ URGENT WARNING - interrupting: $text');
        _currentType = type;
        _markSpeakingNow();
        await _tts.stop();
        await _tts.speak(text);
        break;

      case TtsMessageType.warning:
        // Ngắt navigation để cảnh báo, nhưng không ngắt warning khác
        if (_isSpeaking && (_currentType == TtsMessageType.warning ||
            _currentType == TtsMessageType.urgentWarning)) {
          // Đang phát cảnh báo khác → bỏ qua để tránh chồng chéo
          print('[TTS] ⏭ Dropped warning (another warning speaking): $text');
          return;
        }
        print('[TTS] ⚡ WARNING - interrupting navigation: $text');
        _currentType = type;
        _markSpeakingNow();
        await _tts.stop();
        await _tts.speak(text);
        break;

      case TtsMessageType.lowWarning:
        // Chỉ phát khi TTS rảnh, không ngắt bất kỳ thứ gì
        if (_isSpeaking) {
          print('[TTS] ⏭ Dropped low warning (TTS busy): $text');
          return;
        }
        print('[TTS] 📢 Low warning: $text');
        _currentType = type;
        _markSpeakingNow();
        await _tts.speak(text);
        break;

      case TtsMessageType.navigation:
        // Phát bình thường (có thể bị ngắt bởi warning)
        print('[TTS] 🧭 Navigation: $text');
        _currentType = type;
        _markSpeakingNow();
        await _tts.speak(text);
        break;
    }
  }

  /// Đánh dấu đang phát NGAY LẬP TỨC (không chờ setStartHandler).
  /// Quan trọng: setStartHandler async có thể trễ hoặc bị miss trên iOS.
  /// Việc set đồng bộ ở đây đảm bảo logic priority hoạt động đúng,
  /// còn watchdog timeout (10s) sẽ tự reset nếu completion handler bị miss.
  void _markSpeakingNow() {
    _isSpeakingFlag = true;
    _speakStartedAt = DateTime.now().millisecondsSinceEpoch;
  }

  /// Nói ngay - ngắt câu đang nói (dùng cho close warning)
  Future<void> speakImmediate(String text) async {
    if (!_isInitialized || text.isEmpty) return;
    _currentType = TtsMessageType.urgentWarning;
    _markSpeakingNow();
    await _tts.stop();
    await _tts.speak(text);
  }

  /// Dừng nói
  Future<void> stop() async {
    await _tts.stop();
    _isSpeakingFlag = false;
  }

  /// Giải phóng
  Future<void> dispose() async {
    await _tts.stop();
  }
}
