import 'dart:async';
import 'dart:convert';
import 'package:chess_demo_sabina/pages/call_ended_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/signaling_service.dart';
import '../utils/color_utils.dart';
import '../helper/helper.dart';

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

class _CallPageState extends State<CallPage>
    with SingleTickerProviderStateMixin {
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
  bool _remoteVideoEnabled = false;
  String _callStatus = 'Initializing...';
  int _callDuration = 0;
  bool _hasError = false;
  bool _offerSent = false;
  bool _callerReady = false;
  bool _receiverReady = false;
  bool _remoteDescriptionSet = false;
  final Set<String> _addedCandidates = {};
  final List<RTCIceCandidate> _remoteCandidates = [];

  // Signaling
  StreamSubscription? _wsSubscription;
  Timer? _durationTimer;
  Timer? _heartbeatTimer;
  Timer? _iceRestartTimer; // 🔹 ICE restart when stuck
  bool _disposed = false;
  bool _renderersInitialized = false;

  // Audio UX
  final AudioPlayer _audioPlayer = AudioPlayer();
  static const String ringingUrl =
      'https://assets.mixkit.co/active_storage/sfx/2358/2358-preview.mp3';
  static const String beepUrl =
      'https://assets.mixkit.co/active_storage/sfx/2571/2571-preview.mp3';

  // Animation
  late AnimationController _pulseController;

  // 🔹 ICE Servers — Matches working Manika project config
  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
      {'urls': 'stun:stun.cloudflare.com:3478'},
      {'urls': 'stun:stun.services.mozilla.com'},
      {
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turn:openrelay.metered.ca:3478',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': [
          'turns:openrelay.metered.ca:443?transport=tcp',
          'turns:openrelay.metered.ca:3478?transport=tcp',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'iceCandidatePoolSize': 10,
    'bundlePolicy': 'balanced',
    'rtcpMuxPolicy': 'require',
    'sdpSemantics': 'unified-plan',
    'iceTransportPolicy': 'all',
  };

  @override
  void initState() {
    super.initState();
    _isCameraOff = widget.callType == 'audio';
    _remoteVideoEnabled = widget.callType == 'video'; // Default to true for video calls
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _audioPlayer.setVolume(1.0);
    _initCall();
  }

  @override
  void dispose() {
    _leaveChannel();
    super.dispose();
  }

  Future<void> _initCall() async {
    try {
      _setStatus('Initializing...');

      _localRenderer = RTCVideoRenderer();
      _remoteRenderer = RTCVideoRenderer();

      await Future.wait([
        _localRenderer!.initialize(),
        _remoteRenderer!.initialize(),
        _setupLocalMedia(),
      ]);

      _renderersInitialized = true;

      if (_localStream == null) {
        _setStatus('Media access failed');
        _hasError = true;
        return;
      }

      if (_localRenderer != null) {
        _localRenderer!.srcObject = _localStream;
      }

      // 🔹 Fetch fresh TURN credentials from backend
      await _fetchTurnCredentials();

      await _createPeerConnection();

      // 🔹 Connect to WebSocket
      final stream = await SignalingService.connectWebSocket(widget.roomId);
      if (stream == null) {
        _setStatus('Connection error');
        _hasError = true;
        return;
      }

      _wsSubscription = stream.listen(
        _onWsMessage,
        onError: (e) {
          debugPrint('WebSocket Error: $e');
        },
        onDone: () {
          debugPrint('WebSocket Closed');
          // 🔹 Only end call if WebRTC is NOT connected
          if (!_disposed && !_isConnected) {
            _onUserOffline();
          }
        },
      );

      // 🔹 Start Heartbeat (keep socket alive on HF Spaces)
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
        if (!_disposed) {
          SignalingService.sendWsSignal('ping', {'room_id': widget.roomId});
        } else {
          timer.cancel();
        }
      });

      if (widget.isCaller) {
        _setStatus('Ringing ${widget.remoteUsername}...');
        _playSound(ringingUrl, loop: true);
        SignalingService.sendWsSignal('caller_ready', {
          'room_id': widget.roomId,
          'video_enabled': !_isCameraOff,
        });
      } else {
        _setStatus('Connecting...');
        // Notify caller that we received the call and are ready
        SignalingService.sendWsSignal('incoming_received', {'room_id': widget.roomId});
        SignalingService.sendWsSignal('receiver_ready', {
          'room_id': widget.roomId,
          'video_enabled': !_isCameraOff,
        });
      }
    } catch (e) {
      debugPrint('Init call error: $e');
      _setStatus('Error: $e');
      _hasError = true;
    }
  }
  /// 🔹 Fetch fresh TURN credentials from backend (ephemeral, time-limited)
  Future<void> _fetchTurnCredentials() async {
    try {
      final result = await SignalingService.getTurnCredentials();
      if (result['success'] == true && result['data'] != null) {
        final List<dynamic> servers = result['data']['ice_servers'];
        
        // 🔹 Update servers while PRESERVING critical policies
        setState(() {
          _iceServers = {
            'iceServers': servers,
            'iceCandidatePoolSize': 10,
            'bundlePolicy': 'balanced',
            'rtcpMuxPolicy': 'require',
            'sdpSemantics': 'unified-plan',
            'iceTransportPolicy': 'all',
          };
        });
        debugPrint('🧲 TURN credentials fetched: ${servers.length} ICE servers (Policies applied)');
      } else {
        debugPrint('⚠️ TURN credential fetch failed, using hardcoded config');
      }
    } catch (e) {
      debugPrint('❌ TURN credential fetch error: $e (using hardcoded config)');
    }
  }

  void _onWsMessage(dynamic message) async {
    if (_disposed || _peerConnection == null) return;
    final data = jsonDecode(message);
    final type = data['type'];
    final payload = data['data'];

    debugPrint('Received WS Signal: $type');

    switch (type) {
      case 'caller_ready':
        _callerReady = true;
        if (mounted)
          setState(
            () => _remoteVideoEnabled = payload['video_enabled'] ?? false,
          );
        if (!widget.isCaller) {
          SignalingService.sendWsSignal('receiver_ready', {
            'room_id': widget.roomId,
            'video_enabled': !_isCameraOff,
          });
        }
        break;
      case 'incoming_received':
        if (widget.isCaller) {
          debugPrint('Callee acknowledged receiving the call');
          _setStatus('Ringing...');
        }
        break;
      case 'receiver_ready':
        _receiverReady = true;
        if (mounted)
          setState(
            () => _remoteVideoEnabled = payload['video_enabled'] ?? false,
          );
        if (widget.isCaller && !_offerSent) {
          _setStatus('Connecting...');
          _stopSound();
          await _createOffer();
        }
        break;
      case 'video_toggle':
        if (mounted) setState(() => _remoteVideoEnabled = payload['enabled']);
        break;
      case 'offer':
        _setStatus('Connecting...');
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(payload['sdp'], payload['type']),
        );
        _remoteDescriptionSet = true;
        await _createAnswer();
        for (var c in _remoteCandidates) {
          await _peerConnection!.addCandidate(c);
        }
        _remoteCandidates.clear();
        break;
      case 'answer':
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(payload['sdp'], payload['type']),
        );
        _remoteDescriptionSet = true;
        for (var c in _remoteCandidates) {
          await _peerConnection!.addCandidate(c);
        }
        _remoteCandidates.clear();
        break;
      case 'candidate':
        if (_addedCandidates.contains(payload['candidate'])) return;
        _addedCandidates.add(payload['candidate']);

        final sdpMLineIndex = payload['sdpMLineIndex'] is String
            ? int.tryParse(payload['sdpMLineIndex'])
            : payload['sdpMLineIndex'];
            
        final candidate = RTCIceCandidate(
          payload['candidate'],
          payload['sdpMid'],
          sdpMLineIndex,
        );
        
        if (_peerConnection != null && _remoteDescriptionSet) {
          await _peerConnection!.addCandidate(candidate);
        } else {
          _remoteCandidates.add(candidate);
        }
        break;
      case 'end_call':
        _onUserOffline();
        break;
    }
  }

  Future<void> _setupLocalMedia() async {
    final Map<String, dynamic> constraints = {
      'audio': true,
      'video': !_isCameraOff
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    };
    try {
      if (_localStream != null) {
        for (var track in _localStream!.getTracks()) track.stop();
        await _localStream!.dispose();
      }
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      if (_localRenderer != null) {
        _localRenderer!.srcObject = _localStream;
      }
    } catch (e) {
      debugPrint('Media Error: $e');
    }
  }

  Future<void> _createPeerConnection() async {
    if (_peerConnection != null) return;
    _peerConnection = await createPeerConnection(_iceServers);

    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }

    // 🔹 Explicitly set transceiver direction (Unified Plan)
    final transceivers = await _peerConnection!.getTransceivers();
    for (var t in transceivers) {
      await t.setDirection(TransceiverDirection.SendRecv);
    }

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      debugPrint('Received Remote Track: ${event.track.kind}');
      if (event.streams.isNotEmpty && mounted && !_disposed) {
        if (_remoteRenderer != null) {
          setState(() {
            _remoteRenderer!.srcObject = event.streams[0];
            if (event.track.kind == 'video') {
              _remoteVideoEnabled = true;
            }
          });
        }
        if (!_isConnected) _onUserJoined();
      }
    };

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (!_disposed && candidate.candidate != null) {
        // 🔹 Log candidate type (HOST/SRFLX/RELAY) for diagnostics
        String type = 'unknown';
        if (candidate.candidate!.contains('typ host')) type = 'HOST (Local)';
        if (candidate.candidate!.contains('typ srflx')) type = 'SRFLX (Public IP)';
        if (candidate.candidate!.contains('typ relay')) type = 'RELAY (TURN Server)';
        debugPrint('🧲 ICE Candidate: $type');
        SignalingService.sendWsSignal('candidate', {
          'room_id': widget.roomId,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('RTC Peer Connection State: ${state.toString()}');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (!_isConnected) _onUserJoined();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        debugPrint('RTC Peer Connection FAILED - NAT traversal failed or timed out.');
        // 🔹 Don't disconnect immediately. Let the ICE restart timer try to recover.
        // We'll only exit if it stays failed for too long.
        Future.delayed(const Duration(seconds: 10), () {
          if (mounted && !_disposed && !_isConnected) {
             debugPrint('RTC Connection still failed after 10s. Closing call.');
             _onUserOffline();
          }
        });
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _onUserOffline();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        debugPrint('RTC Peer Connection DISCONNECTED - Attempting to remain in room...');
      }
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('🧲 ICE Connection State: ${state.toString()}');
      if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
        // 🔹 Start ICE restart timer (15s) in case ICE gets stuck
        _startIceRestartTimer();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
                 state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _stopIceRestartTimer();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
                 state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        debugPrint('❌ ICE Connection Failed/Disconnected - attempting restart...');
        _stopIceRestartTimer();
        if (widget.isCaller && !_disposed) {
          Future.delayed(const Duration(seconds: 2), () {
            // 🔹 Allow restart even if initial connection never finished
            if (!_disposed) _triggerIceRestart();
          });
        }
      }
    };

    _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
      debugPrint('📡 ICE Gathering State: ${state.toString()}');
    };
  }

  // 🔹 ICE Restart mechanism (ported from Manika project)
  void _startIceRestartTimer() {
    _iceRestartTimer?.cancel();
    _iceRestartTimer = Timer(const Duration(seconds: 15), () {
      if (_peerConnection != null && widget.isCaller && !_disposed) {
        debugPrint('⏳ ICE stuck in checking for 15s. Triggering restart...');
        _triggerIceRestart();
      }
    });
  }

  void _stopIceRestartTimer() {
    _iceRestartTimer?.cancel();
    _iceRestartTimer = null;
  }

  Future<void> _triggerIceRestart() async {
    if (_peerConnection == null || !widget.isCaller || _disposed) return;
    try {
      debugPrint('🔄 ICE Restart: Creating new offer with iceRestart=true');
      final offer = await _peerConnection!.createOffer({'iceRestart': true});
      await _peerConnection!.setLocalDescription(offer);
      SignalingService.sendWsSignal('offer', {
        'room_id': widget.roomId,
        'sdp': offer.sdp,
        'type': offer.type,
      });
    } catch (e) {
      debugPrint('❌ ICE Restart failed: $e');
    }
  }

  Future<void> _createOffer() async {
    _offerSent = true;
    final constraints = {
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': true,
      },
      'optional': [],
    };
    RTCSessionDescription offer = await _peerConnection!.createOffer(constraints);
    await _peerConnection!.setLocalDescription(offer);
    SignalingService.sendWsSignal('offer', {
      'room_id': widget.roomId,
      'sdp': offer.sdp,
      'type': offer.type,
    });
  }

  Future<void> _createAnswer() async {
    final constraints = {
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': true,
      },
      'optional': [],
    };
    RTCSessionDescription answer = await _peerConnection!.createAnswer(constraints);
    await _peerConnection!.setLocalDescription(answer);
    SignalingService.sendWsSignal('answer', {
      'room_id': widget.roomId,
      'sdp': answer.sdp,
      'type': answer.type,
    });
  }

  Future<void> _renegotiate() async {
    if (_peerConnection == null) return;

    // Add new local tracks if they were added
    if (_localStream != null) {
      final senders = await _peerConnection!.getSenders();
      for (var track in _localStream!.getTracks()) {
        bool exists = senders.any((s) => s.track?.id == track.id);
        if (!exists) {
          await _peerConnection!.addTrack(track, _localStream!);
        }
      }
    }

    _offerSent = false;
    await _createOffer();
  }

  Future<void> _toggleCamera() async {
    if (_disposed || _peerConnection == null) return;

    if (_isCameraOff) {
      // Turn camera ON
      setState(() => _isCameraOff = false);
      await _setupLocalMedia();
      await _renegotiate();
    } else {
      // Turn camera OFF
      setState(() => _isCameraOff = true);
      for (var track in _localStream!.getVideoTracks()) {
        track.enabled = false;
        track.stop();
      }
    }

    SignalingService.sendWsSignal('video_toggle', {'enabled': !_isCameraOff});
  }

  Future<void> _switchCamera() async {
    if (_localStream == null || _isCameraOff) return;
    try {
      final videoTrack = _localStream!.getVideoTracks().first;
      await Helper.switchCamera(videoTrack);
    } catch (e) {
      debugPrint('Switch Camera Error: $e');
    }
  }

  void _onUserJoined() {
    _stopSound();
    _playSound(beepUrl);
    if (mounted) {
      setState(() {
        _isConnected = true;
        _callStatus = 'Connected';
      });
    }
    _startDurationTimer();
  }

  void _onUserOffline() {
    _stopSound();
    _setStatus('Call ended');
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _leaveChannel(notifyServer: false);
    });
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
    _wsSubscription?.cancel();
    _durationTimer?.cancel();
    _heartbeatTimer?.cancel();
    _iceRestartTimer?.cancel();

    if (notifyServer) {
      SignalingService.sendWsSignal('end_call', {'room_id': widget.roomId});
      SignalingService.endCall(widget.roomId);
    }

    SignalingService.closeWebSocket();

    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }

    if (_peerConnection != null) {
      await _peerConnection!.close();
      await _peerConnection!.dispose();
      _peerConnection = null;
    }

    if (_renderersInitialized) {
      await _localRenderer?.dispose();
      await _remoteRenderer?.dispose();
      _localRenderer = null;
      _remoteRenderer = null;
      _renderersInitialized = false;
    }

    await _audioPlayer.dispose();
    _pulseController.dispose();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CallEndedPage(
            remoteUsername: widget.remoteUsername,
            duration: _formatDurationLong(_callDuration),
          ),
        ),
      );
    }
  }

  String _formatDurationLong(int totalSeconds) {
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    int s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _setStatus(String status) {
    if (mounted && !_disposed) setState(() => _callStatus = status);
  }

  Future<void> _playSound(String url, {bool loop = false}) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setReleaseMode(
        loop ? ReleaseMode.loop : ReleaseMode.release,
      );
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      debugPrint('Audio Error: $e');
    }
  }

  void _stopSound() {
    _audioPlayer.stop();
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }


  @override
  Widget build(BuildContext context) {
    final showRemoteVideo =
        _isConnected && _remoteVideoEnabled && _remoteRenderer != null;
    final showLocalVideo = !_isCameraOff && _localRenderer != null;

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
              // Remote Video
              if (showRemoteVideo)
                Positioned.fill(
                  child: RTCVideoView(
                    _remoteRenderer!,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),

              // Avatar/Status View (when video is off)
              if (!showRemoteVideo || !_isConnected)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final scale = _isConnected
                              ? 1.0
                              : 0.8 + (_pulseController.value * 0.4);
                          return Transform.scale(
                            scale: scale,
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
                                    color: AppColors.secondaryColor.withOpacity(
                                      0.4,
                                    ),
                                    blurRadius: 30,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  widget.remoteUsername.isNotEmpty
                                      ? widget.remoteUsername[0].toUpperCase()
                                      : '?',
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
                      Text(
                        widget.remoteUsername,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isConnected
                            ? _formatDuration(_callDuration)
                            : _callStatus,
                        style: TextStyle(
                          fontSize: 16,
                          color: _isConnected
                              ? Colors.greenAccent
                              : _hasError
                              ? Colors.redAccent
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

              // Local Video (PiP)
              if (showLocalVideo)
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
                        color: Colors.black26,
                      ),
                      child: Stack(
                        children: [
                          RTCVideoView(
                            _localRenderer!,
                            mirror: true,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: _switchCamera,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black45,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.switch_camera,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Controls
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ctrlBtn(
                      icon: _isMuted ? Icons.mic_off : Icons.mic,
                      label: 'Mute',
                      isActive: _isMuted,
                      onTap: () {
                        if (_localStream == null) return;
                        setState(() => _isMuted = !_isMuted);
                        for (var track in _localStream!.getAudioTracks())
                          track.enabled = !_isMuted;
                      },
                    ),
                    _ctrlBtn(
                      icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                      label: 'Speaker',
                      isActive: _isSpeakerOn,
                      activeColor: AppColors.secondaryColor,
                      onTap: () {
                        setState(() => _isSpeakerOn = !_isSpeakerOn);
                        Helper.setSpeakerphoneOn(_isSpeakerOn);
                      },
                    ),
                    GestureDetector(
                      onTap: () => _leaveChannel(),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.call_end,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                    _ctrlBtn(
                      icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                      label: 'Cam',
                      isActive: !_isCameraOff,
                      activeColor: AppColors.secondaryColor,
                      onTap: _toggleCamera,
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

  Widget _ctrlBtn({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    Color activeColor = Colors.redAccent,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withOpacity(0.3)
                  : Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
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
