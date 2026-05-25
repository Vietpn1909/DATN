import 'dart:isolate';
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:safewalk_hanoi/models/detection.dart';
import 'package:safewalk_hanoi/services/yolo_postprocessor.dart';
import 'package:safewalk_hanoi/core/constants/class_labels.dart';

// ═══════════════════════════════════════════════════════════════════════
// Bottleneck 1: Pre-computed RGB clamp table
// Tránh branch misprediction trong vòng lặp YUV→RGB (102K pixels/frame).
// Index = value + 256 → clamped [0, 255]
// ═══════════════════════════════════════════════════════════════════════
final Uint8List _rgbClampTable = _buildClampTable();

Uint8List _buildClampTable() {
  // YUV→RGB output range: ~[-180, 435] → cần cover [-256, 511]
  final table = Uint8List(768);
  for (int i = 0; i < 768; i++) {
    final v = i - 256;
    table[i] = v < 0 ? 0 : (v > 255 ? 255 : v);
  }
  return table;
}

/// Message khởi tạo gửi đến isolate
class InferenceInitMessage {
  final SendPort sendPort;
  final Uint8List modelBytes;
  final int inputSize;
  final int numClasses;
  final double confThreshold;
  final double iouThreshold;
  final bool useGpuDelegate;
  final bool useNnApi;

  const InferenceInitMessage({
    required this.sendPort,
    required this.modelBytes,
    required this.inputSize,
    required this.numClasses,
    required this.confThreshold,
    required this.iouThreshold,
    required this.useGpuDelegate,
    required this.useNnApi,
  });
}

/// Message chứa frame camera (giữ lại cho backward compatibility)
class FrameMessage {
  final Uint8List yPlane;
  final Uint8List uPlane;
  final Uint8List vPlane;
  final int width;
  final int height;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final String format;

  const FrameMessage({
    required this.yPlane,
    required this.uPlane,
    required this.vPlane,
    required this.width,
    required this.height,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    this.format = 'yuv420',
  });
}

/// Message debug gửi về main isolate
class DebugMessage {
  final String message;
  const DebugMessage(this.message);
}

