"""
Demo Distance Estimation
=========================
Script demo ước tính khoảng cách trên ảnh hoặc video
sử dụng YOLO11-seg + BBox Distance Estimator.

Cách dùng:
    # Trên 1 ảnh
    python scripts/distance/demo_distance.py --source path/to/image.jpg

    # Trên thư mục ảnh (vd: tập test)
    python scripts/distance/demo_distance.py --source data/yolo_seg_oldquarter/test/images/

    # Trên video
    python scripts/distance/demo_distance.py --source path/to/video.mp4

    # Với webcam
    python scripts/distance/demo_distance.py --source 0

    # Calibrate focal length
    python scripts/distance/demo_distance.py --calibrate --source path/to/calibration_image.jpg \\
        --known-distance 3.0 --known-height 1.65 --known-class 0
"""

from __future__ import annotations

import sys
import argparse
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

import cv2
import numpy as np
from ultralytics import YOLO

# Import module distance estimation
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))
from scripts.distance.bbox_distance import (
    BBoxDistanceEstimator,
    CLASS_NAMES,
    CLASS_NAMES_VI,
    calibrate_focal_length,
)


# ============================================================
# Visualization
# ============================================================

# Màu sắc cho mỗi mức cảnh báo (BGR)
WARNING_COLORS = {
    "close": (0, 0, 255),      # Đỏ
    "medium": (0, 165, 255),    # Cam
    "far": (0, 255, 0),        # Xanh lá
    "unknown": (128, 128, 128), # Xám
}


def draw_detection(
    frame: np.ndarray,
    det,
    show_mask: bool = True,
) -> np.ndarray:
    """Vẽ detection + khoảng cách lên frame."""
    x1, y1, x2, y2 = [int(v) for v in det.bbox]
    color = WARNING_COLORS.get(det.warning_level, (128, 128, 128))

    # Vẽ bbox
    thickness = 3 if det.warning_level == "close" else 2
    cv2.rectangle(frame, (x1, y1), (x2, y2), color, thickness)

    # Vẽ mask overlay nếu có
    if show_mask and det.mask is not None:
        mask_resized = cv2.resize(
            det.mask.astype(np.uint8),
            (frame.shape[1], frame.shape[0]),
            interpolation=cv2.INTER_NEAREST,
        )
        overlay = frame.copy()
        overlay[mask_resized > 0] = color
        cv2.addWeighted(overlay, 0.3, frame, 0.7, 0, frame)

    # Label: class + distance
    if det.distance_m > 0:
        label = f"{det.class_name} {det.distance_m:.1f}m ({det.confidence:.0%})"
    else:
        label = f"{det.class_name} ??m ({det.confidence:.0%})"

    # Background cho text
    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.6
    (tw, th), _ = cv2.getTextSize(label, font, font_scale, 1)
    cv2.rectangle(frame, (x1, y1 - th - 10), (x1 + tw + 4, y1), color, -1)
    cv2.putText(frame, label, (x1 + 2, y1 - 5), font, font_scale, (255, 255, 255), 2)

    return frame


def draw_warnings(
    frame: np.ndarray,
    warnings_vi: list[str],
) -> np.ndarray:
    """Vẽ cảnh báo tiếng Việt ở góc trên bên trái."""
    font = cv2.FONT_HERSHEY_SIMPLEX
    y_offset = 30

    for i, warning in enumerate(warnings_vi):
        color = (0, 0, 255) if i == 0 else (0, 165, 255)
        # Background
        (tw, th), _ = cv2.getTextSize(warning, font, 0.6, 2)
        cv2.rectangle(frame, (5, y_offset - th - 5), (tw + 15, y_offset + 5), (0, 0, 0), -1)
        cv2.putText(frame, warning, (10, y_offset), font, 0.6, color, 2)
        y_offset += 35

    return frame


# ============================================================
# Processing modes
# ============================================================

