import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/signaling_service.dart';
import '../utils/color_utils.dart';

class CallPage extends StatefulWidget {
  final String roomId;
  final String remoteUsername;
  final String callType; // 'audio' or 'video'
  final bool isCaller;

  const CallPage({
    super.key,
    required this.roomId,
    required this.remoteUsername,
    required this.callType,
    required this.isCaller,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> with TickerProviderStateMixin {
  // WebRTC
  RTCPeerConnection? _peerConnection;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  // UI State
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isCameraOff = false;
  bool _isConnected = false;
  bool _isConnecting = true;
  String _callStatus = 'Connecting...';
  int _callDuration = 0;

  // Signaling
  Timer? _signalPollTimer;
  Timer? _durationTimer;
  String? _accessToken;
  bool _disposed = false;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ICE Servers (Google's free STUN)
  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ]
  };

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initCall();
  }

  Future<void> _initCall() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('accessToken');

    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    await _createLocalStream();
    await _createPeerConnection();

    if (widget.isCaller) {
      setState(() => _callStatus = 'Calling ${widget.remoteUsername}...');
      await _createOffer();
    } else {
      setState(() => _callStatus = 'Connecting...');
    }

    // Start polling for signals
    _signalPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollSignals(),
    );
  }

  Future<void> _createLocalStream() async {
    final Map<String, dynamic> constraints = {
      'audio': true,
      'video': widget.callType == 'video'
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      _localRenderer.srcObject = _localStream;
      setState(() {});
    } catch (e) {
      debugPrint('Error getting user media: $e');
      if (mounted) {
        setState(() => _callStatus = 'Camera/Mic permission denied');
      }
    }
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceServers);

    // Add local tracks to peer connection
    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    // Listen for remote tracks
    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        _remoteRenderer.srcObject = _remoteStream;
        if (mounted) {
          setState(() {
            _isConnected = true;
            _isConnecting = false;
            _callStatus = 'Connected';
          });
          _startDurationTimer();
        }
      }
    };

    // Listen for ICE candidates
    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (_accessToken != null) {
        SignalingService.sendSignal(
          _accessToken!,
          widget.roomId,
          'candidate',
          {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        );
      }
    };

    // Connection state monitoring
    _peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      if (mounted) {
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            setState(() {
              _isConnected = true;
              _isConnecting = false;
              _callStatus = 'Connected';
            });
            _startDurationTimer();
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            setState(() {
              _callStatus = 'Call ended';
              _isConnected = false;
            });
            break;
          default:
            break;
        }
      }
    };
  }

  Future<void> _createOffer() async {
    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    if (_accessToken != null) {
      await SignalingService.sendSignal(
        _accessToken!,
        widget.roomId,
        'offer',
        {'sdp': offer.sdp, 'type': offer.type},
      );
    }
  }

  Future<void> _createAnswer() async {
    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    if (_accessToken != null) {
      await SignalingService.sendSignal(
        _accessToken!,
        widget.roomId,
        'answer',
        {'sdp': answer.sdp, 'type': answer.type},
      );
    }
  }

  Future<void> _pollSignals() async {
    if (_disposed || _accessToken == null) return;

    final result = await SignalingService.getSignals(
      _accessToken!,
      widget.roomId,
    );

    if (!result['success'] || _disposed) return;

    final data = result['data'];

    // Check if call was ended by the other party
    if (data['room_status'] == 'ended' || data['room_status'] == 'rejected') {
      _endCall(navigateBack: true, notifyServer: false);
      return;
    }

    final signals = data['signals'] as List;
    for (final signal in signals) {
      final signalType = signal['signal_type'];
      final signalData = signal['data'];

      switch (signalType) {
        case 'offer':
          await _peerConnection?.setRemoteDescription(
            RTCSessionDescription(signalData['sdp'], signalData['type']),
          );
          await _createAnswer();
          break;

        case 'answer':
          await _peerConnection?.setRemoteDescription(
            RTCSessionDescription(signalData['sdp'], signalData['type']),
          );
          if (mounted) {
            setState(() {
              _isConnecting = false;
              _callStatus = 'Ringing...';
            });
          }
          break;

        case 'candidate':
          await _peerConnection?.addCandidate(
            RTCIceCandidate(
              signalData['candidate'],
              signalData['sdpMid'],
              signalData['sdpMLineIndex'],
            ),
          );
          break;
      }
    }
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _callDuration++);
      }
    });
    _pulseController.stop();
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    _localStream?.getAudioTracks().forEach((track) {
      // WebRTC handles speaker routing via helper
      Helper.setSpeakerphoneOn(_isSpeakerOn);
    });
  }

  void _toggleCamera() {
    setState(() => _isCameraOff = !_isCameraOff);
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = !_isCameraOff;
    });
  }

  void _switchCamera() {
    _localStream?.getVideoTracks().forEach((track) {
      Helper.switchCamera(track);
    });
  }

  Future<void> _endCall({
    bool navigateBack = true,
    bool notifyServer = true,
  }) async {
    if (_disposed) return;
    _disposed = true;

    _signalPollTimer?.cancel();
    _durationTimer?.cancel();

    // Notify server
    if (notifyServer && _accessToken != null) {
      await SignalingService.endCall(_accessToken!, widget.roomId);
    }

    // Clean up WebRTC
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _remoteStream?.dispose();
    await _peerConnection?.close();
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();

    if (navigateBack && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    if (!_disposed) {
      _endCall(navigateBack: false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callType == 'video';

    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppColors.woodGradient,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // ── Video Views (for video calls) ──
              if (isVideo) ...[
                // Remote video (full screen)
                if (_isConnected && _remoteStream != null)
                  Positioned.fill(
                    child: RTCVideoView(
                      _remoteRenderer,
                      objectFit: RTCVideoViewObjectFit
                          .RTCVideoViewObjectFitCover,
                    ),
                  ),

                // Local video (small overlay)
                if (_localStream != null &&
                    !_isCameraOff)
                  Positioned(
                    top: 20,
                    right: 20,
                    width: 120,
                    height: 170,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.secondaryColor,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: RTCVideoView(
                          _localRenderer,
                          mirror: true,
                          objectFit: RTCVideoViewObjectFit
                              .RTCVideoViewObjectFitCover,
                        ),
                      ),
                    ),
                  ),
              ],

              // ── Audio Call / Connecting UI ──
              if (!isVideo || !_isConnected)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Pulsing avatar
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _isConnected ? 1.0 : _pulseAnimation.value,
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    AppColors.primaryColor,
                                    AppColors.secondaryColor,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.secondaryColor
                                        .withOpacity(0.4),
                                    blurRadius: 30,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  widget.remoteUsername[0].toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      // Remote username
                      Text(
                        widget.remoteUsername,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Call status / duration
                      Text(
                        _isConnected
                            ? _formatDuration(_callDuration)
                            : _callStatus,
                        style: TextStyle(
                          fontSize: 16,
                          color: _isConnected
                              ? Colors.greenAccent
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Call type badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.secondaryColor.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isVideo ? Icons.videocam : Icons.call,
                              size: 16,
                              color: AppColors.secondaryColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isVideo ? 'Video Call' : 'Audio Call',
                              style: const TextStyle(
                                color: AppColors.secondaryColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Call Controls ──
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    // Connected status text for video
                    if (isVideo && _isConnected)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          _formatDuration(_callDuration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Mute
                        _controlButton(
                          icon: _isMuted ? Icons.mic_off : Icons.mic,
                          label: _isMuted ? 'Unmute' : 'Mute',
                          color: _isMuted
                              ? Colors.redAccent
                              : Colors.white.withOpacity(0.2),
                          onTap: _toggleMute,
                        ),

                        // Speaker
                        _controlButton(
                          icon: _isSpeakerOn
                              ? Icons.volume_up
                              : Icons.volume_off,
                          label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
                          color: _isSpeakerOn
                              ? AppColors.secondaryColor.withOpacity(0.3)
                              : Colors.white.withOpacity(0.2),
                          onTap: _toggleSpeaker,
                        ),

                        // End call
                        _controlButton(
                          icon: Icons.call_end,
                          label: 'End',
                          color: Colors.redAccent,
                          size: 64,
                          iconSize: 32,
                          onTap: () => _endCall(),
                        ),

                        // Camera toggle (video only)
                        if (isVideo)
                          _controlButton(
                            icon: _isCameraOff
                                ? Icons.videocam_off
                                : Icons.videocam,
                            label: _isCameraOff ? 'Camera On' : 'Camera Off',
                            color: _isCameraOff
                                ? Colors.redAccent
                                : Colors.white.withOpacity(0.2),
                            onTap: _toggleCamera,
                          ),

                        // Switch camera (video only)
                        if (isVideo)
                          _controlButton(
                            icon: Icons.cameraswitch_rounded,
                            label: 'Switch',
                            color: Colors.white.withOpacity(0.2),
                            onTap: _switchCamera,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    double size = 52,
    double iconSize = 24,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.15),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}
