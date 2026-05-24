"""
Convert Mapillary Vistas v2.0 Polygon JSON → YOLO Instance Segmentation format.

Đọc trực tiếp từ thư mục v2.0/polygons/ (không cần mask PNG),
lọc class theo selected_classes_old_quarter.json, normalize tọa độ,
và ghi ra data/yolo_seg/{train,val,test}/{images,labels}/.

Cách dùng:
    python scripts/train/convert_mapillary_to_yoloseg.py

Tùy chọn:
    --include-stuff     Bao gồm cả class stuff (road, sidewalk, curb)
    --limit N           Chỉ xử lý N ảnh đầu (để test nhanh)
    --dry-run           Chỉ in thống kê, không ghi file
    --min-area FLOAT    Bỏ qua polygon nhỏ hơn N pixel^2 (mặc định=50)
    --visualize N       Sau convert, vẽ overlay lên N ảnh đầu để kiểm tra
"""

import argparse
import json
import os
import shutil
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np

# ──────────────────────────────────────────────────────────────
# Các class trong selected_classes_old_quarter.json có instances: True
# Các class stuff (instances: False) sẽ bị bỏ qua nếu không có --include-stuff
# ──────────────────────────────────────────────────────────────

# Gộp các sub-class traffic light / sign thành 1 class để đủ sample
MERGE_GROUPS: Dict[str, str] = {
    "object--traffic-light--general-single": "traffic_light",
    "object--traffic-light--pedestrians": "traffic_light",
    "object--traffic-light--general-upright": "traffic_light",
    "object--traffic-light--general-horizontal": "traffic_light",
    "object--traffic-sign--front": "traffic_sign",
    "object--traffic-sign--direction-front": "traffic_sign",
    "object--traffic-sign--information-parking": "traffic_sign",
    "object--traffic-sign--temporary-front": "traffic_sign",
    "construction--barrier--other-barrier": "barrier",
    "construction--barrier--temporary": "barrier",
}

# Class thứ tự cố định (index = class_id)
INSTANCE_CLASSES: List[str] = [
    "human--person--individual",    # 0  person
    "human--rider--bicyclist",      # 1  bicyclist
    "human--rider--motorcyclist",   # 2  motorcyclist
    "object--vehicle--car",         # 3  car
    "object--vehicle--bus",         # 4  bus
    "object--vehicle--motorcycle",  # 5  motorcycle
    "construction--flat--crosswalk-plain",  # 6  crosswalk
    "object--support--pole",        # 7  pole
    "traffic_light",                # 8  (gộp)
    "traffic_sign",                 # 9  (gộp)
    "barrier",                      # 10 (gộp)
]

STUFF_CLASSES: List[str] = [
    "construction--flat--road",         # 11 road
    "construction--flat--sidewalk",     # 12 sidewalk
    "construction--barrier--curb",      # 13 curb
]

HUMAN_READABLE: Dict[str, str] = {
    "human--person--individual": "person",
    "human--rider--bicyclist": "bicyclist",
    "human--rider--motorcyclist": "motorcyclist",
    "object--vehicle--car": "car",
    "object--vehicle--bus": "bus",
    "object--vehicle--motorcycle": "motorcycle",
    "construction--flat--crosswalk-plain": "crosswalk",
    "object--support--pole": "pole",
    "traffic_light": "traffic_light",
    "traffic_sign": "traffic_sign",
    "barrier": "barrier",
    "construction--flat--road": "road",
    "construction--flat--sidewalk": "sidewalk",
    "construction--barrier--curb": "curb",
}


def load_config(config_path: Path) -> Dict:
    with open(config_path, "r", encoding="utf-8") as f:
        return json.load(f)


def build_label_info(config: Dict) -> Dict[str, Dict]:
    """Trả về dict {label_name: {"instances": bool}} từ config_v2.0."""
    return {
        label["name"]: {"instances": bool(label.get("instances", False))}
        for label in config["labels"]
    }


def polygon_area(polygon: List[List[float]]) -> float:
    """Tính diện tích polygon theo công thức Shoelace."""
    n = len(polygon)
    if n < 3:
        return 0.0
    area = 0.0
    for i in range(n):
        x1, y1 = polygon[i]
        x2, y2 = polygon[(i + 1) % n]
        area += x1 * y2 - x2 * y1
    return abs(area) / 2.0


def polygon_to_yolo(
    polygon: List[List[float]],
    width: int,
    height: int,
) -> List[float]:
    """Normalize tọa độ [x,y] tuyệt đối → [0,1] và trả về danh sách phẳng."""
    coords = []
    for (x, y) in polygon:
        coords.append(round(max(0.0, min(1.0, x / width)), 6))
        coords.append(round(max(0.0, min(1.0, y / height)), 6))
    return coords


def resolve_label(label_name: str, label_info: Dict[str, Dict]) -> Optional[str]:
    """
    Trả về tên class đã được gộp (hoặc giữ nguyên), hay None nếu không trong selected.
    """
    # Nếu là sub-class được gộp → trả về tên gộp
    if label_name in MERGE_GROUPS:
        return MERGE_GROUPS[label_name]
    return label_name