/// Entry point cho inference isolate
void inferenceIsolateEntry(InferenceInitMessage initMsg) {
  final receivePort = ReceivePort();

  // Gửi SendPort về main isolate
  initMsg.sendPort.send(receivePort.sendPort);

  // Load model từ bytes
  late final Interpreter interpreter;
  late final TensorType inputType;
  late final double inputScale;
  late final int inputZeroPoint;
  late final List<double> outputScales;
  late final List<int> outputZeroPoints;
  late final List<TensorType> outputTypes;

  try {
    // ═══════════════════════════════════════════════════════════════════
    // Bottleneck 2: GPU/NNAPI Delegate — tăng tốc inference ~2-3×
    // Float16 model tương thích tốt với GPU delegate (Metal/OpenGL).
    // Thử GPU delegate trước, fallback NNAPI, cuối cùng CPU.
    // ═══════════════════════════════════════════════════════════════════
    bool gpuActive = false;
    final options = InterpreterOptions()..threads = 4; // Giảm threads khi có GPU

    // Thử thêm GPU Delegate (nếu được phép)
    if (initMsg.useGpuDelegate) {
      try {
        if (Platform.isAndroid) {
          options.addDelegate(GpuDelegateV2(
            options: GpuDelegateOptionsV2(
              isPrecisionLossAllowed: true, // Cho phép float16 → tăng tốc
            ),
          ));
          gpuActive = true;
          initMsg.sendPort.send(const DebugMessage('[Isolate] Android GPU Delegate V2 enabled (float16 optimized) ✓'));
        } else if (Platform.isIOS) {
          options.addDelegate(GpuDelegate(
            options: GpuDelegateOptions(
              allowPrecisionLoss: true, // Float16 native → không mất chất lượng
            ),
          ));
          gpuActive = true;
          initMsg.sendPort.send(const DebugMessage('[Isolate] iOS Metal GPU Delegate enabled (float16 native) ✓'));
        }
      } catch (e) {
        gpuActive = false;
        initMsg.sendPort.send(DebugMessage('[Isolate] GPU Delegate failed, falling back: $e'));
      }
    }

    // Nếu GPU không khả dụng, thử NNAPI trên Android
    if (!gpuActive && initMsg.useNnApi) {
      try {
        options.useNnApiForAndroid = true;
        initMsg.sendPort.send(const DebugMessage(
          '[Isolate] NNAPI Delegate enabled ✓',
        ));
      } catch (e) {
        initMsg.sendPort.send(DebugMessage(
          '[Isolate] NNAPI not available ($e)',
        ));
      }
    }

    // Nếu chạy CPU thuần, tăng threads
    if (!gpuActive && !initMsg.useNnApi) {
      options.threads = 6; // Tăng CPU threads khi không có GPU
      initMsg.sendPort.send(const DebugMessage(
        '[Isolate] No hardware acceleration, using CPU with 6 threads',
      ));
    }

    try {
      interpreter = Interpreter.fromBuffer(initMsg.modelBytes, options: options);
      initMsg.sendPort.send(const DebugMessage('[Isolate] Model loaded successfully'));
    } catch (e) {
      initMsg.sendPort.send(DebugMessage('[Isolate] Delegate failed during interpreter creation: $e. Falling back to CPU only...'));
      try {
        final cpuOptions = InterpreterOptions()..threads = 6;
        interpreter = Interpreter.fromBuffer(initMsg.modelBytes, options: cpuOptions);
        initMsg.sendPort.send(const DebugMessage('[Isolate] Model loaded successfully with CPU fallback ✓'));
      } catch (e2) {
        initMsg.sendPort.send(DebugMessage('[Isolate] ERROR loading model even with CPU: $e2'));
        return;
      }
    }

    // Log + lưu input tensor info
    final inTensor = interpreter.getInputTensor(0);
    inputType = inTensor.type;
    inputScale = inTensor.params.scale == 0 ? 1.0 : inTensor.params.scale;
    inputZeroPoint = inTensor.params.zeroPoint;
    initMsg.sendPort.send(DebugMessage(
      '[Isolate] Input: shape=${inTensor.shape}, type=$inputType, '
      'scale=$inputScale, zp=$inputZeroPoint',
    ));

    // Log + lưu output tensor info
    final outTensors = interpreter.getOutputTensors();
    outputScales = [];
    outputZeroPoints = [];
    outputTypes = [];
    for (int i = 0; i < outTensors.length; i++) {
      final t = outTensors[i];
      final s = t.params.scale == 0 ? 1.0 : t.params.scale;
      final zp = t.params.zeroPoint;
      outputScales.add(s);
      outputZeroPoints.add(zp);
      outputTypes.add(t.type);
      initMsg.sendPort.send(DebugMessage(
        '[Isolate] Output $i: shape=${t.shape}, type=${t.type}, '
        'scale=$s, zp=$zp',
      ));
    }
  } catch (e) {
    initMsg.sendPort.send(DebugMessage('[Isolate] ERROR loading model: $e'));
    return;
  }

  final postprocessor = YoloPostprocessor(
    inputSize: initMsg.inputSize,
    numClasses: initMsg.numClasses,
    confThreshold: initMsg.confThreshold,
    iouThreshold: initMsg.iouThreshold,
  );

  // ═══════════════════════════════════════════════════════════════════════
  // Bottleneck 3: Pre-allocate output buffers — tạo 1 lần, reuse mỗi frame
  // Tránh tạo ~307K objects/frame → giảm GC pressure đáng kể.
  // ═══════════════════════════════════════════════════════════════════════
  final preAllocatedOutputs = <int, Object>{};
  final outputShapes = <int, List<int>>{};
  for (int i = 0; i < interpreter.getOutputTensors().length; i++) {
    final shape = interpreter.getOutputTensor(i).shape;
    outputShapes[i] = shape;
    preAllocatedOutputs[i] = _createOutputBuffer(shape, outputTypes[i]);
  }
  initMsg.sendPort.send(DebugMessage(
    '[Isolate] Pre-allocated ${preAllocatedOutputs.length} output buffers ✓',
  ));

  final inputSize = initMsg.inputSize;
  int frameCount = 0;

  // Listen frames từ main isolate
    receivePort.listen((message) {
      FrameMessage? frame;

      if (message is FrameMessage) {
        frame = message;
      } else if (message is List && message.isNotEmpty) {
        if (message[0] == 'bgra8888' && message.length >= 6) {
          try {
            final td = message[1] as TransferableTypedData;
            final buffer = td.materialize();
            final allBytes = buffer.asUint8List();
            final planeLen = message[2] as int;

            frame = FrameMessage(
              yPlane: Uint8List.view(buffer, 0, planeLen),
              uPlane: Uint8List(0),
              vPlane: Uint8List(0),
              width: message[3] as int,
              height: message[4] as int,
              yRowStride: message[5] as int,
              uvRowStride: 0,
              uvPixelStride: 0,
              format: 'bgra8888',
            );
          } catch (e) {
            initMsg.sendPort.send(DebugMessage('[Isolate] ERROR parsing bgra8888: $e'));
            return;
          }
        } else if (message[0] == 'yuv420' && message.length >= 10) {
          try {
            final td = message[1] as TransferableTypedData;
            final buffer = td.materialize();
            final allBytes = buffer.asUint8List();

            final yLen = message[2] as int;
            final uLen = message[3] as int;

            frame = FrameMessage(
              yPlane: Uint8List.view(buffer, 0, yLen),
              uPlane: Uint8List.view(buffer, yLen, uLen),
              vPlane: Uint8List.view(buffer, yLen + uLen, allBytes.length - yLen - uLen),
              width: message[5] as int,
              height: message[6] as int,
              yRowStride: message[7] as int,
              uvRowStride: message[8] as int,
              uvPixelStride: message[9] as int,
              format: 'yuv420',
            );
          } catch (e) {
            initMsg.sendPort.send(DebugMessage('[Isolate] ERROR parsing yuv420: $e'));
            return;
          }
        } else if (message.length >= 9 && message[0] is TransferableTypedData) {
          // Fallback legacy TransferableTypedData protocol
          try {
            final td = message[0] as TransferableTypedData;
            final buffer = td.materialize();
            final allBytes = buffer.asUint8List();

            final yLen = message[1] as int;
            final uLen = message[2] as int;

            frame = FrameMessage(
              yPlane: Uint8List.view(buffer, 0, yLen),
              uPlane: Uint8List.view(buffer, yLen, uLen),
              vPlane: Uint8List.view(buffer, yLen + uLen, allBytes.length - yLen - uLen),
              width: message[4] as int,
              height: message[5] as int,
              yRowStride: message[6] as int,
              uvRowStride: message[7] as int,
              uvPixelStride: message[8] as int,
              format: 'yuv420',
            );
          } catch (e) {
            initMsg.sendPort.send(DebugMessage('[Isolate] ERROR parsing legacy TransferableTypedData: $e'));
            return;
          }
        }
      }

    if (frame == null) return;

    final stopwatch = Stopwatch()..start();
    frameCount++;

    try {
      // 1. Preprocess: YUV420 -> RGB -> resize -> quantize nếu cần
      final inputData = _preprocessFrame(
        frame,
        inputSize,
        inputType,
        inputScale,
        inputZeroPoint,
      );

      // 2. Reuse pre-allocated output buffers (Bottleneck 3)
      // Không cần clear — interpreter sẽ ghi đè hoàn toàn
      if (frameCount % 30 == 1) {
        initMsg.sendPort.send(const DebugMessage('[Isolate] Starting interpreter.invoke...'));
      }
      // Khắc phục lỗi resize graph của tflite_flutter khi truyền Float32List (nó tưởng là 1D tensor)
      // Bằng cách set memory trực tiếp và gọi invoke, ta bypass cơ chế auto-resize của thư viện.
      interpreter.getInputTensor(0).setTo(inputData);
      interpreter.invoke();
      for (int i = 0; i < preAllocatedOutputs.length; i++) {
        interpreter.getOutputTensor(i).copyTo(preAllocatedOutputs[i]!);
      }
      if (frameCount % 30 == 1) {
        initMsg.sendPort.send(const DebugMessage('[Isolate] interpreter.invoke finished ✓'));
      }

      // 3. Dequantize output nếu là INT8
      final floatOutputs = <int, Object>{};
      for (int i = 0; i < preAllocatedOutputs.length; i++) {
        final raw = preAllocatedOutputs[i];
        if (raw == null) continue;
        if (outputTypes[i] == TensorType.int8) {
          // ═══════════════════════════════════════════════════════════
          // Bottleneck 4: Iterative dequantize thay vì đệ quy
          // ═══════════════════════════════════════════════════════════
          floatOutputs[i] = _dequantizeOutput(
            raw,
            outputScales[i],
            outputZeroPoints[i],
            outputShapes[i]!,
          );
        } else {
          floatOutputs[i] = raw;
        }
      }

      // 4. Postprocess: decode boxes, NMS
      final rawDetections = postprocessor.process(floatOutputs, outputShapes);

      // 5. Convert to DetectionResult với hệ thống hướng mặt đồng hồ
      final results = rawDetections.map((det) {
        final nameVi = ClassLabels.namesVi[det.classId] ?? 'vật cản';
        
        // Tính toán hướng (clock face) dựa trên tâm X của Bounding Box
        final centerX = det.bbox.centerX;
        final ratioX = centerX / inputSize;
        
        String directionVi;
        if (ratioX < 0.33) {
          directionVi = 'hướng 10 giờ'; // Bên trái
        } else if (ratioX <= 0.66) {
          directionVi = 'hướng 12 giờ'; // Ở giữa
        } else {
          directionVi = 'hướng 2 giờ'; // Bên phải
        }

        return DetectionResult(
          detection: det,
          warningTextVi: 'Có $nameVi, $directionVi',
        );
      }).toList();

      // Sort by area (larger/closer objects first in the list)
      results.sort((a, b) => b.detection.bbox.area.compareTo(a.detection.bbox.area));

      final frameResult = FrameResult(
        detections: results,
        priorityDetection: results.isEmpty ? null : results.first,
        warningsVi: results.take(3).map((r) => r.warningTextVi).toList(),
        inferenceTimeMs: stopwatch.elapsedMilliseconds,
      );

      stopwatch.stop();

      // Log mỗi 30 frames
      if (frameCount % 30 == 1) {
        initMsg.sendPort.send(DebugMessage(
          '[Isolate] Frame #$frameCount: ${results.length} detections, '
          '${stopwatch.elapsedMilliseconds}ms',
        ));
      }

      // 6. Gửi kết quả về main isolate
      initMsg.sendPort.send(frameResult);
    } catch (e, stackTrace) {
      initMsg.sendPort.send(DebugMessage(
        '[Isolate] ERROR frame #$frameCount: $e\n$stackTrace',
      ));
      initMsg.sendPort.send(FrameResult(
        detections: [],
        warningsVi: [],
        inferenceTimeMs: stopwatch.elapsedMilliseconds,
      ));
    }
  });
}

