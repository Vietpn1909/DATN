# SafeWalk Hanoi - Trợ lý Điều hướng Thông minh cho Người khiếm thị

Dự án Ứng dụng Hỗ trợ người khiếm thị đi lại an toàn tại khu vực phố cổ Hoàn Kiếm, Hà Nội (Đồ án tốt nghiệp). 

Ứng dụng kết hợp tính năng **Chỉ đường bằng giọng nói (Voice Navigation)** sử dụng bản đồ Goong và **Phát hiện vật cản theo thời gian thực (Real-time Object Detection)** sử dụng mô hình YOLO11n.

---

## 📱 Các tính năng chính (Core Features)
1. **Chỉ đường bằng giọng nói:** Chuyển đổi giọng nói thành văn bản (STT) -> Chỉ đường (Goong Maps) -> Phát âm thanh (TTS).
2. **Phát hiện vật cản theo thời gian thực:** Sử dụng Camera điện thoại kết hợp với YOLO11n.
3. **Ước lượng khoảng cách:** Cảnh báo các vật cản nguy hiểm ở cự ly gần thông qua âm thanh cảnh báo bằng tiếng Việt.
4. **Nhận diện 11 loại vật thể/phương tiện:** Người đi bộ, xe đạp, xe máy, ô tô, xe buýt, vạch kẻ đường, cột điện, đèn giao thông, biển báo, rào chắn...

---

## 🛠 Yêu cầu hệ thống (Prerequisites)

Để có thể chạy được source code này trên một máy tính mới, bạn cần cài đặt các công cụ sau:

### 1. Dành cho Ứng dụng Di động (Flutter App)
- **Flutter SDK:** Phiên bản 3.19.x hoặc mới hơn. ([Hướng dẫn cài đặt Flutter](https://docs.flutter.dev/get-started/install))
- **IDE:** Android Studio, IntelliJ IDEA, hoặc Visual Studio Code (có cài đặt extension Flutter & Dart).
- **Thiết bị chạy:** 
  - Android: Máy ảo Android (Emulator) hoặc thiết bị thật.
  - iOS: Máy Mac có cài đặt Xcode, chạy trên thiết bị thật (iPhone 13 hoặc mới hơn để đảm bảo tốc độ >= 15 FPS) hoặc iOS Simulator.
  - *Lưu ý:* Nên dùng **Thiết bị thật** để test Camera và các tính năng liên quan đến GPS, TFLite.

### 2. Dành cho Huấn luyện Mô hình ML (Tùy chọn)
- **Python:** 3.9 trở lên.
- Card đồ họa hỗ trợ CUDA (NVIDIA) nếu bạn muốn train lại model.

---

## 🚀 Hướng dẫn Cài đặt & Chạy ứng dụng Flutter

Thư mục chứa ứng dụng nằm trong `app/`. Bạn thực hiện các bước sau để chạy app:

### Bước 1: Mở dự án
Mở terminal/CMD và di chuyển vào thư mục ứng dụng:
```bash
cd DATN/app
```

### Bước 2: Cài đặt các thư viện (Dependencies)
Tải các package cần thiết về máy:
```bash
flutter pub get
```

### Bước 3: Kiểm tra cấu hình Goong Map API (Nếu cần)
Ứng dụng sử dụng API của Goong cho bản đồ nội địa Việt Nam. 
File cấu hình API nằm tại:
👉 `app/lib/core/constants/app_constants.dart`
*(Key hiện tại đã được gán sẵn, nếu bị giới hạn lượt gọi, bạn cần tạo tài khoản trên [Goong.io](https://goong.io/) để thay thế Key mới vào các biến `goongApiKey` và `goongMaptileKey`).*

### Bước 4: Chạy ứng dụng
Đảm bảo bạn đã kết nối điện thoại (bật chế độ Developer/Gỡ lỗi USB) hoặc đang mở máy ảo. 

Chạy ứng dụng bằng lệnh:
```bash
flutter run
```
Hoặc ấn nút **Run / Debug** trực tiếp từ Visual Studio Code / Android Studio.

> **Lưu ý trên iOS:**
> - Nếu chạy trên iOS lần đầu, bạn cần cài đặt CocoaPods:
>   ```bash
>   cd ios && pod install && cd ..
>   ```
> - Bạn cần mở `ios/Runner.xcworkspace` bằng Xcode để cấu hình **Signing & Capabilities** (chọn Team của bạn) trước khi có thể build lên iPhone thật.

---

## 🧠 Hướng dẫn Cài đặt Môi trường Machine Learning (YOLO)

Nếu bạn cần chạy lại các file script Python hoặc huấn luyện lại mô hình YOLO11n, hãy thiết lập môi trường Python. Các thư mục liên quan: `configs/`, `data/`, `scripts/`.

### Bước 1: Tạo môi trường ảo (Virtual Environment)
Mở terminal ở thư mục gốc `DATN`:
```bash
python -m venv .venv
```

### Bước 2: Kích hoạt môi trường ảo
- **Windows:**
  ```bash
  .venv\Scripts\activate
  ```
- **macOS/Linux:**
  ```bash
  source .venv/bin/activate
  ```

### Bước 3: Cài đặt thư viện AI
Cài đặt PyTorch và Ultralytics:
```bash
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118  # Dành cho Windows có GPU NVIDIA
pip install ultralytics onnx onnxruntime-gpu
```

---

## 📂 Cấu trúc dự án
- `app/`: Source code ứng dụng di động Flutter.
  - `lib/`: Mã nguồn chính của app (Dart).
  - `assets/`: Chứa các tài nguyên, bao gồm mô hình TFLite đã xuất (`best_float16.tflite`).
- `configs/`: Các cấu hình liên quan đến việc xử lý nhãn và lớp dữ liệu (11 classes).
- `data/`: Nơi chứa dữ liệu thô (Mapillary, Video quay ở phố cổ) và dữ liệu đã tiền xử lý cho YOLO.
- `scripts/`: Code Python để format data, chuẩn bị cho quá trình training YOLO.
- `outputs/`: Kết quả của các lần huấn luyện mô hình (weights, logs, biểu đồ đánh giá mAP).

---

## 💡 Ghi chú Quan trọng
- Ứng dụng dành cho **người khiếm thị**, giao diện hỗ trợ đầy đủ các trình đọc màn hình (TalkBack/VoiceOver).
- Hệ thống cảnh báo giọng nói (TTS) và nhận diện giọng nói (STT) hoạt động tốt nhất ở môi trường có kết nối Internet ổn định.
- Khi đi bộ, hệ thống bản đồ ưu tiên chế độ xe đạp (`vehicle=bike` trên Goong API) vì đây là chế độ cho đường nhỏ tối ưu nhất khả dụng.
