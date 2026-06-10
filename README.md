# SafeWalk Hanoi - Trợ lý Điều hướng Thông minh cho Người khiếm thị

Dự án Ứng dụng Hỗ trợ người khiếm thị đi lại an toàn tại khu vực phố cổ Hoàn Kiếm, Hà Nội (Đồ án tốt nghiệp). 

Ứng dụng kết hợp tính năng **Chỉ đường bằng giọng nói (Voice Navigation)** sử dụng bản đồ Goong và **Phát hiện vật cản theo thời gian thực (Real-time Object Detection)** sử dụng mô hình YOLO11n.

---

## 🏗 Kiến Trúc Hệ Thống (System Architecture)
```mermaid
graph TD
    A[Camera Điện Thoại] -->|Frame (30FPS)| B[Flutter Isolate]
    
    subgraph Lõi AI xử lý nền
    B -->|Pre-process YUV/RGB| C(TFLite Model - YOLO11n)
    C -->|BBox Tensors| D[Yolo Postprocessor]
    D -->|Lọc Nhiễu/NMS| E{DangerZone Service}
    end
    
    E -->|Area Ratio & Hướng| F[Warning Service]
    F -->|Adaptive Cooldown| G((TTS - Phát Âm Thanh))
    
    subgraph Lõi Chỉ Đường
    H[Voice Input - STT] --> I[Goong Map API]
    I -->|Waypoints| J[Navigation Provider]
    J -->|GPS Real-time| G
    end
```

---

## 📱 Các tính năng chính (Core Features)
1. **Chỉ đường bằng giọng nói:** Chuyển đổi giọng nói thành văn bản (STT) -> Tìm đường bằng hệ thống Goong Maps -> Đọc chỉ dẫn rẽ bằng âm thanh (TTS).
2. **Phát hiện vật cản thời gian thực:** Sử dụng Camera điện thoại kết hợp với AI (YOLO11n) xử lý ngay trên thiết bị (On-device Inference), không cần mạng Internet.
3. **Phân tích khu vực nguy hiểm & Hướng dẫn lách tránh:** 
   - Thay vì đọc con số khoảng cách tuyệt đối gây rối loạn, hệ thống quy chiếu vị trí vật cản sang **Hướng mặt đồng hồ** (10 giờ, 12 giờ, 2 giờ).
   - Đánh giá độ rủi ro dựa trên **Tỷ lệ diện tích (Area Ratio)** và đưa ra lệnh hành động dứt khoát bằng tiếng Việt: *"Tránh sang trái", "Tránh sang phải", "Dừng lại"*.
4. **Nhận diện 11 loại vật thể đặc trưng:** Người đi bộ, xe đạp, xe máy, ô tô, xe buýt, vạch kẻ đường, cột điện, đèn giao thông, biển báo, rào chắn...

---

## 🛠 Yêu cầu hệ thống (Prerequisites)

Để có thể chạy được source code này trên một máy tính mới, bạn cần cài đặt các công cụ sau:

### 1. Dành cho Ứng dụng Di động (Flutter App)
- **Flutter SDK:** Phiên bản `>=3.16.0` (Dart `>=3.2.0`). Khuyên dùng bản 3.19.x trở lên để có hiệu năng đồ họa tốt nhất. ([Hướng dẫn cài đặt Flutter](https://docs.flutter.dev/get-started/install))
- **IDE:** Android Studio, IntelliJ IDEA, hoặc Visual Studio Code (có cài đặt extension Flutter & Dart).
- **Thiết bị chạy:** 
  - Android: Máy ảo Android (Emulator) hoặc thiết bị thật.
  - iOS: Máy Mac có cài đặt Xcode, chạy trên thiết bị thật (iPhone 13 hoặc mới hơn để đảm bảo tốc độ >= 15 FPS) hoặc iOS Simulator.
  - *Lưu ý:* Bắt buộc dùng **Thiết bị thật** để test Camera, các tính năng liên quan đến GPS và tối ưu hóa phần cứng (Metal/NNAPI) cho TFLite.

### 2. Dành cho Huấn luyện Mô hình ML (Ngoại tuyến)
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

Nếu bạn cần chạy lại các file script Python hoặc huấn luyện lại mô hình YOLO11n, hãy thiết lập môi trường Python. 

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
Cài đặt toàn bộ thư viện qua file `requirements.txt`:
```bash
pip install -r requirements.txt
```
*(Lưu ý: Nếu sử dụng GPU NVIDIA trên Windows, hãy đảm bảo bạn đã cài đặt CUDA toolkit).*

---

## 📂 Cấu trúc dự án
- `app/`: Source code ứng dụng di động Flutter.
  - `lib/`: Mã nguồn chính của app (Dart). Tích hợp kiến trúc Riverpod.
  - `assets/`: Chứa các tài nguyên, bao gồm mô hình TFLite (`best_float16.tflite`).
- `configs/`: Các cấu hình liên quan đến việc xử lý nhãn và lớp dữ liệu.
- `data/`: Nơi chứa dữ liệu thô và dữ liệu đã tiền xử lý cho mô hình YOLO.
- `scripts/`: Code Python để chuẩn bị data (Auto-labeling) và phục vụ việc phân tích offline thuật toán (vd: tính sai số phương pháp).
- `outputs/`: Kết quả của các lần huấn luyện mô hình.

---

## 💡 Ghi chú Công nghệ Thực tiễn (Bảo vệ Đồ án)
- **Thiết kế UX/UI cho người khiếm thị:** Ứng dụng loại bỏ việc cảnh báo khoảng cách bằng mét (gây quá tải nhận thức) và chuyển sang **Hướng mặt đồng hồ (10h, 12h, 2h)**. Điều này giúp phản xạ lách tránh tự nhiên và an toàn hơn.
- **Chống Spam Âm thanh (Adaptive Cooldown):** Thuật toán tự động nhận diện khu vực đông đúc để tăng độ trễ (delay) giữa các lần đọc TTS, tránh làm người dùng hoảng loạn thính giác.
- **Tối ưu Hóa Hiệu Năng Cấp Cao:** Không sử dụng các thư viện xử lý ảnh thông thường, dự án tự triển khai **Lookup Table** ở tầng Dart để xử lý mảng màu YUV->RGB, kết hợp GPU Delegate (Metal/NNAPI) giúp mô hình đạt tốc độ Real-time 30FPS trên cả các thiết bị đời cũ.
- Khi đi bộ, hệ thống bản đồ ưu tiên chế độ xe đạp (`vehicle=bike` trên Goong API) vì đây là chế độ cho đường nhỏ tối ưu nhất khả dụng cho vỉa hè.
