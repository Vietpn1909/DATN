"""
So sánh BBox-based vs Mask-based Distance Estimation
=====================================================
Chạy cả 2 phương pháp trên cùng tập ảnh test, so sánh kết quả.

Cách dùng:
    python scripts/distance/compare_methods.py \
        --source data/yolo_seg_oldquarter/test/images/ \
        --max-images 20

Output:
    - Bảng so sánh khoảng cách từng detection
    - Thống kê chênh lệch theo class
    - Ảnh side-by-side lưu vào outputs/distance_compare/
"""

from __future__ import annotations

import sys
import argparse
from pathlib import Path
from collections import defaultdict

sys.stdout.reconfigure(encoding="utf-8")

import cv2
import numpy as np
from ultralytics import YOLO

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))
from scripts.distance.bbox_distance import BBoxDistanceEstimator, CLASS_NAMES
from scripts.distance.mask_distance import MaskDistanceEstimator


# ============================================================
# Visualization
# ============================================================

WARNING_COLORS = {
    "close": (0, 0, 255),
    "medium": (0, 165, 255),
    "far": (0, 255, 0),
    "unknown": (128, 128, 128),
}


def draw_result_on_frame(
    frame: np.ndarray,
    detections: list,
    method_name: str,
) -> np.ndarray:
    """Vẽ detections lên frame với tên phương pháp."""
    # Tiêu đề
    cv2.putText(
        frame, method_name,
        (10, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2,
    )

    for det in detections:
        x1, y1, x2, y2 = [int(v) for v in det.bbox]
        color = WARNING_COLORS.get(det.warning_level, (128, 128, 128))
        thickness = 3 if det.warning_level == "close" else 2
        cv2.rectangle(frame, (x1, y1), (x2, y2), color, thickness)

        # Label
        if det.distance_m > 0:
            label = f"{det.class_name} {det.distance_m:.1f}m"
        else:
            label = f"{det.class_name} ??m"

        font = cv2.FONT_HERSHEY_SIMPLEX
        (tw, th), _ = cv2.getTextSize(label, font, 0.5, 1)
        cv2.rectangle(frame, (x1, y1 - th - 8), (x1 + tw + 4, y1), color, -1)
        cv2.putText(frame, label, (x1 + 2, y1 - 4), font, 0.5, (255, 255, 255), 1)

    return frame


# ============================================================
# Comparison logic
# ============================================================

def compare_on_images(
    model: YOLO,
    bbox_estimator: BBoxDistanceEstimator,
    mask_estimator: MaskDistanceEstimator,
    image_dir: Path,
    output_dir: Path,
    max_images: int = 20,
    conf_threshold: float = 0.3,
) -> None:
    """Chạy cả 2 phương pháp và so sánh."""
    extensions = {".jpg", ".jpeg", ".png", ".bmp"}
    images = sorted([f for f in image_dir.iterdir() if f.suffix.lower() in extensions])

    if not images:
        print(f"[ERROR] Không tìm thấy ảnh trong: {image_dir}")
        return

    if len(images) > max_images:
        rng = np.random.default_rng(42)
        indices = rng.choice(len(images), size=max_images, replace=False)
        images = [images[i] for i in sorted(indices)]

    print(f"So sánh BBox vs Mask trên {len(images)} ảnh...\n")

    # Thu thập dữ liệu so sánh
    all_comparisons: list[dict] = []

    for img_path in images:
        frame = cv2.imread(str(img_path))
        if frame is None:
            continue

        # YOLO inference (1 lần duy nhất)
        results = model(frame, conf=conf_threshold, verbose=False)
        result = results[0]

        if result.boxes is None or len(result.boxes) == 0:
            continue

        # Chạy cả 2 phương pháp
        bbox_result = bbox_estimator.process_yolo_result(result, conf_threshold)
        mask_result = mask_estimator.process_yolo_result(result, conf_threshold)

        # Ghép cặp detections (cùng index)
        n = min(len(bbox_result.detections), len(mask_result.detections))

        # Sắp xếp lại theo class_id + bbox position để ghép đúng cặp
        bbox_dets = sorted(bbox_result.detections, key=lambda d: (d.class_id, d.bbox[0], d.bbox[1]))
        mask_dets = sorted(mask_result.detections, key=lambda d: (d.class_id, d.bbox[0], d.bbox[1]))

        for i in range(min(len(bbox_dets), len(mask_dets))):
            bd = bbox_dets[i]
            md = mask_dets[i]

            # Chỉ so sánh nếu cùng class và cùng vật (bbox gần nhau)
            if bd.class_id != md.class_id:
                continue

            if bd.distance_m > 0 and md.distance_m > 0:
                diff = md.distance_m - bd.distance_m
                diff_pct = (diff / bd.distance_m) * 100 if bd.distance_m != 0 else 0

                all_comparisons.append({
                    "image": img_path.name,
                    "class": bd.class_name,
                    "class_id": bd.class_id,
                    "bbox_dist": bd.distance_m,
                    "mask_dist": md.distance_m,
                    "diff": diff,
                    "diff_pct": diff_pct,
                    "bbox_level": bd.warning_level,
                    "mask_level": md.warning_level,
                    "level_match": bd.warning_level == md.warning_level,
                })

        # Tạo ảnh side-by-side
        frame_bbox = frame.copy()
        frame_mask = frame.copy()
        draw_result_on_frame(frame_bbox, bbox_result.detections, "BBox-based")
        draw_result_on_frame(frame_mask, mask_result.detections, "Mask-based")

        # Ghép ngang
        combined = np.hstack([frame_bbox, frame_mask])
        output_path = output_dir / f"cmp_{img_path.name}"
        cv2.imwrite(str(output_path), combined)

    # ============================================================
    # In kết quả so sánh
    # ============================================================
    print(f"{'='*80}")
    print(f"KẾT QUẢ SO SÁNH: BBox-based vs Mask-based")
    print(f"{'='*80}")
    print(f"Tổng cặp so sánh: {len(all_comparisons)}")

    if not all_comparisons:
        print("Không có dữ liệu so sánh!")
        return

    # Tổng quan
    diffs = [c["diff"] for c in all_comparisons]
    diffs_abs = [abs(d) for d in diffs]
    diffs_pct = [c["diff_pct"] for c in all_comparisons]
    level_matches = [c["level_match"] for c in all_comparisons]

    print(f"\n--- TỔNG QUAN ---")
    print(f"Chênh lệch trung bình (Mask - BBox): {np.mean(diffs):+.2f}m")
    print(f"Chênh lệch tuyệt đối trung bình:     {np.mean(diffs_abs):.2f}m")
    print(f"Chênh lệch % trung bình:              {np.mean(diffs_pct):+.1f}%")
    print(f"Chênh lệch tuyệt đối max:             {np.max(diffs_abs):.2f}m")
    print(f"Tỷ lệ cùng mức cảnh báo:              {sum(level_matches)}/{len(level_matches)} "
          f"({sum(level_matches)/len(level_matches)*100:.1f}%)")

    # Phân phối chênh lệch
    small = sum(1 for d in diffs_abs if d < 1.0)
    medium = sum(1 for d in diffs_abs if 1.0 <= d < 3.0)
    large = sum(1 for d in diffs_abs if d >= 3.0)
    print(f"\nPhân phối chênh lệch:")
    print(f"  < 1m:  {small:3d} ({small/len(diffs_abs)*100:.1f}%)")
    print(f"  1-3m:  {medium:3d} ({medium/len(diffs_abs)*100:.1f}%)")
    print(f"  > 3m:  {large:3d} ({large/len(diffs_abs)*100:.1f}%)")

    # Theo class
    print(f"\n--- THEO CLASS ---")
    print(f"{'Class':20s} | {'N':>4s} | {'BBox avg':>8s} | {'Mask avg':>8s} | {'Diff avg':>9s} | {'Match%':>6s}")
    print(f"{'-'*20}-+-{'-'*4}-+-{'-'*8}-+-{'-'*8}-+-{'-'*9}-+-{'-'*6}")

    class_groups = defaultdict(list)
    for c in all_comparisons:
        class_groups[c["class"]].append(c)

    for cls_name in sorted(class_groups.keys()):
        items = class_groups[cls_name]
        n = len(items)
        avg_bbox = np.mean([c["bbox_dist"] for c in items])
        avg_mask = np.mean([c["mask_dist"] for c in items])
        avg_diff = np.mean([c["diff"] for c in items])
        match_rate = sum(1 for c in items if c["level_match"]) / n * 100

        print(f"{cls_name:20s} | {n:4d} | {avg_bbox:7.1f}m | {avg_mask:7.1f}m | {avg_diff:+8.2f}m | {match_rate:5.1f}%")

    # Mức cảnh báo bị khác
    mismatches = [c for c in all_comparisons if not c["level_match"]]
    if mismatches:
        print(f"\n--- CẢNH BÁO: {len(mismatches)} detection khác mức cảnh báo ---")
        for c in mismatches[:10]:  # Hiện tối đa 10
            print(f"  {c['class']:15s} | BBox: {c['bbox_dist']:.1f}m ({c['bbox_level']}) "
                  f"vs Mask: {c['mask_dist']:.1f}m ({c['mask_level']}) | {c['image']}")

    # Kết luận
    print(f"\n{'='*80}")
    print("KẾT LUẬN:")
    avg_abs_diff = np.mean(diffs_abs)
    match_rate = sum(level_matches) / len(level_matches) * 100

    if avg_abs_diff < 1.5 and match_rate > 80:
        print("  -> Hai phương pháp cho kết quả TƯƠNG ĐỒNG.")
        print("  -> BBox-based đủ tốt cho ứng dụng, nên dùng vì đơn giản và nhanh hơn.")
    elif avg_abs_diff < 3.0:
        print("  -> Có chênh lệch TRUNG BÌNH giữa 2 phương pháp.")
        print("  -> Cân nhắc dùng BBox cho mobile (nhanh) và Mask cho phân tích chi tiết.")
    else:
        print("  -> Chênh lệch LỚN giữa 2 phương pháp.")
        print("  -> Cần calibrate lại tham số hoặc kiểm tra chất lượng mask.")

    print(f"\nẢnh side-by-side đã lưu tại: {output_dir}")


# ============================================================
# Main
# ============================================================

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="So sánh BBox vs Mask distance estimation")
    parser.add_argument("--source", type=str, required=True, help="Thư mục ảnh test")
    parser.add_argument("--model", type=str, default=None, help="Đường dẫn model YOLO (.pt)")
    parser.add_argument("--config", type=str, default=None, help="Đường dẫn camera_params.json")
    parser.add_argument("--max-images", type=int, default=20, help="Số ảnh tối đa (default: 20)")
    parser.add_argument("--conf", type=float, default=0.3, help="Confidence threshold (default: 0.3)")
    parser.add_argument("--output-dir", type=str, default=None, help="Thư mục lưu kết quả")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    project_root = Path(__file__).resolve().parent.parent.parent
    default_model = project_root / "outputs" / "runs_seg" / "yolo11seg_oldquarter_finetune" / "weights" / "best.pt"
    default_config = project_root / "configs" / "distance" / "camera_params.json"
    default_output = project_root / "outputs" / "distance_compare"

    # Load model
    model_path = Path(args.model) if args.model else default_model
    print(f"Loading model: {model_path}")
    model = YOLO(str(model_path))

    # Khởi tạo cả 2 estimator
    config_path = Path(args.config) if args.config else default_config

    if config_path.exists():
        bbox_est = BBoxDistanceEstimator(config_path=config_path)
        mask_est = MaskDistanceEstimator(config_path=config_path)
        print(f"Loaded config: {config_path}")
    else:
        bbox_est = BBoxDistanceEstimator()
        mask_est = MaskDistanceEstimator()
        print("Dùng tham số mặc định")

    # Output
    output_dir = Path(args.output_dir) if args.output_dir else default_output
    output_dir.mkdir(parents=True, exist_ok=True)

    # Chạy so sánh
    compare_on_images(
        model=model,
        bbox_estimator=bbox_est,
        mask_estimator=mask_est,
        image_dir=Path(args.source),
        output_dir=output_dir,
        max_images=args.max_images,
        conf_threshold=args.conf,
    )


if __name__ == "__main__":
    main()
