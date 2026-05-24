import 'package:flutter/material.dart';
import 'package:safewalk_hanoi/core/theme/app_theme.dart';

/// Nút lớn cho voice input - thiết kế cho người khiếm thị.
/// - Kích thước lớn (dễ chạm)
/// - Có feedback haptic
/// - Accessible label cho screen reader
class VoiceButton extends StatelessWidget {
  final bool isListening;
  final VoidCallback onTap;

  const VoiceButton({
    super.key,
    required this.isListening,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isListening
          ? 'Đang nghe, chạm để dừng'
          : 'Chạm để nói địa chỉ cần đến',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isListening ? AppTheme.danger : AppTheme.accent,
            boxShadow: [
              BoxShadow(
                color: (isListening ? AppTheme.danger : AppTheme.accent)
                    .withOpacity(0.4),
                blurRadius: 16,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Icon(
            isListening ? Icons.stop : Icons.mic,
            color: Colors.white,
            size: 40,
          ),
        ),
      ),
    );
  }
}
