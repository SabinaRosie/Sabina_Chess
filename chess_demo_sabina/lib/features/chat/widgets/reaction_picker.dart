import 'package:flutter/material.dart';
import '../../../core/utils/color_utils.dart';

class ReactionPicker extends StatelessWidget {
  final Function(String) onEmojiSelected;
  final VoidCallback onMorePressed;

  const ReactionPicker({
    super.key,
    required this.onEmojiSelected,
    required this.onMorePressed,
  });

  static const List<String> defaultEmojis = ['❤️', '😂', '😮', '😢', '😡', '👍'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: Colors.white10, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...defaultEmojis.map((emoji) => GestureDetector(
                onTap: () => onEmojiSelected(emoji),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              )),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onMorePressed,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add,
                color: Colors.white70,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
