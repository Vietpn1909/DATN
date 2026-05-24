# 🧪 UI Flow Test - Run On Desktop

Test app obstacle detection UI flow trên **máy tính Windows** mà không cần Android device!

## 🚀 Quick Start (2 phút)

### **Step 1: Run Test App**

```bash
cd d:\VIET\DATN\app

# Run test app trên desktop (Windows)
flutter run -t lib/main_test.dart
```

App sẽ mở trên máy tính (Windows desktop) với test UI.

### **Step 2: Click "Start Detection"**

Bạn sẽ thấy:
- ✓ Mock service simulate frames
- ✓ FPS updating (should be ~15 FPS)
- ✓ Detections appearing
- ✓ Warnings being generated

### **Step 3: Watch Scenarios**

Mock service simulate 4 scenarios:

```
Cycle (120 frames = 8 seconds):
├─ Frames 0-30: Empty street (occasional pole)
├─ Frames 30-60: Person walking closer (distance: 15m → 5m)
├─ Frames 60-90: Multiple vehicles (car + motorcycle)
└─ Frames 90-120: Busy street (person + motorcycle very close)
```

---

## 📊 What Gets Tested

| Component | Test | Expected |
|-----------|------|----------|
| **Mock Service** | Load & initialize | "Mock service ready ✓" |
| **FPS Counter** | Update every 1 sec | "FPS: 14.5" |
| **Detections** | Detected objects appear | "Detections: 3-8" |
| **Warning Level** | Distance → warning color | Red (close), Orange (medium), Yellow (far) |
| **Warning Text** | Vietnamese text generated | "Phía trước có người, cách 2 mét" |
| **Snackbar** | UI shows warning | Red snackbar with warning text |

---

## 🎯 Expected UI States

### **State 1: Idle** 
```
Status: 🔴 IDLE
FPS: 0
Detections: 0
```

### **State 2: Detecting (Empty)**
```
Status: 🟢 DETECTING
FPS: 14.8
Detections: 0
```

### **State 3: Person Detected**
```
Status: 🟢 DETECTING
FPS: 14.8
Detections: 1
Closest: người (8.5m)

Last Warning:
🔊 "Phía trước có người, cách 8.5 mét"

Detections (1):
┌─────────────────────────────────┐
│ NGƯỜI (0.90)                    │
│ Distance: 8.5m                  │
│ Level: far                       │
│ Warning: Phía trước có người... │
└─────────────────────────────────┘
```

### **State 4: Close Alert**
```
Status: 🟢 DETECTING
FPS: 14.8
Detections: 2
Closest: người (1.5m)

Last Warning:
🔊 "Cảnh báo! Có người rất gần, cách 1.5 mét"

Detections (2):
┌─────────────────────────────────┐
│ NGƯỜI (0.95)                    │  ← Red border (close)
│ Distance: 1.5m                  │
│ Level: close                    │
│ Warning: Cảnh báo! Có người...  │
└─────────────────────────────────┘
┌─────────────────────────────────┐
│ XE MÁY (0.88)                   │  ← Orange border (medium)
│ Distance: 4.2m                  │
│ Level: medium                   │
│ Warning: Chú ý! Có xe máy...    │
└─────────────────────────────────┘
```

---

## ✅ Verification Checklist

Test UI Flow và verify những thứ này:

- [ ] **Initialization**
  - [ ] App loads without crash
  - [ ] No errors in console
  
- [ ] **Detection Toggle**
  - [ ] Click "Start Detection" button works
  - [ ] Status changes to 🟢 DETECTING
  - [ ] FPS counter updates (should be ~15 FPS)
  - [ ] Detections start appearing

- [ ] **Scenario 1: Empty (0-30 frames)**
  - [ ] Detections = 0 or very few (pole occasionally)
  - [ ] No warnings

- [ ] **Scenario 2: Person Walking (30-60 frames)**
  - [ ] Person detection appears
  - [ ] Distance decreases: 15m → 5m
  - [ ] Warning level changes: far → medium → close (color changes)
  - [ ] Warning text updates

- [ ] **Scenario 3: Vehicles (60-90 frames)**
  - [ ] Car + motorcycle detected
  - [ ] Multiple detections showing
  - [ ] Each has correct warning level

- [ ] **Scenario 4: Busy Street (90-120 frames)**
  - [ ] Person very close (1-3m)
  - [ ] Red border indicator (close)
  - [ ] Warning snackbar appears red
  - [ ] Warning text shows "Cảnh báo! Có người rất gần"

- [ ] **Stop Detection**
  - [ ] Click "Stop Detection" button works
  - [ ] Status changes to 🔴 IDLE
  - [ ] FPS resets to 0
  - [ ] Detections list clears

---

## 🔍 Debug Output (Console)

Watch Flutter console for debug messages:

```
flutter: [UITest] Mock service ready ✓
flutter: [UITest] Detection started - simulating frames...
flutter: [MockTFLite] Frame #30: 0 detections, 45ms
flutter: [MockTFLite] Frame #60: 1 detections, 48ms | Input: 480x640 YUV420
flutter: [MockTFLite]   → Class: 0 (person), Conf: 0.87
flutter: 🔊 WARNING: Phía trước có người, cách 8.5 mét
flutter: [MockTFLite] Frame #90: 2 detections, 52ms
flutter: [UITest] Detection stopped
```

---

## 📱 Common Issues

| Issue | Solution |
|-------|----------|
| "App won't start" | Check `flutter pub get` ran |
| "FPS = 0" | Make sure "Start Detection" was clicked |
| "No detections" | Wait 30 frames for scenario to load |
| "No warnings" | Check 2-second cooldown hasn't triggered yet |
| "TypeError" | Make sure you have latest code (no uncommitted changes) |

---

## 🎬 Next Steps After UI Test

Once UI flow verified, we'll do:

1. **Unit Tests** - Test individual components:
   - Mock detection data parsing
   - Warning service logic
   - Distance calculation

2. **Integration Tests** - Test on Android emulator:
   - Real TFLite inference
   - Camera stream
   - Full app flow

---

## 📝 Notes

- Mock detections are **completely simulated** - no GPU required
- Runs on **Windows/Mac/Linux** - any desktop
- Tests **UI flow only** - doesn't test actual ML inference
- Good for catching UI bugs before testing on device

---

## 🚀 Run It Now!

```bash
cd d:\VIET\DATN\app
flutter run -t lib/main_test.dart
```

Then click "Start Detection" and watch the scenarios! 🎯