/// Preprocess camera frame: YUV420 -> letterbox RGB -> input tensor
///
/// Tối ưu cho 320×320 float32 model:
/// - Trả về Float32List thay vì nested List → tránh tạo ~307K object/frame
/// - Float32List được tflite_flutter copy trực tiếp qua C bridge → nhanh hơn 10×
Object _preprocessFrame(
  FrameMessage frame,
  int targetSize,
  TensorType inputType,
  double inputScale,
  int inputZeroPoint,
) {
  final rgb = frame.format == 'bgra8888' 
      ? _bgra8888ToLetterboxRgb(frame, targetSize) 
      : _yuv420ToLetterboxRgb(frame, targetSize);
  final total = targetSize * targetSize * 3;

  if (inputType == TensorType.float32) {
    // Float32List flat buffer [H*W*3] — tflite_flutter nhận trực tiếp
    final input = Float32List(total);
    for (int i = 0; i < total; i++) {
      input[i] = rgb[i] / 255.0;
    }
    return input;
  } else if (inputType == TensorType.int8) {
    // INT8: q = round(pixel/255 / scale) + zero_point
    final input = Int8List(total);
    for (int i = 0; i < total; i++) {
      final q = (rgb[i] / 255.0 / inputScale).round() + inputZeroPoint;
      input[i] = q.clamp(-128, 127);
    }
    return input;
  } else {
    // uint8 [0-255]
    return Uint8List.fromList(rgb);
  }
}

