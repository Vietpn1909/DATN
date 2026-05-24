import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Quản lý camera: khởi tạo, stream frames, giải phóng.
/// Dùng camera sau (back camera) với resolution thấp để tiết kiệm pin.
class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isProcessing = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  /// Callback khi có frame mới - được gọi từ startImageStream
  void Function(CameraImage image)? onFrameAvailable;

  /// Khởi tạo camera sau
  Future<void> initialize() async {
    _cameras = await availableCameras();
    if (_cameras == null || _cameras!.isEmpty) {
      throw Exception('Không tìm thấy camera');
    }

    // Chọn camera sau (back camera)
    final backCamera = _cameras!.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras!.first,
    );

    // Resolution medium để cân bằng chất lượng và tốc độ
    _controller = CameraController(
      backCamera,
      ResolutionPreset.medium, // 480p - tốt cho inference
      enableAudio: false,
      imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS 
          ? ImageFormatGroup.bgra8888 
          : ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();
  }

  /// Bắt đầu stream frames cho inference
  void startImageStream() {
    if (_controller == null || !isInitialized) return;

    _controller!.startImageStream((CameraImage image) {
      // Backpressure: skip frame nếu đang xử lý frame trước
      if (_isProcessing) return;
      _isProcessing = true;

      onFrameAvailable?.call(image);
    });
  }

  /// Đánh dấu đã xử lý xong frame - cho phép nhận frame tiếp
  void frameProcessed() {
    _isProcessing = false;
  }

  /// Dừng stream
  Future<void> stopImageStream() async {
    if (_controller != null && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
  }

  /// Giải phóng camera
  Future<void> dispose() async {
    await stopImageStream();
    await _controller?.dispose();
    _controller = null;
  }
}
