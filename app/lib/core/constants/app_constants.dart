/// App-wide constants

class AppConstants {
  AppConstants._();

  // --- Model ---
  static const String modelAssetPath = 'assets/models/best_float16.tflite';
  static const int modelInputSize = 640;
  static const int numClasses = 11;
  static const double confThreshold = 0.35; // Nâng ngưỡng từ 0.25 lên 0.35 để giảm báo sai / nhầm nhãn
  static const double iouThreshold = 0.45;

  // --- Warning ---
  /// Thời gian tối thiểu giữa 2 cảnh báo cùng class (ms)
  static const int warningCooldownMs = 3000;

  /// Số cảnh báo tối đa mỗi frame
  static const int maxWarningsPerFrame = 2;

  // --- Camera FPS ---
  static const int targetFps = 10;

  // --- Goong API Keys ---
  static const String goongApiKey = 'mNJpwM5Uw6qGj4oncu8h2KRU9AotNVZa5iihzTqL';
  static const String goongMaptileKey = 'lNBUrO0xtthLxX33qAazI5iIAcUADDxzFjEOK6ik';
  static String get goongTileUrl =>
      'https://tiles.goong.io/assets/goong_map_web/{z}/{x}/{y}?api_key=$goongMaptileKey';

  // --- TTS ---
  static const String ttsLanguage = 'vi-VN';
  static const double ttsSpeechRate = 0.6;
  static const double ttsVolume = 1.0;
  static const double ttsPitch = 1.0;

  /// Danh sách nhãn tiếng Việt (COCO 80 classes)
  static const List<String> classNamesVi = [
    'người', 'xe đạp', 'ô tô', 'xe máy', 'máy bay', 'xe buýt', 'tàu hỏa', 'xe tải', 'thuyền', 'đèn giao thông',
    'vòi cứu hỏa', 'biển báo dừng', 'máy thu tiền đỗ xe', 'ghế dài', 'con chim', 'con mèo', 'con chó', 'con ngựa', 'con cừu', 'con bò',
    'con voi', 'con gấu', 'con ngựa vằn', 'con hươu cao cổ', 'ba lô', 'chiếc ô', 'túi xách', 'cà vạt', 'vali', 'đĩa bay',
    'ván trượt tuyết', 'ván trượt', 'quả bóng', 'diều', 'gậy bóng chày', 'găng tay bóng chày', 'ván trượt', 'ván lướt sóng', 'vợt tennis', 'chai lọ',
    'ly rượu', 'chiếc cốc', 'nĩa', 'dao', 'thìa', 'bát', 'chuối', 'táo', 'bánh mì kẹp', 'cam',
    'bông cải broccoli', 'cà rốt', 'xúc xích', 'pizza', 'bánh donut', 'bánh ngọt', 'ghế', 'ghế sofa', 'chậu cây', 'giường',
    'bàn ăn', 'nhà vệ sinh', 'tivi', 'máy tính xách tay', 'con chuột', 'điều khiển', 'bàn phím', 'điện thoại', 'lò vi sóng', 'lò nướng',
    'máy nướng bánh mì', 'bồn rửa', 'tủ lạnh', 'cuốn sách', 'đồng hồ', 'bình hoa', 'kéo', 'gấu bông', 'máy sấy tóc', 'bàn chải đánh răng'
  ];

  // --- Accessibility ---
  static const double minFontSize = 24.0;
  static const double minContrastRatio = 7.0;
} 
