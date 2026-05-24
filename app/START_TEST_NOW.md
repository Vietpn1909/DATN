# 🚀 UI Flow Test - Ready to Run!

## ✨ What I Created For You

**4 files để test UI flow trên máy tính mà không cần Android device:**

| File | Purpose |
|------|---------|
| `lib/services/mock_tflite_service.dart` | Mock inference service (simulate detections) |
| `lib/core/config/app_config.dart` | Config flag to enable mock mode |
| `lib/screens/test/ui_flow_test_screen.dart` | Test UI with detection display |
| `lib/main_test.dart` | App entry point for testing |

**3 documentation files:**
- `UI_TEST_SETUP.md` - Detailed setup guide
- `TEST_UI_FLOW.md` - What to test & verify
- `THIS FILE` - Quick start

---

## ⚡ Quick Start (2-3 Minutes)

### **Step 1: Run Test App**

```bash
cd d:\VIET\DATN\app
flutter run -t lib/main_test.dart
```

Wait 20-30 seconds for build. App will open on **Windows desktop**.

### **Step 2: Click "Start Detection"**

Green floating button at bottom right. Click it.

### **Step 3: Watch Mock Scenarios** (8 seconds × 3-4 cycles)

App simulates realistic scenarios:
- **Frames 0-30**: Empty street
- **Frames 30-60**: Person walking closer (distance: 15m → 5m)
- **Frames 60-90**: Multiple vehicles
- **Frames 90-120**: Busy street (danger zone)

### **Step 4: Verify Results**

Check if you see:
- ✓ FPS updating (~15 FPS)
- ✓ Detections appearing (people, motorcycles, cars)
- ✓ Detection cards with red/orange/yellow borders (based on distance)
- ✓ Warning snackbars at top (red card with Vietnamese text)
- ✓ Last warning shows: "Phía trước có người, cách 2 mét" etc.

### **Step 5: Stop Detection**

Click "Stop Detection" button. Everything should reset.

---

## 🎯 Expected Behavior

### **Good Sign #1: Initialization**
```
App loads successfully
No crashes or errors
Test screen displays
```

### **Good Sign #2: Detection Running**
```
Status: 🟢 DETECTING
FPS: 14.5 (or similar)
Detections: 3 (numbers varying)
```

### **Good Sign #3: Warnings**
```
Red warning card appears:
"Phía trước có người, cách 2 mét"
OR
"Cảnh báo! Có người rất gần, cách 1.5 mét"
```

### **Good Sign #4: Multiple Objects**
```
Detections (2):
┌─ NGƯỜI (0.90) - Distance: 2.5m [RED border]
└─ XE MÁY (0.88) - Distance: 4.2m [ORANGE border]
```

---

## ❌ If Something Fails

| Problem | Fix |
|---------|-----|
| `FileNotFoundError` | Make sure you're in `d:\VIET\DATN\app` directory |
| `TypeError` | Run `flutter clean && flutter pub get` first |
| FPS = 0 always | Click "Start Detection" button |
| No detections | Wait 5+ seconds, detections appear gradually |
| App won't start | Check `flutter --version` is 3.16+, run `flutter upgrade` |

---

## 📊 What Gets Tested

✅ **UI Flow:**
- Initialization
- Button responsiveness
- Card rendering
- Snackbar display
- FPS counter

✅ **Detection Logic:**
- Detection generation (simulated)
- Sorting (closest first)
- Distance estimation
- Warning level assignment

✅ **Warning System:**
- Text generation (Vietnamese)
- Color coding (red/orange/yellow)
- Cooldown logic
- Snackbar triggering

❌ **NOT Tested (yet):**
- Real TFLite inference
- Actual camera stream
- GPU processing
- Android-specific sensors

---

## 🎬 Test Checklist

After running, verify these:

- [ ] App opens without crash
- [ ] "Start Detection" button visible and clickable
- [ ] Click button → Status changes to 🟢 DETECTING
- [ ] FPS counter shows 14-15 (updates every second)
- [ ] Detections appear in list (numbers change)
- [ ] Detections have detection cards showing:
  - [ ] Class name (người, xe máy, ô tô, etc.)
  - [ ] Confidence (0.85, 0.90, etc.)
  - [ ] Distance (1.5m, 3.2m, 7.8m, etc.)
  - [ ] Warning level (close, medium, far)
  - [ ] Border color matches level (red, orange, yellow)
- [ ] Warning snackbars appear with Vietnamese text
- [ ] Scenarios cycle through (empty → person → vehicles → busy)
- [ ] "Stop Detection" button works → resets everything
- [ ] Status changes to 🔴 IDLE after stopping

---

## 📝 Output to Watch

### Console Output (Good):
```
flutter: [UITest] Mock service ready ✓
flutter: [UITest] Detection started - simulating frames...
flutter: [MockTFLite] Frame #30: 0 detections, 45ms
flutter: [MockTFLite] Frame #60: 1 detections, 48ms
flutter: [MockTFLite]   → Class: 0 (person), Conf: 0.87
flutter: 🔊 WARNING: Phía trước có người, cách 15.0 mét
```

### UI Output (Good):
```
┌─────────────────────────────┐
│ Status: 🟢 DETECTING        │
│ FPS: 14.8                   │
│ Detections: 2               │
└─────────────────────────────┘

Last Warning:
🔊 "Cảnh báo! Có xe máy rất gần, cách 2.5 mét"

Detections (2):
┌─ NGƯỜI (0.92)           ← [RED border]
│ Distance: 2.5m
│ Level: close
└─ XE MÁY (0.88)          ← [ORANGE border]  
  Distance: 4.2m
  Level: medium
```

---

## 🎯 Next Steps (After This Test)

**If UI test PASSES ✅:**
- Proceed to **Unit Tests** (test components)
- Then **Integration Tests** (test on emulator/device)

**If UI test FAILS ❌:**
- Check console errors
- Try `flutter clean && flutter pub get && flutter run -t lib/main_test.dart`
- If still fails, share error message with me

---

## 🚀 Ready? Go!

```bash
cd d:\VIET\DATN\app
flutter run -t lib/main_test.dart
```

**Expected:**
- 20-30 seconds building...
- App opens on Windows desktop
- Click "Start Detection"
- Watch scenarios run
- Verify all ✓ above

That's it! 🎉

---

## 📚 Full Documentation

For detailed info, see:
- `UI_TEST_SETUP.md` - Detailed component testing
- `TEST_UI_FLOW.md` - Full verification guide

