"""
Train YOLOv11-seg (Instance Segmentation) trên tập Mapillary đã convert bởi
convert_mapillary_to_yoloseg.py.

Cách dùng:
    # Round 1 - train từ pretrained YOLOv11s-seg (mặc định)
    python scripts/train/train_yolo_v11_seg.py

    # Round 1 với model medium (nếu GPU đủ VRAM >= 8GB)
    python scripts/train/train_yolo_v11_seg.py --model-size m

    # Round 2 - fine-tune từ checkpoint round 1
    python scripts/train/train_yolo_v11_seg.py \\
        --init-model D:/VIET/DATN/outputs/runs_seg/yolo11seg_mapillary_r1/weights/best.pt \\
        --run-name yolo11seg_mapillary_r2 \\
        --epochs 100 --lr0 0.0005

    # Fine-tune trên ảnh phố cổ thực tế
    python scripts/train/train_yolo_v11_seg.py \\
        --data-dir D:/VIET/DATN/data/yolo_seg_oldquarter \\
        --init-model D:/VIET/DATN/outputs/runs_seg/yolo11seg_mapillary_r2/weights/best.pt \\
        --run-name yolo11seg_oldquarter_finetune \\
        --epochs 50 --lr0 0.0003

    # Resume training nếu bị gián đoạn
    python scripts/train/train_yolo_v11_seg.py --resume \\
        --init-model D:/VIET/DATN/outputs/runs_seg/yolo11seg_mapillary_r1/weights/last.pt
"""

import argparse
from pathlib import Path
from typing import List, Optional

import yaml
from ultralytics import YOLO


def load_class_names(classes_file: Path) -> List[str]:
    """Đọc file classes.txt (mỗi dòng 1 tên class)."""
    with open(classes_file, "r", encoding="utf-8") as f:
        names = [line.strip() for line in f if line.strip()]
    return names


def create_dataset_yaml(
    dataset_root: Path,
    output_yaml: Path,
    class_names: List[str],
    task: str = "segment",
):
    """Tạo YOLO dataset.yaml cho bài toán segmentation."""
    config = {
        "path": str(dataset_root.resolve()),
        "train": "train/images",
        "val": "val/images",
        "test": "test/images",
        "nc": len(class_names),
        "names": {i: name for i, name in enumerate(class_names)},
        "task": task,
    }
    with open(output_yaml, "w", encoding="utf-8") as f:
        yaml.dump(config, f, default_flow_style=False, allow_unicode=True)
    print(f"Dataset YAML: {output_yaml}", flush=True)
    return config


def parse_args():
    parser = argparse.ArgumentParser(
        description="Train YOLOv11 Instance Segmentation trên Mapillary"
    )
    parser.add_argument(
        "--data-dir", type=str,
        default="D:/VIET/DATN/data/yolo_seg",
        help="Thư mục chứa train/val/test + classes.txt",
    )
    parser.add_argument(
        "--init-model", type=str,
        default=None,
        help="Đường dẫn đến file .pt. Mặc định tự động tải yolo11s-seg.pt từ Ultralytics.",
    )
    parser.add_argument(
        "--model-size", type=str,
        default="s",
        choices=["n", "s", "m", "l", "x"],
        help="Kích thước model (nano/small/medium/large/xlarge). Dùng khi không chỉ --init-model.",
    )
    parser.add_argument("--epochs", type=int, default=150)
    parser.add_argument("--batch-size", type=int, default=8)
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument(
        "--output-dir", type=str,
        default="D:/VIET/DATN/outputs/runs_seg",
    )
    parser.add_argument(
        "--run-name", type=str,
        default="yolo11seg_mapillary_r1",
    )
    # Hyperparameters
    parser.add_argument("--lr0", type=float, default=0.001,
                        help="Learning rate ban đầu (0.001 phù hợp AdamW)")
    parser.add_argument("--lrf", type=float, default=0.01,
                        help="Learning rate cuối = lr0 * lrf")
    parser.add_argument("--weight-decay", type=float, default=0.0005)
    parser.add_argument("--warmup-epochs", type=int, default=5,
                        help="Số epoch warmup (tăng dần lr)")
    parser.add_argument("--patience", type=int, default=30,
                        help="Early stopping patience (epochs)")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--device", type=str, default="0",
                        help="GPU device (mặc định GPU 0). Dùng 'cpu' nếu không có GPU.")
    parser.add_argument("--resume", action="store_true",
                        help="Resume training từ --init-model (phải trỏ vào last.pt)")
    # Augmentation
    parser.add_argument("--mosaic", type=float, default=1.0)
    parser.add_argument("--mixup", type=float, default=0.15,
                        help="MixUp augmentation probability")
    parser.add_argument("--copy-paste", type=float, default=0.1,
                        help="Copy-Paste augmentation (tốt cho segmentation)")
    parser.add_argument("--close-mosaic", type=int, default=15,
                        help="Tắt mosaic ở N epoch cuối")

    return parser.parse_args()