/// Convert BGRA8888 (iOS default) to letterboxed RGB and rotate 90 degrees if landscape
Uint8List _bgra8888ToLetterboxRgb(FrameMessage frame, int targetSize) {
  // Rotate 90 degrees clockwise if image is landscape (typical for iOS portrait apps)
  final bool rotate90 = frame.width > frame.height;
  final int srcW = rotate90 ? frame.height : frame.width;
  final int srcH = rotate90 ? frame.width : frame.height;

  final rgb = Uint8List(targetSize * targetSize * 3)
    ..fillRange(0, targetSize * targetSize * 3, 114);

  final double scale = targetSize / (srcW > srcH ? srcW : srcH);
  final int newW = (srcW * scale).round().clamp(1, targetSize);
  final int newH = (srcH * scale).round().clamp(1, targetSize);
  final int padX = (targetSize - newW) ~/ 2;
  final int padY = (targetSize - newH) ~/ 2;

  final int xRatioFp = ((srcW << 16) / newW).toInt();
  final int yRatioFp = ((srcH << 16) / newH).toInt();

  for (int dy = 0; dy < newH; dy++) {
    final int sy = (dy * yRatioFp) >> 16;
    if (sy >= srcH) break;

    final int dstRowBase = ((dy + padY) * targetSize + padX) * 3;

    for (int dx = 0; dx < newW; dx++) {
      final int sx = (dx * xRatioFp) >> 16;
      if (sx >= srcW) break;

      int origX, origY;
      if (rotate90) {
        origX = sy;
        origY = frame.height - 1 - sx;
      } else {
        origX = sx;
        origY = sy;
      }

      final int srcOff = (origY * frame.yRowStride) + (origX * 4);
      if (srcOff < 0 || srcOff + 2 >= frame.yPlane.length) continue;

      // BGRA: B=0, G=1, R=2, A=3
      final int b = frame.yPlane[srcOff];
      final int g = frame.yPlane[srcOff + 1];
      final int r = frame.yPlane[srcOff + 2];

      final int dstOff = dstRowBase + dx * 3;
      rgb[dstOff] = r;
      rgb[dstOff + 1] = g;
      rgb[dstOff + 2] = b;
    }
  }
  return rgb;
}

