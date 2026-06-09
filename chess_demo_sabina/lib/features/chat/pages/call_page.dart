import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/call_manager.dart';
import '../../../core/utils/color_utils.dart';
import './call_ended_page.dart';

class CallPage extends StatefulWidget {
  final String roomId;
  final String remoteUsername;
  final String callType;
  final bool isCaller;
  final bool fromMinimized;

  const CallPage({
    super.key,
    required this.roomId,
    required this.remoteUsername,
    required this.callType,
    required this.isCaller,
    this.fromMinimized = false,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final CallManager _callManager = CallManager();
  final AudioPlayer _audioPlayer = AudioPlayer();
  late AnimationController _pulseController;
  
  static const String dialingToneUrl = 'https://www.soundjay.com/phone/sounds/dial-tone-1.mp3';
  static const String beepUrl = 'https://assets.mixkit.co/active_storage/sfx/2571/2571-preview.mp3';
 
  StreamSubscription? _updateSubscription;
  Timer? _recordTimer;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _renderersInitialized = false;

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    
    _localRenderer.srcObject = _callManager.localStream;
    _remoteRenderer.srcObject = _callManager.remoteStream;
    
    if (mounted) {
      setState(() {
        _renderersInitialized = true;
      });
    }
  }
 
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this)..repeat(reverse: true);
    
    _initRenderers();
    
