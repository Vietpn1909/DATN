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
| ML Model | YOLO11-seg (Ultralytics) |
| Training Framework | PyTorch + Ultralytics |
| Dataset | Mapillary Vistas v2.0 + Custom Old Quarter dataset |
| Mobile App | Flutter |
| On-device Inference | TFLite / ONNX Runtime Mobile |
| Navigation | Google Maps Directions API |
| Voice Input | Speech-to-Text (Google/platform native) |
| Voice Output | Text-to-Speech (flutter_tts) |
| Depth Estimation | MiDaS / Depth Anything v2 (optional) |

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

## 11 Target Classes (Segmentation)

person, bicyclist, motorcyclist, car, bus, motorcycle, crosswalk, pole, traffic_light, traffic_sign, barrier

## Current Status

- [x] Mapillary dataset conversion (detection + segmentation)
- [x] YOLO11n-seg trained (50 epochs) - baseline metrics low
- [ ] YOLO11s-seg training (150 epochs) - in progress
- [ ] Fine-tune on Old Quarter custom dataset
- [ ] Distance estimation module
- [ ] Export model to TFLite/ONNX
- [ ] Flutter app development
- [ ] Voice navigation integration
- [ ] Real-device testing

## Important Rules

- GPU: NVIDIA GTX 1650 (4GB VRAM) - keep batch_size <= 8 for seg training
- All training scripts must support --resume for interrupted training
- Model must run real-time (>= 15 FPS) on mid-range Android phones
- Vietnamese language support required for TTS/STT
- Target audience: visually impaired users - UI must be fully accessible
- All obstacle warnings must be in Vietnamese audio
- Code comments in Vietnamese are acceptable
