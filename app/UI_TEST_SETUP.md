# 🧪 UI Flow Test Setup Guide

## ✅ What I Created

### Files Created:
1. **lib/services/mock_tflite_service.dart** - Mock inference service
2. **lib/core/config/app_config.dart** - Configuration flags  
3. **lib/screens/test/ui_flow_test_screen.dart** - Test UI screen
4. **lib/main_test.dart** - Test app entry point
5. **TEST_UI_FLOW.md** - Full testing guide

### Code Changes:
- **lib/providers/providers.dart** - Added conditional mock/real service selection

---

## 🎯 How It Works

### **Main Test Concept:**
```
No Android Device Required ✓
No Emulator Required ✓
No GPU Required ✓
Just Flutter Desktop App ✓
```

### **Test Flow:**
```
Desktop App                Mock Service              UI Layer
    │                          │                         │
    ├─ flutter run ────────────────────────────────────► Loads UI
    │                                                    │
    ├─ Click "Start" ────────► START_TESTING            │
    │                              │                      │
    │                              ├─► Simulate frames   │
    │                              │   (YUV420 dummy)    │
    │                              └─► Generate detections
    │                                   (realistic data) │
    │                          ◄─────────────────────────┤
    │                          FrameResult              │
    │                          + detections             │
    │                          + warnings               │
    │                                               ►   Show detection
    │                                                   cards + snackbars
    │                                                   Update FPS counter
    │                                                   Display warnings
```

---

## 🚀 Run Test (ONE COMMAND)

```bash
cd d:\VIET\DATN\app
flutter run -t lib/main_test.dart
```

That's it! App will open on your Windows desktop.

---

## 🧪 What Gets Tested

### **Component Tests:**

| Component | Test | Result |
|-----------|------|--------|
| **Initialization** | MockTFLiteService loads | "Mock service ready ✓" |
| **Frame Processing** | 15 FPS frame simulation | "FPS: 14.8" |
| **Detection Generation** | Realistic detection data | "Detections: 1-8" |
| **Warning Logic** | Distance → Warning level | Red/Orange/Yellow borders |
| **Warning Text** | Vietnamese warning text | "Phía trước có người, cách 2 mét" |
| **UI Updates** | Snackbars & cards show | Red snackbar appears |
| **Detection Sorting** | Closest detection first | "Closest: người (2.5m)" |
| **Scenario Cycling** | 4 different scenarios | Every 120 frames |

---

## 📊 Test Scenarios (Mock Data)

### **Scenario A: Empty Street (0-30 frames)**
```
Detections: 0-1 (occasional pole)
No warnings
Expected: Clean empty state
```

### **Scenario B: Person Walking (30-60 frames)**
```
Detections: 1 person
Distance: 15m → 5m (gets closer)
Warning level: far → medium → close
Expected: Progressive warnings as person approaches
```

### **Scenario C: Multiple Vehicles (60-90 frames)**
```
Detections: 2 (car + motorcycle)
Distances: 6m, 4.5m
Warning levels: mixed (medium + close)
Expected: Multiple detection cards showing
```

### **Scenario D: Busy Street (90-120 frames)**
```
Detections: 2-3 (person very close + motorcycle)
Distances: 1.5m, 2.5m (DANGER ZONE)
Warning levels: CLOSE for person
Expected: Red alert, urgent warning snackbar
```

---

## ✅ Verification Steps

### **After Running:**

1. **Check Initialization**
   - [ ] App loads without crash
   - [ ] Widget displays properly

2. **Click "Start Detection"**
   - [ ] Status changes to 🟢 DETECTING
   - [ ] FPS starts updating (~15 FPS)
   - [ ] Button text changes to "Stop Detection"

3. **Watch Scenario 1 (Empty)**
   - [ ] Let it run 3-4 seconds
   - [ ] Detections should be 0
   - [ ] No warnings yet

4. **Watch Scenario 2 (Person)**
   - [ ] Detections appear (should be 1)
   - [ ] Distance shown: ~15m → ~5m
   - [ ] Warning color changes: Yellow → Orange
   - [ ] Warning text updates

5. **Watch Scenario 3 (Vehicles)**
   - [ ] 2 detections showing (car + motorcycle)
   - [ ] Different warning levels
   - [ ] Orange/Red colors

6. **Watch Scenario 4 (Busy)**
   - [ ] 2+ detections
   - [ ] Some with RED borders (close)
   - [ ] Red snackbar warning appears
   - [ ] Warning: "Cảnh báo! Có người rất gần"

7. **Click "Stop Detection"**
   - [ ] Status changes to 🔴 IDLE
   - [ ] FPS resets to 0
   - [ ] Detections list clears
   - [ ] Button text changes to "Start Detection"

---

## 🐛 If Something Goes Wrong

### **Error: "Cannot find 'main_test.dart'"**
```bash
# Make sure to run from app directory
cd d:\VIET\DATN\app
flutter run -t lib/main_test.dart
```

### **Error: "MockTFLiteService not found"**
```bash
# Run pub get
flutter pub get
```

### **Error: "Type mismatch"**
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run -t lib/main_test.dart
```

### **Error: "No tests run"**
```bash
# Make sure you're running -t (target file)
flutter run -t lib/main_test.dart
# NOT just: flutter run
```

---

## 📝 Console Output (Expected)

```
flutter: [UITest] Mock service ready ✓
flutter: [UITest] Detection started - simulating frames...
flutter: [MockTFLite] Frame #30: 0 detections, 45ms
flutter: [MockTFLite] Frame #60: 1 detections, 48ms
flutter: 🔊 WARNING: Phía trước có người, cách 15.0 mét
flutter: [MockTFLite] Frame #90: 2 detections, 52ms
flutter: 🔊 WARNING: Cảnh báo! Có người rất gần, cách 2.5 mét
flutter: [UITest] Detection stopped
```

---

## 🎯 Success Criteria

✅ **Test PASSED if:**
- No crashes
- FPS counter updating
- Detections appearing/disappearing
- Warnings text showing in snackbars
- All 4 scenarios cycling properly

❌ **Test FAILED if:**
- Crash on startup
- FPS = 0 forever
- Detections never appear
- Warnings don't show
- Buttons don't respond

---

## 📚 Next: After UI Test Passes

Once all ✅ above are working:

1. **Unit Tests** - Test components individually
   - Detection parsing
   - Warning logic  
   - Distance calculation

2. **Integration Tests** - Test with real YOLO model
   - Android emulator
   - Or real device

3. **End-to-End Test** - Full app flow
   - Camera + Detection + Warning + TTS

---

## 🚀 Ready to Test?

```bash
cd d:\VIET\DATN\app
flutter run -t lib/main_test.dart
```

It'll take 15-30 seconds to build, then the test app opens!

Enjoy testing! 🎉

