import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/board.dart';
import '../models/piece.dart';
import '../utils/color_utils.dart';
import '../utils/const.dart';
import '../widgets/square.dart';

class LiveGamePage extends StatefulWidget {
  final String gameId;
  final int opponentId;
  final String opponentUsername;
  final String userColor; // 'white' or 'black'

  const LiveGamePage({
    super.key,
    required this.gameId,
    required this.opponentId,
    required this.opponentUsername,
    required this.userColor,
  });

  @override
  State<LiveGamePage> createState() => _LiveGamePageState();
}

class _LiveGamePageState extends State<LiveGamePage> {
  late Board board;
  WebSocketChannel? _channel;
  bool isConnected = false;
  bool isOpponentDisconnected = false;
  int? selectedRow;
  int? selectedCol;
  List<List<int>> validMoves = [];
  bool isWhiteInCheck = false;
  bool isBlackInCheck = false;

  @override
  void initState() {
    super.initState();
    board = Board();
    _connectWebSocket();
  }

  void _connectWebSocket() {
    final url = Uri.parse('${AppConstants.webSocketUrl}/game/${widget.gameId}/');
    _channel = WebSocketChannel.connect(url);
    
    _channel!.stream.listen(
      (message) {
        final data = jsonDecode(message);
        _handleIncomingMessage(data);
      },
      onDone: () {
        if (mounted) {
          setState(() {
            isConnected = false;
            isOpponentDisconnected = true;
          });
          // Try to reconnect? For now, just show disconnected
        }
      },
      onError: (error) {
        debugPrint("WebSocket Error: $error");
      },
    );
    
    setState(() => isConnected = true);
  }

  void _handleIncomingMessage(Map<String, dynamic> data) {
    if (!mounted) return;

    switch (data['type']) {
      case 'move':
        final moveStr = data['move'] as String; // e.g. "6444"
        final fromRow = int.parse(moveStr[0]);
        final fromCol = int.parse(moveStr[1]);
        final toRow = int.parse(moveStr[2]);
        final toCol = int.parse(moveStr[3]);
        
        setState(() {
          board.movePiece(fromRow, fromCol, toRow, toCol);
          _updateCheckStatus();
        });
        break;
        
      case 'opponent_disconnected':
        setState(() => isOpponentDisconnected = true);
        break;
        
      case 'opponent_reconnected':
        setState(() => isOpponentDisconnected = false);
        break;
        
      case 'game_over':
        _showGameOverDialog(data['reason']);
        break;
        
      case 'draw_offered':
        _showDrawOfferDialog();
        break;
    }
  }

  void _updateCheckStatus() {
    isWhiteInCheck = board.isKingInCheck(true);
    isBlackInCheck = board.isKingInCheck(false);
  }

  void onSquareTap(int row, int col) {
    if (board.gameOver) return;
    
    // Check if it's the user's turn
    bool isUserWhite = widget.userColor == 'white';
    if (board.isWhiteTurn != isUserWhite) return;

    setState(() {
      if (selectedRow == null) {
        final piece = board.board[row][col];
        if (piece != null && piece.isWhite == isUserWhite) {
          selectedRow = row;
          selectedCol = col;
          validMoves = board.getValidMoves(row, col);
        }
      } else {
        bool isValid = validMoves.any((m) => m[0] == row && m[1] == col);

        if (isValid) {
          final moveStr = "$selectedRow$selectedCol$row$col";
          
          // Apply locally
          board.movePiece(selectedRow!, selectedCol!, row, col);
          _updateCheckStatus();
          
          // Send to server
          _channel?.sink.add(jsonEncode({
            'action': 'move',
            'move': moveStr,
            'fen': 'placeholder' // Fen update handled by server mostly, but could send here
          }));
          
          if (board.gameOver) {
            _showGameOverDialog('king_captured');
          }
        }

        selectedRow = null;
        selectedCol = null;
        validMoves = [];
      }
    });
  }

  void _resign() {
    _channel?.sink.add(jsonEncode({'action': 'resign'}));
  }

  void _offerDraw() {
    _channel?.sink.add(jsonEncode({'action': 'offer_draw'}));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Draw offer sent")),
    );
  }

  void _showGameOverDialog(String reason) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Game Over", style: TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold)),
        content: Text("Reason: $reason", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
            child: const Text("Back to Home", style: TextStyle(color: AppColors.secondaryColor)),
          ),
        ],
      ),
    );
  }

  void _showDrawOfferDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        title: const Text("Draw Offer", style: TextStyle(color: AppColors.secondaryColor)),
        content: Text("${widget.opponentUsername} offered a draw. Accept?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Decline", style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _channel?.sink.add(jsonEncode({'action': 'accept_draw'}));
            },
            child: const Text("Accept"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text("Live Chess", style: TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.surfaceColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_rounded, color: Colors.redAccent),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: AppColors.surfaceColor,
                  title: const Text("Resign?", style: TextStyle(color: Colors.white)),
                  content: const Text("Are you sure you want to resign this game?"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                    TextButton(onPressed: () {
                      Navigator.pop(context);
                      _resign();
                    }, child: const Text("Resign", style: TextStyle(color: Colors.redAccent))),
                  ],
                ),
              );
            },
            tooltip: "Resign",
          ),
          IconButton(
            icon: const Icon(Icons.handshake_rounded, color: Colors.amber),
            onPressed: _offerDraw,
            tooltip: "Offer Draw",
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.woodGradient,
          ),
        ),
        child: Column(
          children: [
            // ── Opponent Info ──
            _buildPlayerHeader(widget.opponentUsername, widget.userColor != 'white'),
            
            if (isOpponentDisconnected)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: Colors.redAccent.withOpacity(0.8),
                child: const Text(
                  "Opponent disconnected. Waiting...",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),

            const Spacer(),
            
            // ── The Board ──
            _buildBoard(),

            const Spacer(),
            
            // ── User Info ──
            _buildPlayerHeader("You", widget.userColor == 'white'),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerHeader(String name, bool isWhite) {
    bool isTurn = board.isWhiteTurn == isWhite;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isTurn ? AppColors.secondaryColor : Colors.transparent,
                width: 2,
              ),
            ),
            child: CircleAvatar(
              backgroundColor: Colors.white10,
              child: Text(name[0].toUpperCase(), style: const TextStyle(color: AppColors.secondaryColor)),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: isTurn ? FontWeight.bold : FontWeight.normal,
                  fontSize: 18,
                ),
              ),
              Text(
                isWhite ? "White" : "Black",
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          if (isTurn) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.secondaryColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text("THINKING", style: TextStyle(color: AppColors.secondaryColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBoard() {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.secondaryColor, width: 4),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, spreadRadius: 5),
          ],
        ),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 64,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
          itemBuilder: (context, index) {
            // Flip board for black player
            int displayIndex = widget.userColor == 'black' ? 63 - index : index;
            int row = displayIndex ~/ 8;
            int col = displayIndex % 8;

            bool isWhite = (row + col) % 2 == 0;
            final piece = board.board[row][col];
            
            bool isCheckSquare = false;
            if (piece != null && piece.type == PieceType.king) {
              if (piece.isWhite && isWhiteInCheck) isCheckSquare = true;
              if (!piece.isWhite && isBlackInCheck) isCheckSquare = true;
            }

            return Square(
              isWhite: isWhite,
              piece: piece,
              isHighlighted: validMoves.any((m) => m[0] == row && m[1] == col),
              isCheck: isCheckSquare,
              onTap: () => onSquareTap(row, col),
            );
          },
        ),
      ),
    );
  }
}