def process_image(
    model: YOLO,
    estimator: BBoxDistanceEstimator,
    image_path: Path,
    output_dir: Path,
    show: bool = False,
    conf_threshold: float = 0.25,
) -> None:
    """Xử lý 1 ảnh."""
    frame = cv2.imread(str(image_path))
    if frame is None:
        print(f"[ERROR] Không đọc được ảnh: {image_path}")
        return

    # YOLO inference
    results = model(frame, conf=conf_threshold, verbose=False)
    result = results[0]

    # Distance estimation
    frame_result = estimator.process_yolo_result(result, conf_threshold)

    # Vẽ kết quả
    for det in frame_result.detections:
        draw_detection(frame, det)
    draw_warnings(frame, frame_result.warnings_vi)

    # In cảnh báo ra console
    print(f"\n--- {image_path.name} ---")
    print(f"Phát hiện {len(frame_result.detections)} vật thể:")
    for det in frame_result.detections:
        dist_str = f"{det.distance_m:.1f}m" if det.distance_m > 0 else "N/A"
        print(f"  [{det.warning_level:6s}] {det.class_name_vi:20s} | {dist_str:>6s} | conf={det.confidence:.2f}")

    if frame_result.warnings_vi:
        print("Cảnh báo:")
        for w in frame_result.warnings_vi:
            print(f"  🔊 {w}")

    if frame_result.closest_detection:
        c = frame_result.closest_detection
        print(f"Vật gần nhất: {c.class_name_vi} - {c.distance_m:.1f}m")

    # Lưu kết quả
    output_path = output_dir / f"dist_{image_path.name}"
    cv2.imwrite(str(output_path), frame)
    print(f"Đã lưu: {output_path}")

    if show:
        cv2.imshow("Distance Estimation", frame)
        cv2.waitKey(0)
        cv2.destroyAllWindows()


def process_directory(
    model: YOLO,
    estimator: BBoxDistanceEstimator,
    dir_path: Path,
    output_dir: Path,
    max_images: int = 20,
    conf_threshold: float = 0.25,
) -> None:
    """Xử lý thư mục ảnh."""
    extensions = {".jpg", ".jpeg", ".png", ".bmp"}
    images = sorted([
        f for f in dir_path.iterdir()
        if f.suffix.lower() in extensions
    ])

    if not images:
        print(f"[ERROR] Không tìm thấy ảnh trong: {dir_path}")
        return

    if len(images) > max_images:
        # Lấy ngẫu nhiên max_images ảnh
        rng = np.random.default_rng(42)
        indices = rng.choice(len(images), size=max_images, replace=False)
        images = [images[i] for i in sorted(indices)]

    print(f"Xử lý {len(images)} ảnh từ {dir_path}...")

    all_distances = []
    for img_path in images:
        results = model(cv2.imread(str(img_path)), conf=conf_threshold, verbose=False)
        frame_result = estimator.process_yolo_result(results[0], conf_threshold)

        for det in frame_result.detections:
            if det.distance_m > 0:
                all_distances.append({
                    "image": img_path.name,
                    "class": det.class_name,
                    "distance": det.distance_m,
                    "level": det.warning_level,
                    "confidence": det.confidence,
                })

        # Vẽ và lưu
        frame = cv2.imread(str(img_path))
        for det in frame_result.detections:
            draw_detection(frame, det)
        draw_warnings(frame, frame_result.warnings_vi)
        cv2.imwrite(str(output_dir / f"dist_{img_path.name}"), frame)

    # Thống kê
    print(f"\n{'='*60}")
    print(f"THỐNG KÊ KHOẢNG CÁCH - {len(images)} ảnh")
    print(f"{'='*60}")
    print(f"Tổng detections: {len(all_distances)}")

    if all_distances:
        distances = [d["distance"] for d in all_distances]
        print(f"Khoảng cách trung bình: {np.mean(distances):.1f}m")
        print(f"Khoảng cách min/max: {np.min(distances):.1f}m / {np.max(distances):.1f}m")

        close_count = sum(1 for d in all_distances if d["level"] == "close")
        medium_count = sum(1 for d in all_distances if d["level"] == "medium")
        far_count = sum(1 for d in all_distances if d["level"] == "far")
        print(f"Gần (<3m): {close_count} | Trung bình (3-7m): {medium_count} | Xa (>7m): {far_count}")

        # Thống kê theo class
        print(f"\nTheo class:")
        from collections import defaultdict
        class_stats = defaultdict(list)
        for d in all_distances:
            class_stats[d["class"]].append(d["distance"])

        for cls_name, dists in sorted(class_stats.items()):
            print(f"  {cls_name:20s}: n={len(dists):3d}, "
                  f"avg={np.mean(dists):.1f}m, "
                  f"min={np.min(dists):.1f}m, max={np.max(dists):.1f}m")

    print(f"\nKết quả đã lưu tại: {output_dir}")


