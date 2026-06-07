import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';

/// Speech-to-Text service cho nhập địa chỉ bằng giọng nói tiếng Việt.
class SttService {
  final SpeechToText _stt = SpeechToText();
  bool _isAvailable = false;
  bool _isListening = false;

  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;

  /// Callback khi nhận được text
  void Function(String text, bool isFinal)? onResult;

  /// Khởi tạo
  Future<bool> initialize() async {
    _isAvailable = await _stt.initialize(
      onStatus: (status) {
        _isListening = status == 'listening';
      },
      onError: (error) {
        _isListening = false;
      },
    );
    return _isAvailable;
  }

  /// Bắt đầu nghe - tiếng Việt
  Future<void> startListening() async {
    if (!_isAvailable || _isListening) return;

    await _stt.listen(
      localeId: 'vi_VN',
      listenMode: ListenMode.dictation, // Dùng dictation cho câu dài thay vì confirmation
      pauseFor: const Duration(seconds: 3), // Chờ người dùng 3 giây nếu họ ngập ngừng
      listenFor: const Duration(seconds: 5), // Lắng nghe tối đa 5 giây theo yêu cầu
      partialResults: true, // Lấy cả kết quả trung gian
      onResult: (result) {
        onResult?.call(
          result.recognizedWords,
          result.finalResult,
        );
      },
    );
    _isListening = true;
  }

  /// Dừng nghe
  Future<void> stopListening() async {
    await _stt.stop();
    _isListening = false;
  }

  /// Giải phóng
  void dispose() {
    _stt.stop();
    _stt.cancel();
  }
}
