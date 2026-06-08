# SafeWalk Hanoi - AI Navigation App for Visually Impaired

## Project Overview

DATN (Do An Tot Nghiep) - Ung dung ho tro nguoi khiem thi di lai an toan tai khu vuc pho co Ho Hoan Kiem, Ha Noi.

**Core Features:**
1. Voice-guided navigation (STT -> Map Directions -> TTS)
2. Real-time obstacle detection via phone camera (YOLO11-seg)
3. Distance estimation to obstacles
4. Audio warnings about detected obstacles

## Tech Stack

| Component | Technology |
|-----------|------------|
| ML Model | YOLO11n detection (Ultralytics) — 11 classes, bounding box |
| Training Framework | PyTorch + Ultralytics |
| Dataset | Mapillary Vistas v2.0 + Custom Old Quarter dataset |
| Mobile App | Flutter (Riverpod state management) |
| On-device Inference | TFLite Float16 (`best_float16.tflite`, ~20MB) |
| Navigation / Maps | Goong Maps API + flutter_map (Vietnam-localized) |
| Voice Input | Speech-to-Text (`speech_to_text` package, vi-VN) |
| Voice Output | Text-to-Speech (`flutter_tts`, vi-VN) |
| Threat Assessment | Bounding box area ratio + temporal filter (2/3 frames) |

## Project Structure

```
DATN/
├── configs/mapillary/          # Dataset label configs & class selection
├── data/
│   ├── raw/mapillary/          # Mapillary Vistas raw (train/val/test)
│   ├── raw/old_quarter_videos/ # Self-recorded videos in Old Quarter
│   ├── interim/                # Extracted frames from videos
│   ├── yolo/                   # YOLO detection format (22 classes)
│   └── yolo_seg/               # YOLO segmentation format (11 classes)
├── scripts/
│   ├── data/                   # Data conversion & preprocessing
│   └── train/                  # Training scripts
├── outputs/
│   ├── runs/                   # Detection training results
│   └── runs_seg/               # Segmentation training results
└── app/                        # Flutter mobile app (upcoming)
```

## 11 Target Classes (Detection — bounding box)

person, bicyclist, motorcyclist, car, bus, motorcycle, crosswalk, pole, traffic_light, traffic_sign, barrier

Per-class confidence thresholds (see `app/lib/core/constants/class_labels.dart`):
- person (0.50), bicyclist (0.50)
- motorcyclist (0.65), motorcycle (0.65)
- car (0.75), bus (0.75) — strict to avoid FP
- crosswalk (0.35), pole (0.35), barrier (0.35)
- traffic_light (0.40), traffic_sign (0.40)

## Current Status

- [x] Mapillary dataset conversion (detection format)
- [x] YOLO11n detection trained — 2-stage pipeline (Mapillary 150 epochs + Old Quarter fine-tune 86 epochs)
- [x] Fine-tune on Old Quarter custom dataset (bounding box mAP50 = 0.687)
- [x] Threat assessment via bounding box area ratio + temporal filter
- [x] Export model to TFLite Float16
- [x] Flutter app development (Riverpod + tflite_flutter + Goong API)
- [x] Voice navigation integration (STT + Goong Direction + TTS)
- [x] Real-device testing on iPhone 13
- [ ] Settings screen (UC4.x — TTS speed, volume, system status)

## Important Rules

- GPU: NVIDIA GTX 1650 (4GB VRAM) — keep batch_size <= 16 for detection training
- All training scripts must support --resume for interrupted training
- Model must run real-time (>= 15 FPS) on iPhone 13 (Apple A15 Bionic)
- Vietnamese language support required for TTS/STT (vi-VN)
- Target audience: visually impaired users — UI must be fully accessible (VoiceOver/TalkBack)
- All obstacle warnings must be in Vietnamese audio
- Code comments in Vietnamese are acceptable
- Goong Direction API uses `vehicle=bike` mode (no walking mode available)
