import 'piece.dart';

class Board {
  List<List<Piece?>> board = List.generate(8, (_) => List.filled(8, null));

  bool isWhiteTurn = true;
  bool gameOver = false;

  Board() {
    setupBoard();
  }

  void setupBoard() {
    for (int i = 0; i < 8; i++) {
      board[1][i] = Piece(
        type: PieceType.pawn,
        isWhite: false,
        image: 'assets/images/black_pawn.png',
      );
      board[6][i] = Piece(
        type: PieceType.pawn,
        isWhite: true,
        image: 'assets/images/white_pawn.png',
      );
    }

    board[0][0] = Piece(type: PieceType.rook, isWhite: false, image: 'assets/images/black_rook.png');
    board[0][7] = Piece(type: PieceType.rook, isWhite: false, image: 'assets/images/black_rook.png');
    board[7][0] = Piece(type: PieceType.rook, isWhite: true, image: 'assets/images/white_rook.png');
    board[7][7] = Piece(type: PieceType.rook, isWhite: true, image: 'assets/images/white_rook.png');

    board[0][1] = Piece(type: PieceType.knight, isWhite: false, image: 'assets/images/black_knight.png');
    board[0][6] = Piece(type: PieceType.knight, isWhite: false, image: 'assets/images/black_knight.png');
    board[7][1] = Piece(type: PieceType.knight, isWhite: true, image: 'assets/images/white_knight.png');
    board[7][6] = Piece(type: PieceType.knight, isWhite: true, image: 'assets/images/white_knight.png');

    board[0][2] = Piece(type: PieceType.bishop, isWhite: false, image: 'assets/images/black_bishop.png');
    board[0][5] = Piece(type: PieceType.bishop, isWhite: false, image: 'assets/images/black_bishop.png');
    board[7][2] = Piece(type: PieceType.bishop, isWhite: true, image: 'assets/images/white_bishop.png');
    board[7][5] = Piece(type: PieceType.bishop, isWhite: true, image: 'assets/images/white_bishop.png');

    board[0][3] = Piece(type: PieceType.queen, isWhite: false, image: 'assets/images/black_queen.png');
    board[7][3] = Piece(type: PieceType.queen, isWhite: true, image: 'assets/images/white_queen.png');

    board[0][4] = Piece(type: PieceType.king, isWhite: false, image: 'assets/images/black_king.png');
    board[7][4] = Piece(type: PieceType.king, isWhite: true, image: 'assets/images/white_king.png');
  }

  bool isInBounds(int r, int c) => r >= 0 && c >= 0 && r < 8 && c < 8;

  List<List<int>> getValidMoves(int row, int col) {
    final piece = board[row][col];
    if (piece == null) return [];

    if (piece.isWhite != isWhiteTurn) return [];

    return _getMoves(row, col, piece);
  }

  List<List<int>> getRawMoves(int row, int col) {
    final piece = board[row][col];
    if (piece == null) return [];
    return _getMoves(row, col, piece);
  }

  List<List<int>> _getMoves(int row, int col, Piece piece) {
    List<List<int>> moves = [];

    switch (piece.type) {
      case PieceType.pawn:
        int dir = piece.isWhite ? -1 : 1;

        if (isInBounds(row + dir, col) && board[row + dir][col] == null) {
          moves.add([row + dir, col]);

          if ((piece.isWhite && row == 6) || (!piece.isWhite && row == 1)) {
            if (board[row + 2 * dir][col] == null) {
              moves.add([row + 2 * dir, col]);
            }
          }
        }

        for (int dc in [-1, 1]) {
          int r = row + dir;
          int c = col + dc;

          if (isInBounds(r, c) &&
              board[r][c] != null &&
              board[r][c]!.isWhite != piece.isWhite) {
            moves.add([r, c]);
          }
        }
        break;

      case PieceType.rook:
        moves.addAll(_linearMoves(row, col, piece, [
          [1, 0], [-1, 0], [0, 1], [0, -1]
        ]));
        break;

      case PieceType.bishop:
        moves.addAll(_linearMoves(row, col, piece, [
          [1, 1], [1, -1], [-1, 1], [-1, -1]
        ]));
        break;

      case PieceType.queen:
        moves.addAll(_linearMoves(row, col, piece, [
          [1, 0], [-1, 0], [0, 1], [0, -1],
          [1, 1], [1, -1], [-1, 1], [-1, -1]
        ]));
        break;

      case PieceType.knight:
        List<List<int>> kMoves = [
          [2, 1], [2, -1], [-2, 1], [-2, -1],
          [1, 2], [1, -2], [-1, 2], [-1, -2]
        ];
        for (var m in kMoves) {
          int r = row + m[0], c = col + m[1];
          if (isInBounds(r, c) &&
              (board[r][c] == null ||
                  board[r][c]!.isWhite != piece.isWhite)) {
            moves.add([r, c]);
          }
        }
        break;

      case PieceType.king:
        for (int dr = -1; dr <= 1; dr++) {
          for (int dc = -1; dc <= 1; dc++) {
            if (dr == 0 && dc == 0) continue;
            int r = row + dr, c = col + dc;
            if (isInBounds(r, c) &&
                (board[r][c] == null ||
                    board[r][c]!.isWhite != piece.isWhite)) {
              moves.add([r, c]);
            }
          }
        }
        break;
    }

    return moves;
  }

  List<List<int>> _linearMoves(
      int row, int col, Piece piece, List<List<int>> dirs) {
    List<List<int>> moves = [];

    for (var d in dirs) {
      int r = row + d[0], c = col + d[1];

      while (isInBounds(r, c)) {
        if (board[r][c] == null) {
          moves.add([r, c]);
        } else {
          if (board[r][c]!.isWhite != piece.isWhite) {
            moves.add([r, c]);
          }
          break;
        }
        r += d[0];
        c += d[1];
      }
    }

    return moves;
  }

  List<int>? findKing(bool isWhite) {
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final p = board[r][c];
        if (p != null &&
            p.type == PieceType.king &&
            p.isWhite == isWhite) {
          return [r, c];
        }
      }
    }
    return null;
  }

  bool isKingInCheck(bool isWhite) {
    final kingPos = findKing(isWhite);
    if (kingPos == null) return false;

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final p = board[r][c];
        if (p != null && p.isWhite != isWhite) {
          final moves = getRawMoves(r, c);
          for (var m in moves) {
            if (m[0] == kingPos[0] && m[1] == kingPos[1]) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  void movePiece(int fr, int fc, int tr, int tc) {
    final target = board[tr][tc];

    if (target != null && target.type == PieceType.king) {
      gameOver = true;
    }

    board[tr][tc] = board[fr][fc];
    board[fr][fc] = null;

    isWhiteTurn = !isWhiteTurn;
  }
}