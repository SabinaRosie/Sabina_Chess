import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:audioplayers/audioplayers.dart';
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

class _CallPageState extends State<CallPage> with SingleTickerProviderStateMixin {
  // WebRTC
  RTCPeerConnection? _peerConnection;
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;
  MediaStream? _localStream;

  // UI State
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isCameraOff = false;
  bool _isConnected = false;
  String _callStatus = 'Initializing...';
  int _callDuration = 0;
  bool _hasError = false;
  bool _offerSent = false;
  final List<RTCIceCandidate> _remoteCandidates = [];

  // Signaling
  Timer? _signalPollTimer;
  Timer? _durationTimer;
  bool _disposed = false;
  bool _renderersInitialized = false;

  // Audio UX
  final AudioPlayer _audioPlayer = AudioPlayer();
  static const String ringingUrl = 'https://assets.mixkit.co/active_storage/sfx/2358/2358-preview.mp3';
  static const String beepUrl = 'https://assets.mixkit.co/active_storage/sfx/2571/2571-preview.mp3';

  // Animation
  late AnimationController _pulseController;

  // 🔹 STUN + TURN Servers (OpenRelay for NAT bypass)
  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:openrelay.metered.ca:80'},
      {'urls': 'turn:openrelay.metered.ca:80', 'username': 'openrelay', 'credential': 'openrelay'},
      {'urls': 'turn:openrelay.metered.ca:443', 'username': 'openrelay', 'credential': 'openrelay'},
    ]
  };

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _audioPlayer.setVolume(1.0);
    _joinChannel();
  }

  /// 🔹 Agora-style: Initialize and Join Call
  Future<void> _joinChannel() async {
    try {
      _setStatus('Joining channel...');

      _localRenderer = RTCVideoRenderer();
      _remoteRenderer = RTCVideoRenderer();
      await _localRenderer!.initialize();
      await _remoteRenderer!.initialize();
      _renderersInitialized = true;

      await _setupLocalMedia();

      if (_localStream == null) {
        _setStatus('Media access failed');
        _hasError = true;
        return;
      }

      await _createPeerConnection();

      if (_peerConnection == null) {
        _setStatus('RTC Engine Error');
        _hasError = true;
        return;
      }

      // 🔊 Play Ringing sound if I'm the caller
      if (widget.isCaller) {
        _setStatus('Ringing ${widget.remoteUsername}...');
        _playSound(ringingUrl, loop: true);
      } else {
        _setStatus('Connecting...');
      }

      // 🔹 High-frequency signaling (800ms) for fast handshake
      _signalPollTimer = Timer.periodic(
        const Duration(milliseconds: 800),
        (_) => _pollSignals(),
      );

      _onJoinChannelSuccess();
    } catch (e) {
      debugPrint('Join channel error: $e');
      _setStatus('Connection failed');
      _hasError = true;
    }
  }

  /// 🔹 Listener: Join Channel Success
  void _onJoinChannelSuccess() {
    debugPrint('Successfully joined channel: ${widget.roomId}');
  }

  /// 🔹 Listener: Remote User Joined
  void _onUserJoined() {
    debugPrint('User joined: ${widget.remoteUsername}');
    _stopSound(); // Stop ringing
    _playSound(beepUrl); // Play connect beep
    if (mounted) {
      setState(() {
        _isConnected = true;
        _callStatus = 'Connected';
      });
    }
    _startDurationTimer();
  }

  /// 🔹 Listener: User Offline / End Call
  void _onUserOffline() {
    debugPrint('User offline / Call ended');
    _playSound(beepUrl); // Play disconnect beep
    _setStatus('Call ended');
    Future.delayed(const Duration(milliseconds: 500), () => _leaveChannel(notifyServer: false));
  }

  Future<void> _playSound(String url, {bool loop = false}) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      debugPrint('Audio Playback Error: $e');
    }
  }

  void _stopSound() {
    _audioPlayer.stop();
  }

  void _setStatus(String status) {
    if (mounted && !_disposed) {
      setState(() => _callStatus = status);
    }
  }

  Future<void> _setupLocalMedia() async {
    final Map<String, dynamic> constraints = {
      'audio': true,
      'video': widget.callType == 'video'
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    };
    try {
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      if (_localRenderer != null && _renderersInitialized) {
        _localRenderer!.srcObject = _localStream;
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Media Error: $e');
      _setStatus('Permission denied');
    }
  }

  Future<void> _createPeerConnection() async {
    try {
      _peerConnection = await createPeerConnection(_iceServers);

      if (_localStream != null) {
        for (var track in _localStream!.getTracks()) {
          await _peerConnection!.addTrack(track, _localStream!);
        }
      }

      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty && mounted && !_disposed) {
          if (_remoteRenderer != null && _renderersInitialized) {
            _remoteRenderer!.srcObject = event.streams[0];
          }
          if (!_isConnected) _onUserJoined();
        }
      };

      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (!_disposed) {
          SignalingService.sendSignal(
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

      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        if (!mounted || _disposed) return;
        debugPrint('RTC Engine State: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          if (!_isConnected) _onUserJoined();
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _onUserOffline();
        }
      };
    } catch (e) {
      debugPrint('RTC Engine Error: $e');
      _peerConnection = null;
    }
  }

  Future<void> _pollSignals() async {
    if (_disposed) return;

    try {
      final result = await SignalingService.getSignals(widget.roomId);
      if (!result['success'] || _disposed) return;

      final data = result['data'];
      final roomStatus = data['room_status'];

      // 🚨 INSTANT SYNC: If room ended, leave immediately
      if (roomStatus == 'ended' || roomStatus == 'rejected') {
        _onUserOffline();
        return;
      }

      if (widget.isCaller && roomStatus == 'active' && !_offerSent) {
        await _createOffer();
      }

      final signals = data['signals'] as List? ?? [];
      for (final signal in signals) {
        if (_disposed || _peerConnection == null) break;
        final type = signal['signal_type'];
        final sdata = signal['data'];

        switch (type) {
          case 'offer':
            debugPrint('WebRTC: Receiving Offer');
            await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdata['sdp'], sdata['type']));
            await _createAnswer();
            for (var c in _remoteCandidates) await _peerConnection!.addCandidate(c);
            _remoteCandidates.clear();
            break;
          case 'answer':
            debugPrint('WebRTC: Receiving Answer');
            await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdata['sdp'], sdata['type']));
            for (var c in _remoteCandidates) await _peerConnection!.addCandidate(c);
            _remoteCandidates.clear();
            break;
          case 'candidate':
            debugPrint('WebRTC: Receiving Candidate');
            final candidate = RTCIceCandidate(sdata['candidate'], sdata['sdpMid'], sdata['sdpMLineIndex']);
            if (_peerConnection!.getRemoteDescription() != null) {
              await _peerConnection!.addCandidate(candidate);
            } else {
              _remoteCandidates.add(candidate);
            }
            break;
        }
      }
    } catch (e) {
      debugPrint('Polling Error: $e');
    }
  }

  Future<void> _createOffer() async {
    try {
      if (_peerConnection == null || _offerSent) return;
      _offerSent = true;
      debugPrint('WebRTC: Creating Offer');
      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      await SignalingService.sendSignal(widget.roomId, 'offer', {'sdp': offer.sdp, 'type': offer.type});
    } catch (e) {
      _offerSent = false;
      debugPrint('Offer Error: $e');
    }
  }

  Future<void> _createAnswer() async {
    try {
      if (_peerConnection == null) return;
      debugPrint('WebRTC: Creating Answer');
      RTCSessionDescription answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      await SignalingService.sendSignal(widget.roomId, 'answer', {'sdp': answer.sdp, 'type': answer.type});
    } catch (e) {
      debugPrint('Answer Error: $e');
    }
  }

  void _startDurationTimer() {
    if (_durationTimer != null) return;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_disposed) setState(() => _callDuration++);
    });
    _pulseController.stop();
  }

  Future<void> _leaveChannel({bool notifyServer = true}) async {
    if (_disposed) return;
    _disposed = true;
    
    _stopSound();
    _signalPollTimer?.cancel();
    _durationTimer?.cancel();
    
    _setStatus('Ending call...');

    if (notifyServer) {
      SignalingService.endCall(widget.roomId);
    }

    try {
      if (_localStream != null) {
        for (var track in _localStream!.getTracks()) track.stop();
        await _localStream!.dispose();
      }
      if (_peerConnection != null) await _peerConnection!.close();
      if (_renderersInitialized) {
        await _localRenderer?.dispose();
        await _remoteRenderer?.dispose();
      }
      await _audioPlayer.dispose();
    } catch (e) {
      debugPrint('Cleanup Error: $e');
    }
    
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    if (!_disposed) _leaveChannel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callType == 'video';
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: AppColors.woodGradient),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              if (isVideo && _isConnected && _remoteRenderer != null)
                Positioned.fill(child: RTCVideoView(_remoteRenderer!, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),
              if (isVideo && _localStream != null && !_isCameraOff && _localRenderer != null)
                Positioned(
                  top: 20, right: 20, width: 120, height: 170,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(border: Border.all(color: AppColors.secondaryColor, width: 2), borderRadius: BorderRadius.circular(16)),
                      child: RTCVideoView(_localRenderer!, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                    ),
                  ),
                ),
              if (!isVideo || !_isConnected)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final scale = _isConnected ? 1.0 : 0.8 + (_pulseController.value * 0.4);
                          return Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 120, height: 120,
                              decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [AppColors.primaryColor, AppColors.secondaryColor]), boxShadow: [BoxShadow(color: AppColors.secondaryColor.withOpacity(0.4), blurRadius: 30, spreadRadius: 4)]),
                              child: Center(child: Text(widget.remoteUsername.isNotEmpty ? widget.remoteUsername[0].toUpperCase() : '?', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white))),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      Text(widget.remoteUsername, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      const SizedBox(height: 12),
                      Text(_isConnected ? _formatDuration(_callDuration) : _callStatus, style: TextStyle(fontSize: 16, color: _isConnected ? Colors.greenAccent : _hasError ? Colors.redAccent : AppColors.textSecondary)),
                    ],
                  ),
                ),
              Positioned(
                bottom: 40, left: 0, right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ctrlBtn(icon: _isMuted ? Icons.mic_off : Icons.mic, label: 'Mute', isActive: _isMuted, onTap: () {
                      if (_localStream == null) return;
                      setState(() => _isMuted = !_isMuted);
                      for (var track in _localStream!.getAudioTracks()) track.enabled = !_isMuted;
                    }),
                    _ctrlBtn(icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off, label: 'Speaker', isActive: _isSpeakerOn, activeColor: AppColors.secondaryColor, onTap: () {
                      setState(() => _isSpeakerOn = !_isSpeakerOn);
                      Helper.setSpeakerphoneOn(_isSpeakerOn);
                    }),
                    GestureDetector(onTap: () => _leaveChannel(), child: Container(width: 64, height: 64, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle), child: const Icon(Icons.call_end, color: Colors.white, size: 32))),
                    if (isVideo) _ctrlBtn(icon: _isCameraOff ? Icons.videocam_off : Icons.videocam, label: 'Cam', isActive: _isCameraOff, onTap: () {
                      if (_localStream == null) return;
                      setState(() => _isCameraOff = !_isCameraOff);
                      for (var track in _localStream!.getVideoTracks()) track.enabled = !_isCameraOff;
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _ctrlBtn({required IconData icon, required String label, required bool isActive, required VoidCallback onTap, Color activeColor = Colors.redAccent}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(onTap: onTap, child: Container(width: 52, height: 52, decoration: BoxDecoration(color: isActive ? activeColor.withOpacity(0.3) : Colors.white.withOpacity(0.15), shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 24))),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ]);
  }
}