def main():
    args = parse_args()

    data_dir = Path(args.data_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Load class names
    classes_file = data_dir / "classes.txt"
    if not classes_file.exists():
        raise FileNotFoundError(
            f"Không tìm thấy {classes_file}. Hãy chạy convert_mapillary_to_yoloseg.py trước."
        )
    class_names = load_class_names(classes_file)

    print("=" * 70, flush=True)
    print("YOLOv11 Instance Segmentation — Mapillary Training", flush=True)
    print("=" * 70, flush=True)
    print(f"Data dir    : {data_dir}", flush=True)
    print(f"Output dir  : {output_dir / args.run_name}", flush=True)
    print(f"Classes ({len(class_names)}): {class_names}", flush=True)
    print(f"Epochs      : {args.epochs}", flush=True)
    print(f"Batch size  : {args.batch_size}", flush=True)
    print(f"Image size  : {args.imgsz}", flush=True)
    print(f"Device      : {args.device}", flush=True)

    # Tạo dataset YAML
    dataset_yaml = output_dir / f"dataset_{args.run_name}.yaml"
    create_dataset_yaml(data_dir, dataset_yaml, class_names, task="segment")

    # Resume training
    if args.resume:
        if not args.init_model:
            raise ValueError("--resume cần đi kèm --init-model trỏ đến last.pt")
        print(f"\nResuming training từ: {args.init_model}", flush=True)
        model = YOLO(args.init_model)
        model.train(resume=True)
        return

    # Load model
    if args.init_model:
        print(f"\nLoading checkpoint: {args.init_model}", flush=True)
        model = YOLO(args.init_model)
    else:
        model_name = f"yolo11{args.model_size}-seg.pt"
        print(f"\nLoading pretrained model: {model_name}", flush=True)
        model = YOLO(model_name)

    print(f"\nModel size: YOLO11{args.model_size}-seg", flush=True)
    print("\nStarting training...", flush=True)
    print("=" * 70, flush=True)

    model.train(
        data=str(dataset_yaml),
        task="segment",
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=args.batch_size,
        device=args.device,
        project=str(output_dir),
        name=args.run_name,
        # Optimizer — AdamW với lr thấp hơn SGD cho kết quả ổn định hơn
        optimizer="AdamW",
        lr0=args.lr0,
        lrf=args.lrf,
        weight_decay=args.weight_decay,
        warmup_epochs=args.warmup_epochs,
        cos_lr=True,
        # Early stopping — patience 30 để model có đủ thời gian hội tụ
        patience=args.patience,
        # Augmentation — tăng cường đa dạng dữ liệu
        mosaic=args.mosaic,
        mixup=args.mixup,
        copy_paste=args.copy_paste,
        close_mosaic=args.close_mosaic,
        hsv_h=0.015,
        hsv_s=0.7,
        hsv_v=0.4,
        degrees=5.0,
        translate=0.15,
        scale=0.5,
        shear=2.0,
        fliplr=0.5,
        erasing=0.1,
        # Checkpointing
        save=True,
        save_period=10,
        verbose=True,
        workers=args.workers,
    )

    best_ckpt = output_dir / args.run_name / "weights" / "best.pt"
    print("\n" + "=" * 70, flush=True)
    print("Training hoàn tất!", flush=True)
    print(f"Best checkpoint : {best_ckpt}", flush=True)
    print(f"Kết quả         : {output_dir / args.run_name}", flush=True)
    print("=" * 70, flush=True)


if __name__ == "__main__":
    main()
