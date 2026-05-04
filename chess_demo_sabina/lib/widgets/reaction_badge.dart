import 'package:flutter/material.dart';
import '../utils/color_utils.dart';

class ReactionBadge extends StatelessWidget {
  final String emoji;
  final int count;
  final bool isMe;
  final VoidCallback onTap;

  const ReactionBadge({
    super.key,
    required this.emoji,
    required this.count,
    required this.isMe,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 4, top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isMe 
              ? AppColors.secondaryColor.withOpacity(0.2) 
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isMe ? AppColors.secondaryColor : Colors.white24,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(
              count.toString(),
              style: TextStyle(
                color: isMe ? AppColors.secondaryColor : Colors.white70,
                fontSize: 12,
                fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
