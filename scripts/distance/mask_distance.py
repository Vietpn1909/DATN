"""
Mask-based Distance Estimation Module
=======================================
Ước tính khoảng cách đến vật cản dựa trên diện tích segmentation mask.

Nguyên lý:
    Diện tích mask (pixel) tỷ lệ nghịch với bình phương khoảng cách:
        mask_area ∝ 1 / distance²
    => distance = k / sqrt(mask_area_px)
    Trong đó k là hệ số calibrate cho từng class, phụ thuộc:
        - Diện tích thực của vật thể
        - Focal length camera
        - Góc nhìn trung bình

So với BBox-based:
    - Chính xác hơn khi vật bị che khuất (mask co lại đúng phần bị che)
    - Nhưng phụ thuộc chất lượng mask từ model
    - Calibrate phức tạp hơn (phi tuyến: 1/d²)
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import numpy as np

from scripts.distance.bbox_distance import (
    CLASS_NAMES,
    CLASS_NAMES_VI,
    CLOSE_THRESHOLD,
    MEDIUM_THRESHOLD,
    DEFAULT_FOCAL_LENGTH_PX,
    DEFAULT_IMAGE_SIZE,
    DetectionWithDistance,
    FrameDistanceResult,
)


# ============================================================
# Hệ số K mặc định cho từng class
# ============================================================
# k = sqrt(real_area_m2) * focal_length_px
# real_area_m2: diện tích mặt cắt trung bình nhìn từ phía trước
# Công thức: distance = k / sqrt(mask_area_px)
#
# Cách tính real_area_m2 xấp xỉ:
#   person: 1.65m x 0.45m = 0.74 m²
#   bicyclist: 1.70m x 0.60m = 1.02 m²
#   motorcyclist: 1.60m x 0.60m = 0.96 m²
#   car: 1.50m x 1.80m = 2.70 m²
#   bus: 3.00m x 2.50m = 7.50 m²
#   motorcycle: 1.10m x 0.60m = 0.66 m²
#   crosswalk: phẳng trên mặt đất -> xử lý riêng
#   pole: 2.50m x 0.15m = 0.375 m²
#   traffic_light: 0.60m x 0.30m = 0.18 m²
#   traffic_sign: 0.60m x 0.60m = 0.36 m²
#   barrier: 0.90m x 1.20m = 1.08 m²

DEFAULT_REAL_AREAS: dict[int, float] = {
    0: 0.74,    # person
    1: 1.02,    # bicyclist
    2: 0.96,    # motorcyclist
    3: 2.70,    # car
    4: 7.50,    # bus
    5: 0.66,    # motorcycle
    6: 0.0,     # crosswalk (xử lý riêng)
    7: 0.375,   # pole
    8: 0.18,    # traffic_light
    9: 0.36,    # traffic_sign
    10: 1.08,   # barrier
}


# ============================================================
# Main class
# ============================================================

class MaskDistanceEstimator:
    """
    Ước tính khoảng cách dựa trên diện tích segmentation mask.

    Công thức:
        distance = k / sqrt(mask_area_px)
        k = sqrt(real_area_m2) * focal_length_px

    Ưu điểm so với BBox:
        - Vật bị che khuất -> mask nhỏ đúng phần bị che -> ước tính tốt hơn
        - Không bị ảnh hưởng bởi khoảng trống trong bbox

    Nhược điểm:
        - Phụ thuộc chất lượng mask (răng cưa, lỗ hổng)
        - Calibrate phức tạp hơn (tỷ lệ 1/d², phi tuyến)
        - Cùng vật, góc nhìn khác nhau -> mask area thay đổi nhiều
    """

    # Ưu tiên cảnh báo (giống BBox)
    PRIORITY: dict[int, int] = {
        0: 10, 2: 9, 1: 8, 3: 7, 4: 7,
        5: 6, 10: 5, 7: 4, 6: 3, 8: 2, 9: 2,
    }

    def __init__(
        self,
        focal_length_px: float = DEFAULT_FOCAL_LENGTH_PX,
        image_size: int = DEFAULT_IMAGE_SIZE,
        real_areas: Optional[dict[int, float]] = None,
        close_threshold: float = CLOSE_THRESHOLD,
        medium_threshold: float = MEDIUM_THRESHOLD,
        config_path: Optional[Path] = None,
    ) -> None:
        """
        Khởi tạo Mask Distance Estimator.

        Args:
            focal_length_px: Tiêu cự camera (pixel)
            image_size: Kích thước ảnh YOLO (640)
            real_areas: Dict {class_id: diện tích thực mặt cắt (m²)}
            close_threshold: Ngưỡng gần (m)
            medium_threshold: Ngưỡng trung bình (m)
            config_path: File camera_params.json
        """
        if config_path and config_path.exists():
            self._load_config(config_path)
        else:
            self.focal_length_px = focal_length_px
            self.image_size = image_size
            self.close_threshold = close_threshold
            self.medium_threshold = medium_threshold

        self.real_areas = real_areas or DEFAULT_REAL_AREAS.copy()

        # Tính trước hệ số k cho mỗi class
        self.k_factors: dict[int, float] = {}
        for cls_id, area in self.real_areas.items():
            if area > 0:
                self.k_factors[cls_id] = np.sqrt(area) * self.focal_length_px

    def _load_config(self, config_path: Path) -> None:
        """Load tham số từ camera_params.json."""
        with open(config_path, encoding="utf-8") as f:
            config = json.load(f)

        default = config.get("default", {})
        self.focal_length_px = default.get("focal_length_px", DEFAULT_FOCAL_LENGTH_PX)
        self.image_size = default.get("image_width", DEFAULT_IMAGE_SIZE)

        thresholds = config.get("warning_thresholds_m", {})
        self.close_threshold = thresholds.get("close", CLOSE_THRESHOLD)
        self.medium_threshold = thresholds.get("medium", MEDIUM_THRESHOLD)

    def estimate_distance(
        self,
        class_id: int,
        mask: np.ndarray,
    ) -> float:
        """
        Ước tính khoảng cách từ diện tích mask.

        Args:
            class_id: ID class (0-10)
            mask: Binary mask array (H, W) với giá trị 0/1

        Returns:
            Khoảng cách (mét). -1.0 nếu không ước tính được.
        """
        # Crosswalk: nằm trên mặt đất, không dùng mask area
        if class_id == 6:
            return self._estimate_crosswalk_from_mask(mask)

        k = self.k_factors.get(class_id)
        if k is None or k <= 0:
            return -1.0

        mask_area = float(np.sum(mask > 0))
        if mask_area < 20:  # Mask quá nhỏ, không đáng tin
            return -1.0

        distance = k / np.sqrt(mask_area)
        return round(float(distance), 2)

    def _estimate_crosswalk_from_mask(self, mask: np.ndarray) -> float:
        """
        Ước tính khoảng cách crosswalk dựa vào vị trí mask trong ảnh.
        Mask càng ở phía dưới ảnh -> càng gần camera.
        """
        ys = np.where(mask > 0)[0]
        if len(ys) == 0:
            return -1.0

        # Lấy vị trí trung bình theo chiều dọc (y)
        # y càng lớn (gần đáy ảnh) -> càng gần
        y_center = float(np.mean(ys))
        y_max = mask.shape[0]

        # Mapping tuyến tính đơn giản: đáy ảnh = 1m, đỉnh ảnh = 15m
        ratio = 1.0 - (y_center / y_max)  # 0 = đáy, 1 = đỉnh
        distance = 1.0 + ratio * 14.0  # 1m -> 15m
        return round(distance, 2)

    def get_warning_level(self, distance_m: float) -> str:
        """Xác định mức cảnh báo."""
        if distance_m < 0:
            return "unknown"
        if distance_m < self.close_threshold:
            return "close"
        if distance_m < self.medium_threshold:
            return "medium"
        return "far"

    def format_warning_vi(
        self,
        class_id: int,
        distance_m: float,
        warning_level: str,
    ) -> str:
        """Tạo cảnh báo tiếng Việt."""
        name_vi = CLASS_NAMES_VI.get(class_id, "vật cản")
        if distance_m < 0:
            return f"Phía trước có {name_vi}"
        dist_str = f"{distance_m:.1f}"
        if warning_level == "close":
            return f"Cẩn thận! Phía trước có {name_vi}, cách {dist_str} mét"
        elif warning_level == "medium":
            return f"Phía trước có {name_vi}, cách {dist_str} mét"
        else:
            return f"Phía xa có {name_vi}, cách {dist_str} mét"

    def process_yolo_result(
        self,
        result,
        conf_threshold: float = 0.25,
    ) -> FrameDistanceResult:
        """
        Xử lý từ Ultralytics YOLO result object.

        Args:
            result: ultralytics Results object (phải có masks)
            conf_threshold: Ngưỡng confidence

        Returns:
            FrameDistanceResult
        """
        if result.boxes is None or len(result.boxes) == 0:
            return FrameDistanceResult([], None, [])

        if result.masks is None:
            return FrameDistanceResult([], None, [])

        boxes = result.boxes.xyxy.cpu().numpy()
        class_ids = result.boxes.cls.cpu().numpy()
        confidences = result.boxes.conf.cpu().numpy()
        masks = result.masks.data.cpu().numpy()

        detections: list[DetectionWithDistance] = []

        for i in range(len(boxes)):
            conf = float(confidences[i])
            if conf < conf_threshold:
                continue

            cls_id = int(class_ids[i])
            bbox = tuple(float(v) for v in boxes[i])
            mask = masks[i] if i < len(masks) else None

            if mask is None:
                continue

            # Ước tính khoảng cách bằng mask area
            distance = self.estimate_distance(cls_id, mask)

            warning_level = self.get_warning_level(distance)
            warning_text = self.format_warning_vi(cls_id, distance, warning_level)

            det = DetectionWithDistance(
                class_id=cls_id,
                class_name=CLASS_NAMES.get(cls_id, "unknown"),
                class_name_vi=CLASS_NAMES_VI.get(cls_id, "vật cản"),
                confidence=conf,
                bbox=bbox,
                distance_m=round(distance, 2),
                warning_level=warning_level,
                warning_text_vi=warning_text,
                mask=mask,
            )
            detections.append(det)

        # Sắp xếp: gần + nguy hiểm trước
        detections.sort(
            key=lambda d: (
                0 if d.warning_level == "close" else (1 if d.warning_level == "medium" else 2),
                -self.PRIORITY.get(d.class_id, 0),
                d.distance_m if d.distance_m > 0 else 999,
            )
        )

        valid_dets = [d for d in detections if d.distance_m > 0]
        closest = min(valid_dets, key=lambda d: d.distance_m) if valid_dets else None

        warnings_vi = []
        for det in detections:
            if len(warnings_vi) >= 3:
                break
            if det.warning_level in ("close", "medium"):
                warnings_vi.append(det.warning_text_vi)

        return FrameDistanceResult(
            detections=detections,
            closest_detection=closest,
            warnings_vi=warnings_vi,
        )


# ============================================================
# Calibration
# ============================================================

def calibrate_k_factor(
    known_distance_m: float,
    mask_area_px: float,
) -> float:
    """
    Calibrate hệ số k từ 1 phép đo đã biết khoảng cách.

    k = known_distance * sqrt(mask_area_px)

    Args:
        known_distance_m: Khoảng cách thực (mét)
        mask_area_px: Diện tích mask (pixel²)

    Returns:
        Hệ số k
    """
    return known_distance_m * np.sqrt(mask_area_px)
