/// 11 target classes cho SafeWalk Hanoi
/// Port từ scripts/distance/bbox_distance.py

class ClassLabels {
  ClassLabels._();

  static const int numClasses = 11;

  /// Tên class tiếng Anh (Custom 11 classes)
  static const Map<int, String> names = {
    0: 'person',
    1: 'bicyclist',
    2: 'motorcyclist',
    3: 'car',
    4: 'bus',
    5: 'motorcycle',
    6: 'crosswalk',
    7: 'pole',
    8: 'traffic_light',
    9: 'traffic_sign',
    10: 'barrier',
  };

  /// Tên class tiếng Việt - dùng cho TTS cảnh báo
  static const Map<int, String> namesVi = {
    0: 'người đi bộ',
    1: 'người đạp xe',
    2: 'người đi xe máy',
    3: 'ô tô',
    4: 'xe buýt',
    5: 'xe máy',
    6: 'vạch qua đường',
    7: 'cột điện',
    8: 'đèn giao thông',
    9: 'biển báo',
    10: 'rào chắn',
  };

  /// Thứ tự ưu tiên cảnh báo: số càng cao càng ưu tiên
  static const Map<int, int> warningPriority = {
    0: 10,   // person
    1: 9,    // bicyclist
    2: 9,    // motorcyclist
    5: 8,    // motorcycle
    3: 7,    // car
    4: 7,    // bus
    10: 6,   // barrier
    7: 5,    // pole
    8: 4,    // traffic_light
    9: 4,    // traffic_sign
    6: 3,    // crosswalk
  };

  /// Ngưỡng tin cậy (Confidence Threshold) riêng cho từng class
  /// Giúp giảm false positive cho các vật to và giảm false negative cho vật nhỏ.
  static const Map<int, double> confThresholds = {
    0: 0.50, // person (dễ nhận diện -> ngưỡng cao)
    1: 0.50, // bicyclist
    2: 0.65, // motorcyclist (nâng ngưỡng chống FP indoor)
    3: 0.75, // car (to -> ngưỡng rất cao, chống nhận diện nhầm)
    4: 0.75, // bus (to -> ngưỡng rất cao, chống nhận diện nhầm)
    5: 0.65, // motorcycle (nâng ngưỡng chống FP indoor)
    6: 0.35, // crosswalk (khó nhìn -> ngưỡng thấp)
    7: 0.35, // pole
    8: 0.40, // traffic_light
    9: 0.40, // traffic_sign
    10: 0.35, // barrier
  };
}
