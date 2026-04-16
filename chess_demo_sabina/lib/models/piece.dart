enum PieceType { pawn, rook, knight, bishop, queen, king }

class Piece {
  final PieceType type;
  final bool isWhite;
  String image;

  Piece({
    required this.type,
    required this.isWhite,
    required this.image,
  });
}