def process_split(
    data_root: Path,
    split: str,
    mapillary_split: str,
    output_root: Path,
    class_to_id: Dict[str, int],
    label_info: Dict[str, Dict],
    min_area: float,
    limit: Optional[int],
    dry_run: bool,
    include_stuff: bool,
) -> Dict[str, int]:
    """Xử lý 1 split (training/validation/testing)."""
    polygon_dir = data_root / mapillary_split / "v2.0" / "polygons"
    image_dir = data_root / mapillary_split / "images"

    out_img_dir = output_root / split / "images"
    out_lbl_dir = output_root / split / "labels"
    if not dry_run:
        out_img_dir.mkdir(parents=True, exist_ok=True)
        out_lbl_dir.mkdir(parents=True, exist_ok=True)

    json_files = sorted(polygon_dir.glob("*.json"))
    if limit:
        json_files = json_files[:limit]

    stats: Dict[str, int] = {
        "images": 0, "objects_total": 0, "objects_kept": 0,
        "objects_skipped_class": 0, "objects_skipped_area": 0,
        "objects_skipped_stuff": 0,
    }

    for json_path in json_files:
        img_id = json_path.stem
        img_path = image_dir / f"{img_id}.jpg"

        if not img_path.exists():
            continue

        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        W = data.get("width", 1)
        H = data.get("height", 1)
        objects = data.get("objects", [])

        lines: List[str] = []

        for obj in objects:
            label_name: str = obj.get("label", "")
            polygon: List = obj.get("polygon", [])
            stats["objects_total"] += 1

            if len(polygon) < 3:
                stats["objects_skipped_area"] += 1
                continue

            # Resolve tên class (gộp nếu cần)
            resolved = resolve_label(label_name, label_info)

            # Lọc theo class được chọn
            if resolved not in class_to_id:
                stats["objects_skipped_class"] += 1
                continue

            # Kiểm tra stuff
            info = label_info.get(label_name)
            if info and not info["instances"] and not include_stuff:
                stats["objects_skipped_stuff"] += 1
                continue

            # Lọc polygon quá nhỏ
            area = polygon_area(polygon)
            if area < min_area:
                stats["objects_skipped_area"] += 1
                continue

            class_id = class_to_id[resolved]
            coords = polygon_to_yolo(polygon, W, H)
            line = f"{class_id} " + " ".join(f"{v:.6f}" for v in coords)
            lines.append(line)
            stats["objects_kept"] += 1

        if not dry_run:
            # Copy ảnh
            shutil.copy2(img_path, out_img_dir / img_path.name)
            # Ghi label (dù rỗng vẫn ghi để YOLO không báo lỗi thiếu file)
            label_file = out_lbl_dir / f"{img_id}.txt"
            with open(label_file, "w", encoding="utf-8") as lf:
                lf.write("\n".join(lines))

        stats["images"] += 1

    return stats


