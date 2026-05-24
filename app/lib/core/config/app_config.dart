/// App Configuration - Switch between real and mock services
/// 
/// Để test UI flow trên máy tính mà không cần Android device:
/// Set useMockServices = true

class AppConfig {
  /// Set to true để test UI flow với mock detections (không cần GPU/Android)
  /// Set to false để dùng real TFLite service
  static const bool useMockServices = false;

  /// Set to true để dùng GPU acceleration (nếu thiết bị hỗ trợ)
  /// Float16 model tương thích tốt với GPU delegate (Metal trên iOS, OpenGL/Vulkan trên Android).
  /// Lưu ý: INT8 quantized KHÔNG tương thích với Metal → đã fix bằng cách chuyển sang float16.
  static const bool useGpuDelegate = false;

  /// Số luồng xử lý CPU (tăng lên 4-6 để bù lại việc không dùng GPU)
  static const int numThreads = 6;

  /// Set to true để dùng NNAPI (thường ổn định hơn GPU trên Android)
  /// Tắt trên Samsung A11 nếu gặp lỗi "Node PAD failed to prepare"
  static const bool useNnApi = false;

  /// Debug mode - show extra logs
  static const bool debugMode = true;
}
