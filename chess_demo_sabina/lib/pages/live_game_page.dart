import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/board.dart';
import '../models/piece.dart';
import '../utils/color_utils.dart';
import '../utils/const.dart';
import '../widgets/square.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';

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
  bool isSyncing = true;
  bool isOpponentDisconnected = false;
  Timer? _heartbeatTimer;
  int? selectedRow;
  int? selectedCol;
  List<List<int>> validMoves = [];
  bool isWhiteInCheck = false;
  bool isBlackInCheck = false;
  bool showGameStartOverlay = false;
  bool isGameStarted = false;
  Timer? _opponentGraceTimer;
  bool _isGracePeriodActive = false;

  @override
  void initState() {
    super.initState();
    NotificationService().currentGameId = widget.gameId;
    board = Board();
    _connectWebSocket();
  }

  void _connectWebSocket() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('accessToken');
    
    if (token == null) {
      debugPrint("CHESS_ERROR: No access token found for WebSocket");
      return;
    }

    final url = Uri.parse('${AppConstants.webSocketUrl}/game/${widget.gameId}/?token=$token');
    _channel = WebSocketChannel.connect(url);
    
    // 🔹 Add a timeout for synchronization (increased to 60s)
    Timer(const Duration(seconds: 60), () {
      if (mounted && isSyncing) {
        debugPrint("CHESS_ERROR: Sync timed out for game ${widget.gameId}");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Connection timed out. Please try again.")),
        );
        setState(() {
          isSyncing = false;
          isConnected = false;
        });
      }
    });
    
    _channel!.stream.listen(
      (message) {
        final data = jsonDecode(message);
        if (data['type'] == 'pong') return;
        _handleIncomingMessage(data);
      },
      onDone: () {
        if (mounted) {
          setState(() {
            isConnected = false;
            isOpponentDisconnected = true;
          });
        }
      },
      onError: (error) {
        debugPrint("WebSocket Error: $error");
        if (mounted) {
          setState(() {
            isConnected = false;
          });
        }
      },
    );
    
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (isConnected) {
        _channel?.sink.add(jsonEncode({'action': 'ping'}));
      }
    });
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
        _showOpponentLeftPopup();
        break;
        
      case 'player_reconnected':
        _opponentGraceTimer?.cancel();
        setState(() {
          isOpponentDisconnected = false;
          _isGracePeriodActive = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Opponent reconnected!"), backgroundColor: Colors.green),
        );
        break;
        
      case 'game_over':
        _showGameOverDialog(data['reason'], loserUsername: data['loser_username']);
        break;
        
      case 'game_sync':
        final syncData = data['data'];
        final bool opponentOnline = syncData['is_opponent_online'] ?? true;
        
        setState(() {
          board.loadFEN(syncData['fen']);
          isSyncing = false;
          isConnected = true;
          _updateCheckStatus();
          
          if (!opponentOnline) {
            // Start 30s grace period instead of showing banner immediately
            _isGracePeriodActive = true;
            _opponentGraceTimer?.cancel();
            _opponentGraceTimer = Timer(const Duration(seconds: 30), () {
              if (mounted) {
                setState(() {
                  isOpponentDisconnected = true;
                  _isGracePeriodActive = false;
                });
              }
            });
          } else {
            isOpponentDisconnected = false;
            _isGracePeriodActive = false;
            _opponentGraceTimer?.cancel();
            // 🔹 FIX: If opponent is online, the game is effectively started
            if (!isGameStarted) {
              isGameStarted = true;
              showGameStartOverlay = true;
              Timer(const Duration(seconds: 2), () {
                if (mounted) setState(() => showGameStartOverlay = false);
              });
            }
          }
        });

        if (opponentOnline && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Match Ready! Both players connected."),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        break;

      case 'draw_offered':
        _showDrawOfferDialog(data['username']);
        break;

      case 'game_start':
        _opponentGraceTimer?.cancel();
        setState(() {
          isGameStarted = true;
          showGameStartOverlay = true;
          isOpponentDisconnected = false;
          _isGracePeriodActive = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Game Started! Good luck.", style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.green,
          ),
        );
        Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => showGameStartOverlay = false);
        });
        break;
    }
  }

  void _showOpponentLeftPopup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Opponent Left", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Text("${widget.opponentUsername} has left the game session. Waiting for them to return..."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK", style: TextStyle(color: AppColors.secondaryColor)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            child: const Text("Quit to Home", style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  void _updateCheckStatus() {
    isWhiteInCheck = board.isKingInCheck(true);
    isBlackInCheck = board.isKingInCheck(false);
  }

  void onSquareTap(int row, int col) {
    if (board.gameOver || !isGameStarted) return;
    
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
            'fen': board.generateFEN() 
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
    // Navigation will be handled by the game_over signal or manually if needed
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  void _offerDraw() {
    _channel?.sink.add(jsonEncode({'action': 'offer_draw'}));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Draw offer sent")),
    );
  }

  void _showGameOverDialog(String reason, {String? loserUsername}) {
    String title = "Game Over";
    String content = "Reason: $reason";
    
    if (reason == 'resignation') {
      content = "${loserUsername ?? 'Opponent'} resigned. You win!";
    } else if (reason == 'opponent_quit') {
      content = "${loserUsername ?? 'Opponent'} quit the game. You win!";
    } else if (reason == 'draw_accepted') {
      content = "Draw agreed.";
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold)),
        content: Text(content, style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
            child: const Text("Back to Home", style: TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDrawOfferDialog(String? username) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        title: const Text("Draw Offer", style: TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold)),
        content: Text("${username ?? widget.opponentUsername} offered a draw. Accept?", style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _channel?.sink.add(jsonEncode({'action': 'decline_draw'}));
            },
            child: const Text("Decline", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _channel?.sink.add(jsonEncode({'action': 'accept_draw'}));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("Accept", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    if (NotificationService().currentGameId == widget.gameId) {
      NotificationService().currentGameId = null;
    }
    _opponentGraceTimer?.cancel();
    _heartbeatTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final bool shouldQuit = await _showQuitConfirmation() ?? false;
        if (shouldQuit && context.mounted) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      },
      child: Scaffold(
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
                    title: const Text("Resign?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    content: const Text("Are you sure you want to resign this game?", style: TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
                      TextButton(onPressed: () {
                        Navigator.pop(context);
                        _resign();
                      }, child: const Text("Resign", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
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
          child: Stack(
            children: [
              if (isSyncing)
                const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: AppColors.secondaryColor),
                      SizedBox(height: 20),
                      Text("Synchronizing board...", style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                )
              else
                Column(
                  children: [
                    // ── Opponent Info ──
                    _buildPlayerHeader(widget.opponentUsername, widget.userColor != 'white'),
                    
                    if (isOpponentDisconnected && !_isGracePeriodActive)
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
              if (showGameStartOverlay)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "GAME START",
                          style: TextStyle(
                            color: AppColors.secondaryColor,
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "${widget.userColor.toUpperCase()} vs ${widget.opponentUsername.toUpperCase()}",
                          style: const TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _showQuitConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Quit Game?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to leave the game? This will count as a forfeit if you don't return quickly."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Stay", style: TextStyle(color: AppColors.secondaryColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Quit", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
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
