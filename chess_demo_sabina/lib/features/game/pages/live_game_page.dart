import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/board.dart';
import '../models/piece.dart';
import '../../../core/utils/color_utils.dart';
import '../../../core/utils/const.dart';
import '../widgets/square.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/notification_service.dart';
import '../services/game_media_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

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
  bool showGameStartOverlay = true;
  bool isGameStarted = false;
  Timer? _opponentGraceTimer;
  bool _isGracePeriodActive = false;
  
  // 🎙️ Media Signaling
  final GameMediaService _mediaService = GameMediaService();
  bool isMicMuted = true;
  bool isVideoEnabled = false;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  StreamSubscription? _videoRequestSub;
  StreamSubscription? _videoResponseSub;
  bool isRecording = false;

  @override
  void initState() {
    super.initState();
    NotificationService().currentGameId = widget.gameId;
    board = Board();
    
    // 🎙️ Initialize Renderers
    _initializeRenderers();
    
    _connectWebSocket();

    // 🔹 Hide Game Start overlay after 1.5 seconds
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => showGameStartOverlay = false);
      }
    });
  }

  Future<void> _initializeRenderers() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      debugPrint("GAME_MEDIA_UI: Renderers initialized successfully");
      
      if (_mediaService.localStreamNotifier.value != null) {
        debugPrint("GAME_MEDIA_UI: Setting initial local stream: ${_mediaService.localStreamNotifier.value?.id}");
        _localRenderer.srcObject = _mediaService.localStreamNotifier.value;
      }
      if (_mediaService.remoteStreamNotifier.value != null) {
        debugPrint("GAME_MEDIA_UI: Setting initial remote stream: ${_mediaService.remoteStreamNotifier.value?.id}");
        _remoteRenderer.srcObject = _mediaService.remoteStreamNotifier.value;
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("GAME_MEDIA_ERROR: Renderer initialization failed: $e");
    }
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
    
    // 🎙️ Initialize Media Signaling
    // Attach listeners BEFORE connecting to avoid race conditions
    _mediaService.localStreamNotifier.addListener(() {
      debugPrint("GAME_MEDIA_UI: Local stream updated: ${_mediaService.localStreamNotifier.value?.id}");
      _localRenderer.srcObject = _mediaService.localStreamNotifier.value;
      if (mounted) setState(() {});
    });

    _mediaService.remoteStreamNotifier.addListener(() {
      debugPrint("GAME_MEDIA_UI: Remote stream updated: ${_mediaService.remoteStreamNotifier.value?.id}");
      _remoteRenderer.srcObject = _mediaService.remoteStreamNotifier.value;
      if (mounted) setState(() {});
    });

    _mediaService.isRecordingNotifier.addListener(() {
      if (mounted) {
        setState(() {
          isRecording = _mediaService.isRecordingNotifier.value;
        });
      }
    });

    _videoRequestSub = _mediaService.onVideoRequest.listen((_) {
      _showVideoRequestDialog();
    });

    bool isCaller = widget.userColor == 'white';
    _mediaService.connect(widget.gameId, token, isCaller);

    _videoResponseSub = _mediaService.onVideoResponse.listen((accepted) {
      debugPrint("GAME_MEDIA_UI: Received video response: $accepted");
      if (accepted) {
        setState(() => isVideoEnabled = true);
        _mediaService.toggleVideo(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Opponent accepted video call!")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Opponent declined video call.")),
        );
      }
    });
    
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
          isOpponentDisconnected = false;
          _isGracePeriodActive = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Game Started! Good luck.", style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.green,
          ),
        );
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
            // 🔹 Notify server that game is over
            _channel?.sink.add(jsonEncode({
              'action': 'game_over',
              'reason': 'king_captured',
              'winner_id': widget.userColor == 'white' ? null : null, // Backend handles IDs
            }));
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
    } else if (reason == 'king_captured') {
      content = "The King has been captured! Game Over.";
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
    NotificationService().currentGameId = null;
    _opponentGraceTimer?.cancel();
    _heartbeatTimer?.cancel();
    _channel?.sink.close();
    _videoRequestSub?.cancel();
    _videoResponseSub?.cancel();
    _mediaService.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
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
            if (!isVideoEnabled) ...[
              IconButton(
                icon: Icon(
                  isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  color: isMicMuted ? Colors.white54 : Colors.greenAccent,
                  shadows: isMicMuted ? [] : [Shadow(color: Colors.greenAccent.withOpacity(0.6), blurRadius: 12)],
                ),
                onPressed: () {
                  setState(() => isMicMuted = !isMicMuted);
                  _mediaService.toggleMic(!isMicMuted);
                },
              ),
              IconButton(
                icon: Icon(
                  isVideoEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                  color: isVideoEnabled ? Colors.cyanAccent : Colors.white54,
                  shadows: isVideoEnabled ? [Shadow(color: Colors.cyanAccent.withOpacity(0.6), blurRadius: 12)] : [],
                ),
                onPressed: _handleVideoToggle,
              ),
              if (isConnected) // Both users on call/game
                IconButton(
                  icon: Icon(
                    isRecording ? Icons.stop_circle_rounded : Icons.fiber_manual_record_rounded,
                    color: isRecording ? Colors.red : Colors.white54,
                    size: isRecording ? 30 : 24,
                    shadows: isRecording ? [Shadow(color: Colors.red.withOpacity(0.8), blurRadius: 16)] : [],
                  ),
                  onPressed: () async {
                    if (_mediaService.isRecordingNotifier.value) {
                      await _mediaService.stopRecording(widget.opponentUsername);
                      final durSecs = _mediaService.lastRecordingDuration ?? 0;
                      final durStr = '${(durSecs ~/ 60).toString().padLeft(2, '0')}:${(durSecs % 60).toString().padLeft(2, '0')}';
                      if (mounted) {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            backgroundColor: const Color(0xFF1E1E2C),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: Row(
                              children: [
                                Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 28),
                                const SizedBox(width: 10),
                                const Text('Recording Saved', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.timer_rounded, color: AppColors.secondaryColor, size: 22),
                                      const SizedBox(width: 8),
                                      Text(durStr, style: const TextStyle(color: AppColors.secondaryColor, fontSize: 28, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text('Your screen recording has been saved successfully.', style: TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('OK', style: TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                      }
                    } else {
                      await _mediaService.startRecording();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
                              const SizedBox(width: 8),
                              const Text('Screen Recording Started'),
                            ],
                          ),
                          backgroundColor: const Color(0xFF2A2A3A),
                        ),
                      );
                    }
                  },
                ),
            ],
            const SizedBox(width: 8),
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
                    
                    // 🎥 Video Call Row
                    _buildVideoRow(),

                    // ── The Board ──
                    _buildBoard(),
        
                    const Spacer(),
                    
                    // ── User Info ──
                    _buildPlayerHeader("You", widget.userColor == 'white'),
                    
                    const SizedBox(height: 20),
                  ],
                ),
              if (showGameStartOverlay)
                _buildGameStartOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactControl({required IconData icon, required bool isActive, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isActive ? Colors.black54 : Colors.redAccent.withOpacity(0.7),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildVideoBox({required RTCVideoRenderer renderer, required bool isEnabled, required bool isLocal}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLocal 
            ? (isEnabled ? Colors.greenAccent.withOpacity(0.5) : Colors.white10) 
            : (isEnabled ? AppColors.secondaryColor.withOpacity(0.5) : Colors.white10),
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            // Video View or Placeholder
            if (isEnabled && renderer.srcObject != null)
              RTCVideoView(
                renderer,
                key: ValueKey('${isLocal ? 'local' : 'remote'}_${renderer.srcObject?.id}'),
                mirror: isLocal,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isLocal ? Icons.person_rounded : Icons.account_circle_rounded, 
                      color: Colors.white12, 
                      size: 48
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isEnabled ? "Connecting..." : (isLocal ? "Your Video Off" : "Opponent Video Off"),
                      style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            
            // Icons Overlay (On both for status, controls only on local)
            Positioned(
              top: 8,
              right: 8,
              child: isLocal 
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildCompactControl(
                        icon: isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        isActive: !isMicMuted,
                        onTap: () {
                          setState(() => isMicMuted = !isMicMuted);
                          _mediaService.toggleMic(!isMicMuted);
                        },
                      ),
                      const SizedBox(width: 6),
                      _buildCompactControl(
                        icon: isVideoEnabled ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                        isActive: false,
                        onTap: _handleVideoToggle,
                      ),
                      if (isConnected) ...[
                        const SizedBox(width: 6),
                        _buildCompactControl(
                          icon: isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                          isActive: isRecording,
                          onTap: () async {
                            if (_mediaService.isRecordingNotifier.value) {
                              await _mediaService.stopRecording(widget.opponentUsername);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Recording Saved to Database')),
                              );
                            } else {
                              await _mediaService.startRecording();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Recording Started')),
                              );
                            }
                          },
                        ),
                      ],
                    ],
                  )
                : (isEnabled 
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.live_tv_rounded, color: Colors.redAccent, size: 12),
                            const SizedBox(width: 4),
                            Text(widget.opponentUsername, style: const TextStyle(color: Colors.white, fontSize: 10)),
                          ],
                        ),
                      )
                    : const SizedBox.shrink()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoRow() {
    return ValueListenableBuilder<bool>(
      valueListenable: _mediaService.isOpponentVideoEnabled,
      builder: (context, opponentVideoEnabled, _) {
        if (!isVideoEnabled && !opponentVideoEnabled) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SizedBox(
            height: 140, 
            child: Row(
              children: [
                if (opponentVideoEnabled)
                  Expanded(
                    child: _buildVideoBox(
                      renderer: _remoteRenderer,
                      isEnabled: opponentVideoEnabled,
                      isLocal: false,
                    ),
                  ),
                if (opponentVideoEnabled && isVideoEnabled)
                  const SizedBox(width: 12),
                if (isVideoEnabled)
                  Expanded(
                    child: _buildVideoBox(
                      renderer: _localRenderer,
                      isEnabled: isVideoEnabled,
                      isLocal: true,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleVideoToggle() {
    if (isVideoEnabled) {
      setState(() => isVideoEnabled = false);
      _mediaService.toggleVideo(false);
    } else {
      // Send request to other player
      _mediaService.requestVideo();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Video call request sent to opponent...")),
      );
    }
  }

  void _showVideoRequestDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        title: const Text("Video Call Request", style: TextStyle(color: Colors.white)),
        content: const Text("Your opponent wants to start a video call. Do you want to join?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _mediaService.respondVideo(false);
            },
            child: const Text("Decline", style: TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _mediaService.respondVideo(true);
              setState(() => isVideoEnabled = true);
              _mediaService.toggleVideo(true);
            },
            child: const Text("Accept", style: TextStyle(color: Colors.greenAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildGameStartOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 500),
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: Opacity(
                opacity: value,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: AppColors.woodGradient),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.secondaryColor, width: 2),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, spreadRadius: 5),
                    ],
                  ),
                  child: const Text(
                    "GAME STARTED",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
                ),
              ),
            );
          },
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
        content: const Text(
          "Are you sure you want to leave the game? This will count as a forfeit if you don't return quickly.",
          style: TextStyle(color: Colors.white70),
        ),
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
