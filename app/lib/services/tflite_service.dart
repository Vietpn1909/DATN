import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:safewalk_hanoi/core/config/app_config.dart';
import 'package:safewalk_hanoi/core/constants/app_constants.dart';
import 'package:safewalk_hanoi/models/detection.dart';
import 'package:safewalk_hanoi/services/inference_isolate.dart';

/// Service quản lý TFLite Inference.
class TfliteService {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  bool _isReady = false;
  bool _isProcessing = false;
  Completer<void>? _initCompleter;

  bool get isReady => _isReady;

  /// Callback khi có kết quả nhận diện
  Function(FrameResult)? onResult;
  Function(String)? onDebugLog;

  /// Khởi tạo Isolate và nạp model
  Future<void> initialize() async {
    if (_isReady) return;
    _initCompleter = Completer<void>();

    _receivePort = ReceivePort();
    
    // Đọc model từ assets
    final modelData = await rootBundle.load(AppConstants.modelAssetPath);
    final modelBytes = modelData.buffer.asUint8List();

    // Khởi tạo Isolate
    _isolate = await Isolate.spawn(
      inferenceIsolateEntry,
      InferenceInitMessage(
        sendPort: _receivePort!.sendPort,
        modelBytes: modelBytes,
        inputSize: AppConstants.modelInputSize,
        numClasses: AppConstants.numClasses,
        confThreshold: AppConstants.confThreshold,
        iouThreshold: AppConstants.iouThreshold,
        useGpuDelegate: AppConfig.useGpuDelegate,
        useNnApi: AppConfig.useNnApi,
      ),
    );

    // Listen kết quả từ isolate
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _isReady = true;
        debugPrint('[TFLite] Isolate ready');
        _initCompleter?.complete();
      } else if (message is FrameResult) {
        _isProcessing = false; // QUAN TRỌNG: Mở khóa để nhận frame tiếp theo
        onResult?.call(message);
      } else if (message is DebugMessage) {
        debugPrint(message.message);
        onDebugLog?.call(message.message);
      }
    });

    return _initCompleter!.future;
  }

  /// Gửi frame camera đến isolate để inference
  void processFrame(CameraImage image) {
    if (!_isReady || _sendPort == null || _isProcessing) return;

    if (image.format.group == ImageFormatGroup.yuv420) {
      if (image.planes.length < 3) return;

      final yPlane = image.planes[0].bytes;
      final uPlane = image.planes[1].bytes;
      final vPlane = image.planes[2].bytes;

      try {
        final td = TransferableTypedData.fromList([
          yPlane.buffer.asByteData(yPlane.offsetInBytes, yPlane.lengthInBytes),
          uPlane.buffer.asByteData(uPlane.offsetInBytes, uPlane.lengthInBytes),
          vPlane.buffer.asByteData(vPlane.offsetInBytes, vPlane.lengthInBytes),
        ]);

        _isProcessing = true; // Khóa lại cho đến khi có kết quả
        _sendPort!.send([
          'yuv420',
          td,
          yPlane.length,
          uPlane.length,
          vPlane.length,
          image.width,
          image.height,
          image.planes[0].bytesPerRow,
          image.planes[1].bytesPerRow,
          image.planes[1].bytesPerPixel ?? 1,
        ]);
      } catch (e) {
        debugPrint('[TFLite] Transfer failed: $e');
        _isProcessing = false;
      }
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      if (image.planes.isEmpty) return;

      final plane = image.planes[0].bytes;

      try {
        final td = TransferableTypedData.fromList([
          plane.buffer.asByteData(plane.offsetInBytes, plane.lengthInBytes),
        ]);

        _isProcessing = true;
        _sendPort!.send([
          'bgra8888',
          td,
          plane.length,
          image.width,
          image.height,
          image.planes[0].bytesPerRow,
        ]);
      } catch (e) {
        debugPrint('[TFLite] Transfer failed: $e');
        _isProcessing = false;
      }
    }
  }

  void dispose() {
    _isolate?.kill();
    _receivePort?.close();
    _isReady = false;
  }
}