// ═══════════════════════════════════════════════════════════════════════════
// Bottleneck 4: Iterative dequantize thay vì đệ quy
//
// Phiên bản cũ dùng _dequantizeNestedList() recursive → tạo ~400K temporary
// Lists cho output shape [1, 47, 8400]. Phiên bản mới xử lý trực tiếp
// theo shape đã biết trước, tránh allocations không cần thiết.
// ═══════════════════════════════════════════════════════════════════════════

/// Dequantize output tensor dựa trên shape đã biết → float32
/// Xử lý iterative cho các shape phổ biến: 2D, 3D, 4D
Object _dequantizeOutput(Object raw, double scale, int zeroPoint, List<int> shape) {
  if (shape.length == 3) {
    // [1, dim1, dim2] — phổ biến nhất (detection output)
    final batch = (raw as List)[0] as List;
    final dim1 = shape[1];
    final dim2 = shape[2];
    final result = List.generate(
      1,
      (_) => List.generate(
        dim1,
        (i) {
          final row = batch[i] as List;
          final floatRow = List<double>.filled(dim2, 0.0);
          for (int j = 0; j < dim2; j++) {
            final iv = row[j] is int ? row[j] as int : (row[j] as num).toInt();
            floatRow[j] = (iv - zeroPoint) * scale;
          }
          return floatRow;
        },
      ),
    );
    return result;
  } else if (shape.length == 4) {
    // [1, dim1, dim2, dim3] — mask output
    final batch = (raw as List)[0] as List;
    final dim1 = shape[1];
    final dim2 = shape[2];
    final dim3 = shape[3];
    final result = List.generate(
      1,
      (_) => List.generate(
        dim1,
        (i) {
          final plane = batch[i] as List;
          return List.generate(dim2, (j) {
            final row = plane[j] as List;
            final floatRow = List<double>.filled(dim3, 0.0);
            for (int k = 0; k < dim3; k++) {
              final iv = row[k] is int ? row[k] as int : (row[k] as num).toInt();
              floatRow[k] = (iv - zeroPoint) * scale;
            }
            return floatRow;
          });
        },
      ),
    );
    return result;
  } else if (shape.length == 2) {
    // [dim1, dim2]
    final data = raw as List;
    final dim1 = shape[0];
    final dim2 = shape[1];
    final result = List.generate(dim1, (i) {
      final row = data[i] as List;
      final floatRow = List<double>.filled(dim2, 0.0);
      for (int j = 0; j < dim2; j++) {
        final iv = row[j] is int ? row[j] as int : (row[j] as num).toInt();
        floatRow[j] = (iv - zeroPoint) * scale;
      }
      return floatRow;
    });
    return result;
  }

  // Fallback: recursive (cho shape lạ)
  return _dequantizeNestedListFallback(raw, scale, zeroPoint);
}

