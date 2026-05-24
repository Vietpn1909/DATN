"""
BBox-based Distance Estimation Module
======================================
Ước tính khoảng cách đến vật cản dựa trên chiều cao bounding box
sử dụng pinhole camera model:

    distance = (real_height × focal_length_px) / bbox_height_px

Hỗ trợ:
- 11 class vật cản của SafeWalk Hanoi
- 3 mức cảnh báo: gần (< 3m), trung bình (3-7m), xa (> 7m)
- Cảnh báo bằng tiếng Việt
- Calibration cho nhiều loại điện thoại
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import numpy as np


# ============================================================
# Constants
# ============================================================

CLASS_NAMES: dict[int, str] = {
    0: "person",
    1: "bicyclist",
    2: "motorcyclist",
    3: "car",
    4: "bus",
    5: "motorcycle",
    6: "crosswalk",
    7: "pole",
    8: "traffic_light",
    9: "traffic_sign",
    10: "barrier",
}

# Tên tiếng Việt cho cảnh báo âm thanh
CLASS_NAMES_VI: dict[int, str] = {
    0: "người",
    1: "người đi xe đạp",
    2: "người đi xe máy",
    3: "ô tô",
    4: "xe buýt",
    5: "xe máy",
    6: "vạch sang đường",
    7: "cột",
    8: "đèn giao thông",
    9: "biển báo",
    10: "rào chắn",
}

# Chiều cao thực trung bình (mét) cho mỗi class
# crosswalk = 0 vì nằm trên mặt đất -> dùng phương pháp riêng
DEFAULT_REAL_HEIGHTS: dict[int, float] = {
    0: 1.65,   # person (trung bình người Việt Nam)
    1: 1.70,   # bicyclist (người + xe đạp)
    2: 1.60,   # motorcyclist (người ngồi trên xe máy)
    3: 1.50,   # car
    4: 3.00,   # bus
    5: 1.10,   # motorcycle (không người)
    6: 0.0,    # crosswalk (nằm trên mặt đất)
    7: 2.50,   # pole
    8: 0.60,   # traffic_light
    9: 0.60,   # traffic_sign
    10: 0.90,  # barrier
}

# Chiều rộng thực cho crosswalk (dùng bbox width thay vì height)
DEFAULT_REAL_WIDTHS: dict[int, float] = {
    6: 3.00,   # crosswalk
}

DEFAULT_FOCAL_LENGTH_PX = 600  # Giá trị mặc định, cần calibrate
DEFAULT_IMAGE_SIZE = 640

# Ngưỡng cảnh báo khoảng cách (mét)
CLOSE_THRESHOLD = 3.0     # Gần: < 3m -> cảnh báo khẩn cấp
MEDIUM_THRESHOLD = 7.0    # Trung bình: 3-7m -> cảnh báo nhẹ
# Xa: > 7m -> thông báo


# ============================================================
# Data classes
# ============================================================

@dataclass
class DetectionWithDistance:
    """Kết quả detection kèm ước tính khoảng cách."""
    class_id: int
    class_name: str
    class_name_vi: str
    confidence: float
    bbox: tuple[float, float, float, float]  # x1, y1, x2, y2
    distance_m: float  # Khoảng cách ước tính (mét)
    warning_level: str  # "close", "medium", "far"
    warning_text_vi: str  # Cảnh báo tiếng Việt
    mask: Optional[np.ndarray] = field(default=None, repr=False)


@dataclass
class FrameDistanceResult:
    """Kết quả distance estimation cho 1 frame."""
    detections: list[DetectionWithDistance]
    closest_detection: Optional[DetectionWithDistance]
    warnings_vi: list[str]  # Danh sách cảnh báo ưu tiên (tiếng Việt)


# ============================================================
# Main class
# ============================================================

class BBoxDistanceEstimator:
    """
    Ước tính khoảng cách đến vật cản dựa trên BBox height.

    Sử dụng pinhole camera model:
        distance = (real_height × focal_length_px) / bbox_height_px

    Trường hợp đặc biệt:
        - crosswalk: dùng bbox width + real_width thay vì height
        - Vật bị cắt ở mép ảnh: đánh dấu uncertain
    """

    # Thứ tự ưu tiên cảnh báo: vật nguy hiểm hơn được cảnh báo trước
    # person > xe cơ giới > vật cản tĩnh
    PRIORITY: dict[int, int] = {
        0: 10,   # person - ưu tiên cao nhất
        2: 9,    # motorcyclist
        1: 8,    # bicyclist
        3: 7,    # car
        4: 7,    # bus
        5: 6,    # motorcycle (không người)
        10: 5,   # barrier
        7: 4,    # pole
        6: 3,    # crosswalk (thông báo, không nguy hiểm)
        8: 2,    # traffic_light
        9: 2,    # traffic_sign
    }

    def __init__(
        self,
        focal_length_px: float = DEFAULT_FOCAL_LENGTH_PX,
        image_size: int = DEFAULT_IMAGE_SIZE,
        real_heights: Optional[dict[int, float]] = None,
        real_widths: Optional[dict[int, float]] = None,
        close_threshold: float = CLOSE_THRESHOLD,
        medium_threshold: float = MEDIUM_THRESHOLD,
        config_path: Optional[Path] = None,
    ) -> None:
        """
        Khởi tạo BBox Distance Estimator.

        Args:
            focal_length_px: Tiêu cự camera tính bằng pixel
            image_size: Kích thước ảnh input YOLO (mặc định 640)
            real_heights: Dict {class_id: chiều cao thực (m)}
            real_widths: Dict {class_id: chiều rộng thực (m)} cho vật nằm ngang
            close_threshold: Ngưỡng cảnh báo gần (mét)
            medium_threshold: Ngưỡng cảnh báo trung bình (mét)
            config_path: Đường dẫn file camera_params.json
        """
        # Load config nếu có
        if config_path and config_path.exists():
            self._load_config(config_path)
        else:
            self.focal_length_px = focal_length_px
            self.image_size = image_size
            self.real_heights = real_heights or DEFAULT_REAL_HEIGHTS.copy()
            self.real_widths = real_widths or DEFAULT_REAL_WIDTHS.copy()
            self.close_threshold = close_threshold
            self.medium_threshold = medium_threshold

    def _load_config(self, config_path: Path) -> None:
        """Load tham số từ file JSON config."""
        with open(config_path, encoding="utf-8") as f:
            config = json.load(f)

        default = config.get("default", {})
        self.focal_length_px = default.get("focal_length_px", DEFAULT_FOCAL_LENGTH_PX)
        self.image_size = default.get("image_width", DEFAULT_IMAGE_SIZE)

        # Parse real heights
        self.real_heights = DEFAULT_REAL_HEIGHTS.copy()
        for key, val in config.get("real_heights_m", {}).items():
            if key.startswith("_"):
                continue
            class_id = int(key.split("_")[0])
            self.real_heights[class_id] = val

        # Parse real widths
        self.real_widths = DEFAULT_REAL_WIDTHS.copy()
        for key, val in config.get("real_widths_m", {}).items():
            if key.startswith("_"):
                continue
            class_id = int(key.split("_")[0])
            self.real_widths[class_id] = val

        # Warning thresholds
        thresholds = config.get("warning_thresholds_m", {})
        self.close_threshold = thresholds.get("close", CLOSE_THRESHOLD)
        self.medium_threshold = thresholds.get("medium", MEDIUM_THRESHOLD)

    def estimate_distance(
        self,
        class_id: int,
        bbox: tuple[float, float, float, float],
    ) -> float:
        """
        Ước tính khoảng cách từ camera đến vật thể.

        Args:
            class_id: ID của class (0-10)
            bbox: Bounding box (x1, y1, x2, y2) trong pixel

        Returns:
            Khoảng cách ước tính (mét). Trả về -1.0 nếu không ước tính được.
        """
        x1, y1, x2, y2 = bbox
        bbox_height = y2 - y1
        bbox_width = x2 - x1

        # Crosswalk: nằm trên mặt đất -> dùng width
        if class_id == 6:
            real_width = self.real_widths.get(6, 3.0)
            if bbox_width < 5:  # Quá nhỏ, không đáng tin cậy
                return -1.0
            return (real_width * self.focal_length_px) / bbox_width

        # Các class khác: dùng height
        real_height = self.real_heights.get(class_id, 0.0)
        if real_height <= 0 or bbox_height < 5:
            return -1.0

        distance = (real_height * self.focal_length_px) / bbox_height
        return round(distance, 2)

    def get_warning_level(self, distance_m: float) -> str:
        """Xác định mức cảnh báo dựa trên khoảng cách."""
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
        """
        Tạo cảnh báo bằng tiếng Việt.

        Ví dụ: "Cẩn thận! Phía trước có xe máy, cách 2.5 mét"
        """
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

    def is_bbox_clipped(
        self,
        bbox: tuple[float, float, float, float],
        margin: int = 5,
    ) -> bool:
        """
        Kiểm tra bbox có bị cắt ở mép ảnh không.
        Nếu bị cắt, ước tính khoảng cách kém chính xác hơn.
        """
        x1, y1, x2, y2 = bbox
        return (
            x1 < margin
            or y1 < margin
            or x2 > self.image_size - margin
            or y2 > self.image_size - margin
        )

    def process_detections(
        self,
        boxes: np.ndarray,
        class_ids: np.ndarray,
        confidences: np.ndarray,
        masks: Optional[np.ndarray] = None,
        conf_threshold: float = 0.25,
    ) -> FrameDistanceResult:
        """
        Xử lý tất cả detections trong 1 frame.

        Args:
            boxes: Array shape (N, 4) - bbox [x1, y1, x2, y2]
            class_ids: Array shape (N,) - class ID cho mỗi detection
            confidences: Array shape (N,) - confidence score
            masks: Optional array shape (N, H, W) - segmentation masks
            conf_threshold: Ngưỡng confidence tối thiểu

        Returns:
            FrameDistanceResult với danh sách detections kèm khoảng cách
        """
        detections: list[DetectionWithDistance] = []

        for i in range(len(boxes)):
            conf = float(confidences[i])
            if conf < conf_threshold:
                continue

            cls_id = int(class_ids[i])
            bbox = tuple(float(v) for v in boxes[i])

            # Ước tính khoảng cách
            distance = self.estimate_distance(cls_id, bbox)

            # Giảm confidence nếu bbox bị cắt ở mép ảnh
            if self.is_bbox_clipped(bbox) and distance > 0:
                distance = distance * 1.2  # Tăng khoảng cách ước tính (bù cho bbox bị cắt)

            warning_level = self.get_warning_level(distance)
            warning_text = self.format_warning_vi(cls_id, distance, warning_level)

            mask_data = masks[i] if masks is not None and i < len(masks) else None

            det = DetectionWithDistance(
                class_id=cls_id,
                class_name=CLASS_NAMES.get(cls_id, "unknown"),
                class_name_vi=CLASS_NAMES_VI.get(cls_id, "vật cản"),
                confidence=conf,
                bbox=bbox,
                distance_m=round(distance, 2),
                warning_level=warning_level,
                warning_text_vi=warning_text,
                mask=mask_data,
            )
            detections.append(det)

        # Sắp xếp theo ưu tiên cảnh báo: gần + nguy hiểm trước
        detections.sort(
            key=lambda d: (
                0 if d.warning_level == "close" else (1 if d.warning_level == "medium" else 2),
                -self.PRIORITY.get(d.class_id, 0),
                d.distance_m if d.distance_m > 0 else 999,
            )
        )

        # Tìm vật gần nhất
        valid_dets = [d for d in detections if d.distance_m > 0]
        closest = min(valid_dets, key=lambda d: d.distance_m) if valid_dets else None

        # Tạo danh sách cảnh báo (tối đa 3, ưu tiên vật gần + nguy hiểm)
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

    def process_yolo_result(
        self,
        result,
        conf_threshold: float = 0.25,
    ) -> FrameDistanceResult:
        """
        Xử lý trực tiếp từ Ultralytics YOLO result object.

        Args:
            result: ultralytics.engine.results.Results object
            conf_threshold: Ngưỡng confidence tối thiểu

        Returns:
            FrameDistanceResult
        """
        if result.boxes is None or len(result.boxes) == 0:
            return FrameDistanceResult(
                detections=[],
                closest_detection=None,
                warnings_vi=[],
            )

        boxes = result.boxes.xyxy.cpu().numpy()
        class_ids = result.boxes.cls.cpu().numpy()
        confidences = result.boxes.conf.cpu().numpy()

        # Lấy masks nếu có (segmentation model)
        masks = None
        if result.masks is not None:
            masks = result.masks.data.cpu().numpy()

        return self.process_detections(
            boxes=boxes,
            class_ids=class_ids,
            confidences=confidences,
            masks=masks,
            conf_threshold=conf_threshold,
        )


# ============================================================
# Calibration utilities
# ============================================================

def calibrate_focal_length(
    known_distance_m: float,
    known_height_m: float,
    bbox_height_px: float,
) -> float:
    """
    Calibrate focal length từ 1 ảnh đã biết khoảng cách thực.

    Đặt 1 vật có chiều cao đã biết ở khoảng cách đã biết,
    chụp ảnh, đo bbox height -> tính focal length.

    Args:
        known_distance_m: Khoảng cách thực (mét)
        known_height_m: Chiều cao thực của vật (mét)
        bbox_height_px: Chiều cao bbox trong ảnh (pixel)

    Returns:
        focal_length_px

    Ví dụ:
        Đặt 1 người cao 1.65m ở cách camera 3m, bbox height = 330px
        -> focal_length = (3 * 330) / 1.65 = 600 px
    """
    return (known_distance_m * bbox_height_px) / known_height_m


def calibrate_from_multiple(
    measurements: list[tuple[float, float, float]],
) -> float:
    """
    Calibrate focal length từ nhiều phép đo để tăng độ chính xác.

    Args:
        measurements: List of (known_distance_m, known_height_m, bbox_height_px)

    Returns:
        focal_length_px (trung bình)
    """
    focal_lengths = [
        calibrate_focal_length(d, h, b) for d, h, b in measurements
    ]
    return float(np.mean(focal_lengths))
