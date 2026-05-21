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
  
  static const String ringingUrl = 'https://assets.mixkit.co/active_storage/sfx/2358/2358-preview.mp3';
  static const String beepUrl = 'https://assets.mixkit.co/active_storage/sfx/2571/2571-preview.mp3';
 
  StreamSubscription? _updateSubscription;

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
        });
      }
      if (_callManager.roomId == null) {
        // Call ended remotely or locally
        Navigator.pushReplacement(
          context, 
          MaterialPageRoute(
            builder: (_) => CallEndedPage(
              remoteUsername: widget.remoteUsername, 
              duration: _formatDuration(_callManager.callDuration)
            )
          )
        );
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
      _playSound(ringingUrl, loop: true);
    }
  }

  @override
  void didUpdateWidget(CallPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_callManager.isConnected) {
      _stopSound();
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
                  ],
                ),
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
              bottom: 50,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _actionBtn(Icons.mic_off, _callManager.isMuted, _callManager.toggleMic),
                  _actionBtn(Icons.volume_up, _callManager.isSpeakerOn, _callManager.toggleSpeaker),
                  FloatingActionButton(
                    onPressed: () {
                      _callManager.endCall();
                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CallEndedPage(remoteUsername: widget.remoteUsername, duration: _formatDuration(_callManager.callDuration))));
                    },
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.call_end, size: 30),
                  ),
                  _actionBtn(Icons.videocam_off, _callManager.isCameraOff, _callManager.toggleVideo),
                  if (!_callManager.isCameraOff)
                    _actionBtn(Icons.cameraswitch, false, _callManager.switchCamera),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, bool active, VoidCallback onTap) {
    return FloatingActionButton(
      mini: true, 
      heroTag: null,
      onPressed: onTap, 
      backgroundColor: active ? AppColors.secondaryColor : Colors.white24, 
      child: Icon(icon, color: active ? Colors.black : Colors.white)
    );
  }
}
