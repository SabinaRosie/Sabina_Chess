import 'package:chess_demo_sabina/utils/color_utils.dart';
import 'package:flutter/material.dart';
import '../models/piece.dart';
import '../utils/color_utils.dart';

class Square extends StatelessWidget {
  final bool isWhite;
  final Piece? piece;
  final bool isHighlighted;
  final bool isCheck;
  final VoidCallback onTap;

  const Square({
    super.key,
    required this.isWhite,
    required this.piece,
    required this.onTap,
    this.isHighlighted = false,
    this.isCheck = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: isCheck
            ? Colors.red
            : isHighlighted
                ? AppColors.highlight
                : (isWhite
                    ? AppColors.lightSquare
                    : AppColors.darkSquare),
        child: piece != null ? Image.asset(piece!.image) : null,
      ),
    );
  }
}