def visualize_samples(
    output_root: Path,
    split: str,
    class_names: List[str],
    n: int,
):
    """Overlay polygon lên n ảnh đầu rồi lưu vào output_root/visual/."""
    try:
        import cv2
    except ImportError:
        print("  [WARN] cv2 không có sẵn, bỏ qua visualization.")
        return

    visual_dir = output_root / "visual" / split
    visual_dir.mkdir(parents=True, exist_ok=True)

    img_dir = output_root / split / "images"
    lbl_dir = output_root / split / "labels"

    img_files = sorted(img_dir.glob("*.jpg"))[:n]
    COLORS = [
        (255, 56, 56), (255, 157, 151), (255, 112, 31), (255, 178, 29),
        (207, 210, 49), (72, 249, 10), (146, 204, 23), (61, 219, 134),
        (26, 147, 52), (0, 212, 187), (44, 153, 168), (0, 194, 255),
        (52, 69, 147), (100, 115, 255), (0, 24, 236),
    ]

    for img_path in img_files:
        img = cv2.imread(str(img_path))
        if img is None:
            continue
        H, W = img.shape[:2]
        lbl_path = lbl_dir / f"{img_path.stem}.txt"
        if not lbl_path.exists():
            continue
        with open(lbl_path, "r") as f:
            lines = [l.strip() for l in f if l.strip()]
        for line in lines:
            parts = line.split()
            cid = int(parts[0])
            coords = list(map(float, parts[1:]))
            pts = np.array(
                [[int(coords[i] * W), int(coords[i+1] * H)] for i in range(0, len(coords), 2)],
                dtype=np.int32,
            )
            color = COLORS[cid % len(COLORS)]
            overlay = img.copy()
            cv2.fillPoly(overlay, [pts], color)
            img = cv2.addWeighted(overlay, 0.35, img, 0.65, 0)
            cv2.polylines(img, [pts], isClosed=True, color=color, thickness=2)
            if len(pts) > 0:
                cx, cy = pts.mean(axis=0).astype(int)
                label_str = class_names[cid] if cid < len(class_names) else str(cid)
                cv2.putText(img, label_str, (cx, cy), cv2.FONT_HERSHEY_SIMPLEX,
                            0.5, (255, 255, 255), 1, cv2.LINE_AA)
        out_path = visual_dir / img_path.name
        cv2.imwrite(str(out_path), img)
        print(f"  Saved visual: {out_path}")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Convert Mapillary v2.0 polygons → YOLO Instance Segmentation"
    )
    parser.add_argument(
        "--data-root", type=str,
        default="D:/VIET/DATN/data/raw/mapillary",
        help="Thư mục gốc của Mapillary raw data",
    )
    parser.add_argument(
        "--config", type=str,
        default="D:/VIET/DATN/configs/mapillary/config_v2.0.json",
    )
    parser.add_argument(
        "--output-dir", type=str,
        default="D:/VIET/DATN/data/yolo_seg",
        help="Thư mục đầu ra (sẽ tạo train/val/test bên trong)",
    )
    parser.add_argument(
        "--include-stuff", action="store_true",
        help="Bao gồm class stuff (road, sidewalk, curb). Mặc định: chỉ lấy instances",
    )
    parser.add_argument(
        "--limit", type=int, default=None,
        help="Giới hạn số ảnh mỗi split (để test nhanh)",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Chỉ in thống kê, không ghi file",
    )
    parser.add_argument(
        "--min-area", type=float, default=50.0,
        help="Diện tích pixel tối thiểu của polygon (mặc định 50)",
    )
    parser.add_argument(
        "--visualize", type=int, default=0,
        help="Sau convert, tạo ảnh overlay cho N ảnh đầu của mỗi split",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    data_root = Path(args.data_root)
    output_root = Path(args.output_dir)

    config = load_config(Path(args.config))
    label_info = build_label_info(config)

    # Xây dựng danh sách class cuối cùng
    all_classes = INSTANCE_CLASSES + (STUFF_CLASSES if args.include_stuff else [])

    # Kiểm tra class nào không tồn tại trong config
    all_mapillary_labels = set(label_info.keys())
    merged_targets = set(MERGE_GROUPS.values())
    for cls in all_classes:
        if cls in merged_targets:
            continue  # class gộp, không cần check trực tiếp
        if cls not in all_mapillary_labels:
            print(f"  [WARN] Class không có trong config_v2.0.json: '{cls}' — bỏ qua.")

    class_to_id: Dict[str, int] = {cls: idx for idx, cls in enumerate(all_classes)}
    class_names: List[str] = [HUMAN_READABLE.get(c, c) for c in all_classes]

    print("=" * 65)
    print("Mapillary v2.0 → YOLO Instance Segmentation Converter")
    print("=" * 65)
    print(f"Data root    : {data_root}")
    print(f"Output dir   : {output_root}")
    print(f"Include stuff: {args.include_stuff}")
    print(f"Min area     : {args.min_area} px²")
    print(f"Dry run      : {args.dry_run}")
    if args.limit:
        print(f"Limit        : {args.limit} ảnh/split")
    print(f"\nClasses ({len(all_classes)}):")
    for idx, (cls, readable) in enumerate(zip(all_classes, class_names)):
        print(f"  {idx:2d}: {readable} ({cls})")
    print()

    # Ghi file class names để tham chiếu sau
    if not args.dry_run:
        output_root.mkdir(parents=True, exist_ok=True)
        classes_file = output_root / "classes.txt"
        with open(classes_file, "w", encoding="utf-8") as f:
            f.write("\n".join(class_names))
        print(f"Saved class list: {classes_file}\n")

    SPLITS = [
        ("train", "training"),
        ("val",   "validation"),
        ("test",  "testing"),
    ]

    for split, mapillary_split in SPLITS:
        print(f"[{split.upper()}] Processing {mapillary_split}...")
        stats = process_split(
            data_root=data_root,
            split=split,
            mapillary_split=mapillary_split,
            output_root=output_root,
            class_to_id=class_to_id,
            label_info=label_info,
            min_area=args.min_area,
            limit=args.limit,
            dry_run=args.dry_run,
            include_stuff=args.include_stuff,
        )
        print(f"  Ảnh xử lý      : {stats['images']}")
        print(f"  Objects tổng   : {stats['objects_total']}")
        print(f"  Objects giữ lại: {stats['objects_kept']}")
        print(f"  Bỏ (class)     : {stats['objects_skipped_class']}")
        print(f"  Bỏ (stuff)     : {stats['objects_skipped_stuff']}")
        print(f"  Bỏ (area nhỏ) : {stats['objects_skipped_area']}")

        if args.visualize > 0 and not args.dry_run:
            print(f"  Generating {args.visualize} visualization(s)...")
            visualize_samples(output_root, split, class_names, args.visualize)

        print()

    print("=" * 65)
    print("Hoàn thành!" if not args.dry_run else "Dry-run hoàn thành (không ghi file).")
    print("=" * 65)


if __name__ == "__main__":
    main()