def process_video(
    model: YOLO,
    estimator: BBoxDistanceEstimator,
    video_source,
    output_dir: Path,
    show: bool = True,
    conf_threshold: float = 0.25,
) -> None:
    """Xử lý video hoặc webcam."""
    # Mở video source
    if isinstance(video_source, int) or video_source.isdigit():
        cap = cv2.VideoCapture(int(video_source) if isinstance(video_source, str) else video_source)
        source_name = f"webcam_{video_source}"
    else:
        cap = cv2.VideoCapture(str(video_source))
        source_name = Path(video_source).stem

    if not cap.isOpened():
        print(f"[ERROR] Không mở được video: {video_source}")
        return

    # Video writer
    fps = int(cap.get(cv2.CAP_PROP_FPS)) or 30
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    output_path = output_dir / f"dist_{source_name}.mp4"
    writer = cv2.VideoWriter(
        str(output_path),
        cv2.VideoWriter_fourcc(*"mp4v"),
        fps,
        (w, h),
    )

    frame_count = 0
    print(f"Đang xử lý video... (nhấn 'q' để dừng)")

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        frame_count += 1

        # YOLO inference
        results = model(frame, conf=conf_threshold, verbose=False)
        frame_result = estimator.process_yolo_result(results[0], conf_threshold)

        # Vẽ kết quả
        for det in frame_result.detections:
            draw_detection(frame, det, show_mask=False)  # Tắt mask cho video (nhanh hơn)
        draw_warnings(frame, frame_result.warnings_vi)

        # FPS info
        cv2.putText(
            frame, f"Frame: {frame_count}",
            (frame.shape[1] - 150, 30),
            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2,
        )

        writer.write(frame)

        if show:
            cv2.imshow("Distance Estimation", frame)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break

    cap.release()
    writer.release()
    cv2.destroyAllWindows()
    print(f"Đã lưu video: {output_path} ({frame_count} frames)")


def run_calibration(
    model: YOLO,
    image_path: Path,
    known_distance: float,
    known_height: float,
    known_class: int,
) -> None:
    """
    Calibrate focal length từ ảnh có sẵn thông tin khoảng cách.

    Bước calibrate:
    1. Đặt vật thể (vd: người) ở khoảng cách đã đo (vd: 3m)
    2. Chụp ảnh
    3. Chạy script này với --calibrate
    4. Cập nhật focal_length_px trong camera_params.json
    """
    frame = cv2.imread(str(image_path))
    if frame is None:
        print(f"[ERROR] Không đọc được ảnh: {image_path}")
        return

    results = model(frame, verbose=False)
    result = results[0]

    if result.boxes is None or len(result.boxes) == 0:
        print("[ERROR] Không phát hiện vật thể nào trong ảnh!")
        return

    # Tìm detection của class cần calibrate
    boxes = result.boxes.xyxy.cpu().numpy()
    classes = result.boxes.cls.cpu().numpy().astype(int)
    confs = result.boxes.conf.cpu().numpy()

    target_indices = [i for i, c in enumerate(classes) if c == known_class]
    if not target_indices:
        print(f"[ERROR] Không tìm thấy class {known_class} ({CLASS_NAMES.get(known_class, '?')}) trong ảnh!")
        return

    # Lấy detection có confidence cao nhất
    best_idx = max(target_indices, key=lambda i: confs[i])
    bbox = boxes[best_idx]
    bbox_height = bbox[3] - bbox[1]

    focal_length = calibrate_focal_length(known_distance, known_height, bbox_height)

    print(f"\n{'='*50}")
    print("KẾT QUẢ CALIBRATION")
    print(f"{'='*50}")
    print(f"Class: {CLASS_NAMES.get(known_class, '?')} (id={known_class})")
    print(f"Khoảng cách thực: {known_distance}m")
    print(f"Chiều cao thực: {known_height}m")
    print(f"BBox height: {bbox_height:.1f}px")
    print(f"Confidence: {confs[best_idx]:.2f}")
    print(f"\n→ Focal length = {focal_length:.1f} px")
    print(f"\nHãy cập nhật giá trị này vào configs/distance/camera_params.json")
    print(f'  "focal_length_px": {focal_length:.0f}')


