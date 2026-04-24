import 'package:flutter/material.dart';
import '../models/board.dart';
import '../models/piece.dart';
import 'square.dart';

class ChessBoardWidget extends StatefulWidget {
  const ChessBoardWidget({super.key});

  @override
  State<ChessBoardWidget> createState() => _ChessBoardWidgetState();
}

class _ChessBoardWidgetState extends State<ChessBoardWidget> {
  Board board = Board();

  int? selectedRow;
  int? selectedCol;

  List<List<int>> validMoves = [];

  bool isWhiteInCheck = false;
  bool isBlackInCheck = false;

  void onSquareTap(int row, int col) {
    setState(() {
      if (selectedRow == null) {
        if (board.board[row][col] != null) {
          selectedRow = row;
          selectedCol = col;
          validMoves = board.getValidMoves(row, col);
        }
      } else {
        bool isValid = validMoves.any((m) => m[0] == row && m[1] == col);

        if (isValid) {
          board.movePiece(selectedRow!, selectedCol!, row, col);

          isWhiteInCheck = board.isKingInCheck(true);
          isBlackInCheck = board.isKingInCheck(false);

          if (board.gameOver) {
            showDialog(
              context: context,
              builder: (_) => const AlertDialog(
                title: Text("Game Over"),
                content: Text("King captured!"),
              ),
            );
          }
        }

        selectedRow = null;
        selectedCol = null;
        validMoves = [];
      }
    });
  }

  bool isHighlighted(int row, int col) {
    return validMoves.any((m) => m[0] == row && m[1] == col);
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: GridView.builder(
        itemCount: 64,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
        ),
        itemBuilder: (context, index) {
          int row = index ~/ 8;
          int col = index % 8;

          bool isWhite = (row + col) % 2 == 0;

          final piece = board.board[row][col];

          bool isCheckSquare = false;

          if (piece != null && piece.type == PieceType.king) {
            if (piece.isWhite && isWhiteInCheck) {
              isCheckSquare = true;
            }
            if (!piece.isWhite && isBlackInCheck) {
              isCheckSquare = true;
            }
          }

          return Square(
            isWhite: isWhite,
            piece: piece,
            isHighlighted: isHighlighted(row, col),
            isCheck: isCheckSquare,
            onTap: () => onSquareTap(row, col),
          );
        },
      ),
    );
  }
}
