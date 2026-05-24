import numpy as np
import tensorflow as tf
from PIL import Image
import urllib.request

# Tải ảnh test (ảnh người và ô tô)
urllib.request.urlretrieve(
    "https://ultralytics.com/images/zidane.jpg", 
    "zidane.jpg"
)

# Load ảnh và resize về 320x320
img = Image.open("zidane.jpg").resize((320, 320))
input_data = np.array(img, dtype=np.float32) / 255.0
input_data = np.expand_dims(input_data, axis=0) # [1, 320, 320, 3]

# Load TFLite model
interpreter = tf.lite.Interpreter(model_path="assets/models/best_full_integer_quant.tflite")
interpreter.allocate_tensors()

input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

print(f"Input details: {input_details[0]['shape']}, {input_details[0]['dtype']}")
print(f"Output details: {output_details[0]['shape']}, {output_details[0]['dtype']}")

# Set tensor
interpreter.set_tensor(input_details[0]['index'], input_data)

# Run inference
print("Running inference...")
interpreter.invoke()

# Lấy output
output_data = interpreter.get_tensor(output_details[0]['index'])

# Giả sử shape là [1, 84, 2100]
print(f"Output shape: {output_data.shape}")

# Tìm object có confidence cao nhất
if len(output_data.shape) == 3 and output_data.shape[1] == 84:
    candidates = output_data[0] # Shape [84, 2100]
    
    max_score = 0
    max_class = -1
    best_box = None
    
    for i in range(candidates.shape[1]): # Iterate over 2100 boxes
        scores = candidates[4:, i] # 80 classes
        best_class_score = np.max(scores)
        if best_class_score > max_score:
            max_score = best_class_score
            max_class = np.argmax(scores)
            best_box = candidates[0:4, i]
            
    print(f"Best Detection:")
    print(f"  Confidence: {max_score:.4f}")
    print(f"  Class ID: {max_class}")
    print(f"  Box (cx, cy, w, h): {best_box}")
else:
    print("Unexpected output shape, cannot parse YOLOv8 format.")