# ============================================================
# Main
# ============================================================

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Demo BBox-based Distance Estimation với YOLO11-seg",
    )
    parser.add_argument(
        "--source",
        type=str,
        required=True,
        help="Đường dẫn ảnh, thư mục ảnh, video, hoặc '0' cho webcam",
    )
    parser.add_argument(
        "--model",
        type=str,
        default=None,
        help="Đường dẫn model YOLO (.pt). Mặc định: best.pt fine-tuned",
    )
    parser.add_argument(
        "--config",
        type=str,
        default=None,
        help="Đường dẫn camera_params.json",
    )
    parser.add_argument(
        "--focal-length",
        type=float,
        default=600,
        help="Focal length (px) nếu không dùng config file (default: 600)",
    )
    parser.add_argument(
        "--conf",
        type=float,
        default=0.25,
        help="Confidence threshold (default: 0.25)",
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default=None,
        help="Thư mục lưu kết quả (default: outputs/distance/)",
    )
    parser.add_argument(
        "--max-images",
        type=int,
        default=20,
        help="Số ảnh tối đa khi xử lý thư mục (default: 20)",
    )
    parser.add_argument(
        "--show",
        action="store_true",
        help="Hiển thị kết quả (cv2.imshow)",
    )
    # Calibration mode
    parser.add_argument(
        "--calibrate",
        action="store_true",
        help="Chế độ calibrate focal length",
    )
    parser.add_argument(
        "--known-distance",
        type=float,
        help="Khoảng cách thực đến vật (m) - dùng với --calibrate",
    )
    parser.add_argument(
        "--known-height",
        type=float,
        help="Chiều cao thực của vật (m) - dùng với --calibrate",
    )
    parser.add_argument(
        "--known-class",
        type=int,
        default=0,
        help="Class ID của vật dùng calibrate (default: 0=person)",
    )

    return parser.parse_args()


def main() -> None:
    args = parse_args()

    # Xác định đường dẫn mặc định
    project_root = Path(__file__).resolve().parent.parent.parent
    default_model = project_root / "outputs" / "runs_seg" / "yolo11seg_oldquarter_finetune" / "weights" / "best.pt"
    default_config = project_root / "configs" / "distance" / "camera_params.json"
    default_output = project_root / "outputs" / "distance"

    # Load model
    model_path = Path(args.model) if args.model else default_model
    if not model_path.exists():
        print(f"[ERROR] Không tìm thấy model: {model_path}")
        sys.exit(1)

    print(f"Loading model: {model_path}")
    model = YOLO(str(model_path))

    # Khởi tạo estimator
    config_path = Path(args.config) if args.config else default_config
    if config_path.exists():
        print(f"Loading config: {config_path}")
        estimator = BBoxDistanceEstimator(config_path=config_path)
    else:
        print(f"Dùng focal_length mặc định: {args.focal_length}px")
        estimator = BBoxDistanceEstimator(focal_length_px=args.focal_length)

    # Output directory
    output_dir = Path(args.output_dir) if args.output_dir else default_output
    output_dir.mkdir(parents=True, exist_ok=True)

    # Calibration mode
    if args.calibrate:
        if not args.known_distance or not args.known_height:
            print("[ERROR] Cần --known-distance và --known-height cho calibration!")
            sys.exit(1)
        run_calibration(
            model=model,
            image_path=Path(args.source),
            known_distance=args.known_distance,
            known_height=args.known_height,
            known_class=args.known_class,
        )
        return

    # Xác định loại source
    source = args.source
    source_path = Path(source)

    if source.isdigit():
        # Webcam
        process_video(model, estimator, source, output_dir, args.show, args.conf)
    elif source_path.is_dir():
        # Thư mục ảnh
        process_directory(model, estimator, source_path, output_dir, args.max_images, args.conf)
    elif source_path.suffix.lower() in {".mp4", ".avi", ".mov", ".mkv"}:
        # Video
        process_video(model, estimator, source, output_dir, args.show, args.conf)
    elif source_path.is_file():
        # Ảnh đơn
        process_image(model, estimator, source_path, output_dir, args.show, args.conf)
    else:
        print(f"[ERROR] Không nhận dạng được source: {source}")
        sys.exit(1)


if __name__ == "__main__":
    main()