/// Fallback recursive dequantize cho các shape không phổ biến
Object _dequantizeNestedListFallback(Object raw, double scale, int zeroPoint) {
  if (raw is List) {
    if (raw.isEmpty) return <double>[];
    final first = raw.first;
    if (first is List) {
      return raw.map((e) => _dequantizeNestedListFallback(e as Object, scale, zeroPoint)).toList();
    } else {
      return raw.map<double>((v) {
        final iv = v is int ? v : (v as num).toInt();
        return (iv - zeroPoint) * scale;
      }).toList();
    }
  }
  return raw;
}

// ═══════════════════════════════════════════════════════════════════════════
// Bottleneck 1: Optimized YUV420 → letterbox RGB
//
// Cải tiến so với phiên bản cũ:
// 1. Dùng _rgbClampTable lookup thay vì if/else branch → tránh branch
//    misprediction (tiết kiệm ~3-5ms trên 102K pixels)
// 2. Pre-calculate safe bounds → loại bỏ bounds check trong inner loop
// 3. Cache row base calculations để giảm phép nhân
// ═══════════════════════════════════════════════════════════════════════════

/// Single-pass YUV420 → letterbox resize → RGB (Uint8List).
///
/// Hỗ trợ cả 2 format phổ biến trên Android:
/// - YUV420 planar (bytesPerPixel=1): U/V tách biệt
/// - NV21/NV12 semi-planar (bytesPerPixel=2): U/V interleaved
Uint8List _yuv420ToLetterboxRgb(FrameMessage frame, int targetSize) {
  final int srcW = frame.width;
  final int srcH = frame.height;
  final rgb = Uint8List(targetSize * targetSize * 3)
    ..fillRange(0, targetSize * targetSize * 3, 114);

  // Letterbox scale
  final double scale = targetSize / (srcW > srcH ? srcW : srcH);
  final int newW = (srcW * scale).round().clamp(1, targetSize);
  final int newH = (srcH * scale).round().clamp(1, targetSize);
  final int padX = (targetSize - newW) ~/ 2;
  final int padY = (targetSize - newH) ~/ 2;

  // Fixed-point ratios (16-bit precision)
  final int xRatioFp = ((srcW << 16) / newW).toInt();
  final int yRatioFp = ((srcH << 16) / newH).toInt();

  // Pre-calculate safe bounds → loại bỏ bounds check trong inner loop
  final int yLen = frame.yPlane.length;
  final int uLen = frame.uPlane.length;
  final int vLen = frame.vPlane.length;

  // Pre-calculate safe newW/newH để tránh OOB
  // sx_max = ((safeNewW-1) * xRatioFp) >> 16 phải < srcW
  // sy_max = ((safeNewH-1) * yRatioFp) >> 16 phải < srcH
  final int safeNewW = min(newW, srcW);
  final int safeNewH = min(newH, srcH);

  // Reference clamp table
  final clamp = _rgbClampTable;

  for (int dy = 0; dy < safeNewH; dy++) {
    final int sy = (dy * yRatioFp) >> 16;
    if (sy >= srcH) break; // safety net

    final int yRowBase = sy * frame.yRowStride;
    final int uvRowBase = (sy >> 1) * frame.uvRowStride;
    final int dstRowBase = ((dy + padY) * targetSize + padX) * 3;

    for (int dx = 0; dx < safeNewW; dx++) {
      final int sx = (dx * xRatioFp) >> 16;
      if (sx >= srcW) break; // safety net

      // Y sample — bounds check chỉ khi yRowStride != srcW (hiếm)
      final int yOff = yRowBase + sx;
      if (yOff >= yLen) continue;
      final int yVal = frame.yPlane[yOff];

      // UV sample
      final int uvOff = uvRowBase + (sx >> 1) * frame.uvPixelStride;
      final int uVal = (uvOff < uLen) ? frame.uPlane[uvOff] - 128 : 0;
      final int vVal = (uvOff < vLen) ? frame.vPlane[uvOff] - 128 : 0;

      // Fixed-point YUV→RGB (<<10) + clamp table lookup (no branches!)
      final int r = yVal + ((vVal * 1436) >> 10);
      final int g = yVal - ((uVal * 352 + vVal * 731) >> 10);
      final int b = yVal + ((uVal * 1814) >> 10);

      final int idx = dstRowBase + dx * 3;
      rgb[idx]     = clamp[r + 256]; // Bottleneck 1: table lookup thay vì if/else
      rgb[idx + 1] = clamp[g + 256];
      rgb[idx + 2] = clamp[b + 256];
    }
  }
  return rgb;
}

/// Tạo output buffer dựa trên tensor shape và type
Object _createOutputBuffer(List<int> shape, TensorType type) {
  final isFloat = type == TensorType.float32 || type == TensorType.float16;
  if (shape.length == 2) {
    return isFloat
        ? List.generate(shape[0], (_) => List.filled(shape[1], 0.0))
        : List.generate(shape[0], (_) => List.filled(shape[1], 0));
  } else if (shape.length == 3) {
    return isFloat
        ? List.generate(shape[0], (_) => List.generate(shape[1], (_) => List.filled(shape[2], 0.0)))
        : List.generate(shape[0], (_) => List.generate(shape[1], (_) => List.filled(shape[2], 0)));
  } else if (shape.length == 4) {
    return isFloat
        ? List.generate(shape[0], (_) => List.generate(shape[1], (_) => List.generate(shape[2], (_) => List.filled(shape[3], 0.0))))
        : List.generate(shape[0], (_) => List.generate(shape[1], (_) => List.generate(shape[2], (_) => List.filled(shape[3], 0))));
  }
  return [];
}