    _updateSubscription = _callManager.onUpdate.listen((_) {
      if (mounted) {
        setState(() {
          if (_localRenderer.srcObject != _callManager.localStream) {
            _localRenderer.srcObject = _callManager.localStream;
          }
          if (_remoteRenderer.srcObject != _callManager.remoteStream) {
            _remoteRenderer.srcObject = _callManager.remoteStream;
          }
          
          if (_callManager.isRecording && _recordTimer == null) {
            _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
              if (mounted) setState(() {});
            });
          } else if (!_callManager.isRecording && _recordTimer != null) {
            _recordTimer?.cancel();
            _recordTimer = null;
          }
        });
      }
      if (_callManager.roomId == null) {
        // Call ended remotely or locally
        final callDur = _callManager.callDuration;
        final recDur = _callManager.lastRecordingDuration;
        
        if (recDur != null && mounted) {
          _callManager.lastRecordingDuration = null; // Prevent showing twice
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E2C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 28),
                  SizedBox(width: 10),
                  Text('Recording Saved', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
                        Text(
                          _formatDuration(recDur),
                          style: const TextStyle(color: AppColors.secondaryColor, fontSize: 28, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your screen recording was saved successfully.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // close dialog
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => CallEndedPage(remoteUsername: widget.remoteUsername, duration: _formatDuration(callDur))),
                    );
                  },
                  child: const Text('OK', style: TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        } else if (mounted) {
          Navigator.pushReplacement(
            context, 
            MaterialPageRoute(
              builder: (_) => CallEndedPage(
                remoteUsername: widget.remoteUsername, 
                duration: _formatDuration(callDur)
              )
            )
          );
        }
      }
    });
 
    if (!widget.fromMinimized) {
      _init();
    }
  }
 
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint("App Lifecycle State: ${state.name}");
    
    // When app goes to background, we don't want to disconnect.
    // We just log it for now. If you have an Overlay active, it will stay.
    if (state == AppLifecycleState.paused) {
      debugPrint("Call continuing in background...");
    }
  }

  Future<void> _init() async {
    await _callManager.init();
    await _callManager.setupCall(
      roomId: widget.roomId,
      remoteUsername: widget.remoteUsername,
      callType: widget.callType,
      isCaller: widget.isCaller,
    );
    
    if (widget.isCaller) {
      _playSound(dialingToneUrl, loop: true);
    }
  }

  @override
  void didUpdateWidget(CallPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_callManager.isConnected) {
      _stopSound();
    }
  }

  void _endCall() {
    _updateSubscription?.cancel();
    _recordTimer?.cancel();
    if (_callManager.isConnected) {
      _callManager.endCall();
    }
  }

  void _playSound(String url, {bool loop = false}) async { 
    try { 
      await _audioPlayer.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release); 
      await _audioPlayer.play(UrlSource(url)); 
    } catch (e) {} 
  }
  
  void _stopSound() { _audioPlayer.stop(); }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateSubscription?.cancel();
    _recordTimer?.cancel();
    _pulseController.dispose();
    _audioPlayer.dispose();
    
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Shows a premium "Recording Saved" popup dialog
  void _showRecordingSavedDialog(int? durationSecs) {
    final durStr = durationSecs != null ? _formatDuration(durationSecs) : "00:00";
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 28),
            SizedBox(width: 10),
            Text('Recording Saved', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
            const Text(
              'Your screen recording has been saved successfully.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _callManager.minimize(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundColor,
        body: Stack(
          children: [
            // Remote Video
            Positioned.fill(
              child: _renderersInitialized
                  ? RTCVideoView(
                      _remoteRenderer,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Container(color: Colors.black),
            ),
            
            // Audio Call / Placeholder UI
            if (!_callManager.isConnected || 
                !_callManager.remoteVideoEnabled || 
                !_renderersInitialized ||
                _remoteRenderer.srcObject == null ||
                _remoteRenderer.srcObject!.getVideoTracks().isEmpty)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return Container(
                              width: 100 + (_pulseController.value * 50),
                              height: 100 + (_pulseController.value * 50),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.secondaryColor.withOpacity(0.2 * (1 - _pulseController.value)),
                              ),
                            );
                          },
                        ),
                        CircleAvatar(
                          radius: 50, 
                          backgroundColor: AppColors.secondaryColor.withOpacity(0.2), 
                          child: Text(widget.remoteUsername[0].toUpperCase(), style: const TextStyle(fontSize: 40, color: AppColors.secondaryColor, fontWeight: FontWeight.bold))
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    Text(widget.remoteUsername, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        _callManager.isConnected ? _formatDuration(_callManager.callDuration) : _callManager.callStatus, 
                        style: const TextStyle(color: AppColors.secondaryColor, fontSize: 16, fontWeight: FontWeight.w500)
                      ),
                    ),
                    if (_callManager.isRecording && _callManager.recordingStartTime != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _buildRecordingBadge(),
                      ),
                  ],
                ),
              ),

            // Recording indicator overlay for video calls
            if (_callManager.isRecording && _callManager.recordingStartTime != null &&
                _callManager.isConnected && _callManager.remoteVideoEnabled)
              Positioned(
                top: 50,
                left: 0,
                right: 0,
                child: Center(child: _buildRecordingBadge()),
              ),
            
            // Local Video Preview
            if (!_callManager.isCameraOff && _renderersInitialized)
              Positioned(
                top: 50,
                right: 20,
                width: 100,
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                ),
              ),

            // Top Buttons
            Positioned(
              top: 50,
              left: 20,
              child: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 35),
                onPressed: () => _callManager.minimize(context),
              ),
            ),

            // Bottom Controls
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Control buttons row
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _actionBtn(
                          _callManager.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          _callManager.isMuted,
                          _callManager.toggleMic,
                          activeColor: const Color(0xFFFF6B6B),
                          activeIconColor: Colors.white,
                          label: _callManager.isMuted ? 'Unmute' : 'Mute',
                        ),
                        _actionBtn(
                          Icons.volume_up_rounded,
                          _callManager.isSpeakerOn,
                          _callManager.toggleSpeaker,
                          activeColor: const Color(0xFF4ECDC4),
                          activeIconColor: Colors.white,
                          label: 'Speaker',
                        ),
                        // End call - larger, prominent
                        _endCallBtn(),
                        _actionBtn(
                          _callManager.isCameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                          !_callManager.isCameraOff,
                          _callManager.toggleVideo,
                          activeColor: const Color(0xFF45B7D1),
                          activeIconColor: Colors.white,
                          label: 'Camera',
                        ),
                        if (!_callManager.isCameraOff)
                          _actionBtn(
                            Icons.cameraswitch_rounded,
                            false,
                            _callManager.switchCamera,
                            label: 'Flip',
                          ),
                        if (_callManager.isConnected)
                          _actionBtn(
                            _callManager.isRecording ? Icons.stop_circle_rounded : Icons.fiber_manual_record_rounded,
                            _callManager.isRecording,
                            () async {
                              if (_callManager.isRecording) {
                                await _callManager.stopRecording();
                                if (mounted) {
                                  _showRecordingSavedDialog(_callManager.lastRecordingDuration);
                                  _callManager.lastRecordingDuration = null; // Clear so it doesn't show again on call end
                                }
                              } else {
                                await _callManager.startRecording();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Row(
                                        children: [
                                          Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
                                          SizedBox(width: 8),
                                          Text('Screen Recording Started'),
                                        ],
                                      ),
                                      backgroundColor: const Color(0xFF2A2A3A),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  );
                                }
                              }
                            },
                            activeColor: Colors.red,
                            activeIconColor: Colors.white,
                            label: _callManager.isRecording && _callManager.recordingStartTime != null
                                ? _formatDuration(DateTime.now().difference(_callManager.recordingStartTime!).inSeconds)
                                : 'Record',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Recording duration badge widget (reused in audio and video overlays)
  Widget _buildRecordingBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.3), blurRadius: 12, spreadRadius: 1)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
          const SizedBox(width: 6),
          Text(
            "REC ${_formatDuration(DateTime.now().difference(_callManager.recordingStartTime!).inSeconds)}",
            style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  /// End call button with red glow
  Widget _endCallBtn() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 20, spreadRadius: 4)],
      ),
      child: FloatingActionButton(
        heroTag: null,
        onPressed: () async {
          await _callManager.endCall();
        },
        backgroundColor: Colors.red,
        elevation: 12,
        child: const Icon(Icons.call_end_rounded, size: 28, color: Colors.white),
      ),
    );
  }

  Widget _actionBtn(IconData icon, bool active, VoidCallback onTap, {
    Color activeColor = AppColors.secondaryColor,
    Color activeIconColor = Colors.black,
    String? label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: active
                ? [BoxShadow(color: activeColor.withOpacity(0.5), blurRadius: 14, spreadRadius: 1)]
                : [],
          ),
          child: FloatingActionButton(
            mini: true, 
            heroTag: null,
            onPressed: onTap, 
            backgroundColor: active ? activeColor : Colors.white.withOpacity(0.12), 
            elevation: active ? 6 : 0,
            child: Icon(icon, color: active ? activeIconColor : Colors.white70, size: 22),
          ),
        ),
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              label,
              style: TextStyle(color: active ? activeColor : Colors.white54, fontSize: 10, fontWeight: FontWeight.w500),
            ),
          ),
      ],
    );
  }
}
