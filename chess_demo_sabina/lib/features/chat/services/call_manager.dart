import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import '../../../core/services/signaling_service.dart';
import '../../../core/services/api_service.dart';
import '../widgets/call_overlay_widget.dart';
import '../../../core/routing/route_const.dart';
import '../../../core/routing/route_generator.dart';
import '../../../core/utils/app_logger.dart';

class CallManager {
  static final CallManager _instance = CallManager._internal();
  factory CallManager() => _instance;
  CallManager._internal();

  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  bool isRecording = false;
  DateTime? recordingStartTime;
  int? lastRecordingDuration;

  bool isMuted = false;
  bool isCameraOff = false;
  bool isSpeakerOn = true;
  bool isConnected = false;
  bool remoteVideoEnabled = false;
  String callStatus = 'Initializing...';
  int callDuration = 0;
  
  String? roomId;
  String? remoteUsername;
  String? callType;
  bool? isCaller;

  StreamSubscription? wsSubscription;
  Timer? durationTimer;
  Timer? heartbeatTimer;
  List<RTCIceCandidate> remoteCandidatesQueue = [];
  bool isRemoteDescriptionSet = false;
  OverlayEntry? _overlayEntry;
  bool isMinimized = false;
  bool _hasAttemptedIceRestart = false;
  Timer? _iceRestartTimer;

  bool isConnectingWebSocket = false;
  bool isReconnecting = false;
  Timer? _reconnectTimer;

  final _updateController = StreamController<void>.broadcast();
  Stream<void> get onUpdate => _updateController.stream;
  
  Function(String event, dynamic payload)? onRemoteEvent;

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _isInitialized = true;
  }

  void notify() => _updateController.add(null);

  Future<void> setupCall({
    required String roomId,
    required String remoteUsername,
    required String callType,
    required bool isCaller,
  }) async {
    this.roomId = roomId;
    this.remoteUsername = remoteUsername;
    this.callType = callType;
    this.isCaller = isCaller;
    
    isCameraOff = callType == 'audio';
    remoteVideoEnabled = callType == 'video';
    callStatus = 'Initializing...';
    callDuration = 0;
    isConnected = false;
    isMinimized = false;

    await _initWebRTC();
  }

  Future<void> _initWebRTC() async {
    try {
      if (!kIsWeb) {
        debugPrint("🔐 CallManager: Checking microphone permission...");
        var micStatus = await Permission.microphone.status;
        if (!micStatus.isGranted) {
          micStatus = await Permission.microphone.request();
          if (!micStatus.isGranted) {
            debugPrint("❌ CallManager: Microphone permission denied");
            throw Exception('Microphone permission is required to start the call.');
          }
        }

        if (callType == 'video') {
          debugPrint("🔐 CallManager: Checking camera permission...");
          var camStatus = await Permission.camera.status;
          if (!camStatus.isGranted) {
            camStatus = await Permission.camera.request();
            if (!camStatus.isGranted) {
              debugPrint("⚠️ CallManager: Camera permission denied. Will try standard setup anyway.");
            }
          }
        }
      }

      final idealConstraints = {
        'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
        'video': callType == 'video'
            ? {'facingMode': 'user', 'width': {'ideal': 640}, 'height': {'ideal': 480}, 'frameRate': {'ideal': 24}}
            : false
      };
      
      final fallbackConstraints = {
        'audio': true,
        'video': callType == 'video',
      };

      MediaStream? acquiredStream;
      int attempts = 0;

      while (attempts < 2) {
        try {
          final constraints = attempts == 0 ? idealConstraints : fallbackConstraints;
          debugPrint("🎥 CallManager: getUserMedia attempt ${attempts + 1} with constraints: $constraints");
          acquiredStream = await navigator.mediaDevices.getUserMedia(constraints);
          if (acquiredStream != null) {
            debugPrint("✅ CallManager: Acquired MediaStream successfully on attempt ${attempts + 1}");
            break;
          }
        } catch (e) {
          attempts++;
          if (attempts == 2) {
            debugPrint("❌ CallManager: Failed to get local stream after 2 attempts: $e");
            rethrow;
          }
          debugPrint("⚠️ CallManager: 1st getUserMedia attempt failed ($e). Retrying with fallback constraints...");
        }
      }

      localStream = acquiredStream;
      localRenderer.srcObject = localStream;
      
      if (callType == 'audio') {
        localStream!.getVideoTracks().forEach((t) => t.enabled = false);
      }

      final servers = await SignalingService.getIceServers();
      debugPrint("WebRTC: Initializing with ${servers.length} ICE servers");

      final iceConfig = {
        'iceServers': servers,
        'iceCandidatePoolSize': 10,
        'bundlePolicy': 'balanced',
        'rtcpMuxPolicy': 'require',
        'sdpSemantics': 'unified-plan',
        'iceTransportPolicy': 'all',
      };
      _hasAttemptedIceRestart = false;

      peerConnection = await createPeerConnection(iceConfig);
      
      for (var track in localStream!.getTracks()) {
        await peerConnection!.addTrack(track, localStream!);
      }

      // Explicitly set transceivers to SendRecv for unified-plan compatibility
      try {
        final transceivers = await peerConnection!.getTransceivers();
        for (var t in transceivers) {
          final kind = t.receiver.track?.kind ?? t.sender.track?.kind;
          if (kind == 'audio' || kind == 'video') {
            debugPrint("📡 CallManager: Explicitly setting transceiver $kind to SendRecv");
            await t.setDirection(TransceiverDirection.SendRecv);
          }
        }
      } catch (e) {
        debugPrint("⚠️ CallManager: Error setting transceiver directions: $e");
      }

      peerConnection!.onTrack = (RTCTrackEvent event) async {
        debugPrint("📡 WebRTC: onTrack event fired - kind: ${event.track.kind}, streams: ${event.streams.length}");
        event.track.enabled = true; // 🔹 Explicitly ensure the remote track is enabled/active!
        
        if (event.streams.isNotEmpty) {
          final stream = event.streams[0];
          debugPrint("📡 WebRTC: Remote stream track count: ${stream.getTracks().length}");
          
          remoteStream = stream;
          
          // 🔹 Force re-binding of the native renderer by re-assigning srcObject
          remoteRenderer.srcObject = null;
          remoteRenderer.srcObject = stream;
          
          if (event.track.kind == 'video') {
            remoteVideoEnabled = true;
          }
          if (!isConnected) _onUserJoined();
          notify();
        } else {
          debugPrint("📡 WebRTC: onTrack event with empty streams. Manually adding track.");
          if (remoteStream == null) {
            // 🔹 Asynchronously create a brand new container stream for unified-plan compatibility
            final newStream = await createLocalMediaStream('remote_stream');
            remoteStream = newStream;
            remoteRenderer.srcObject = newStream;
          }
          
          remoteStream!.addTrack(event.track);
          
          // 🔹 Force re-binding of the native renderer by re-assigning srcObject
          remoteRenderer.srcObject = null;
          remoteRenderer.srcObject = remoteStream;
          
          if (event.track.kind == 'video') {
            remoteVideoEnabled = true;
          }
          if (!isConnected) _onUserJoined();
          notify();
        }
      };

      peerConnection!.onAddStream = (MediaStream stream) {
        debugPrint("📡 WebRTC: onAddStream event fired - remote stream added!");
        stream.getTracks().forEach((track) {
          track.enabled = true; // 🔹 Ensure all tracks in the stream are enabled!
        });
        
        remoteStream = stream;
        
        // 🔹 Force re-binding of the native renderer by re-assigning srcObject
        remoteRenderer.srcObject = null;
        remoteRenderer.srcObject = stream;
        
        remoteVideoEnabled = true;
        if (!isConnected) _onUserJoined();
        notify();
      };

      peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          // 🔹 Log the candidate type for debugging cross-network issues
          if (candidate.candidate!.contains('typ relay')) {
            debugPrint("WebRTC ICE: Found RELAY candidate (TURN working! ✅)");
          } else if (candidate.candidate!.contains('typ srflx')) {
            debugPrint("WebRTC ICE: Found SRFLX candidate (STUN working!)");
          } else if (candidate.candidate!.contains('typ host')) {
            debugPrint("WebRTC ICE: Found HOST candidate (Local network)");
          }

          SignalingService.sendWsSignal('candidate', {
            'room_id': roomId,
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          });
        }
      };

      peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        debugPrint("🧊 WebRTC: ICE Connection State: ${state.name}");
      };

      peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        debugPrint("📡 WebRTC: Connection State: ${state.name}");
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _hasAttemptedIceRestart = false;
          _iceRestartTimer?.cancel();
          if (!isConnected) _onUserJoined();
        }
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          debugPrint("❌ WebRTC: Connection Failed - Attempting ICE restart...");
          _attemptIceRestart();
        }
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          debugPrint("📡 WebRTC: Connection disconnected. Scheduling ICE restart...");
          // Wait 3 seconds before attempting restart (might be temporary blip)
          _iceRestartTimer?.cancel();
          _iceRestartTimer = Timer(const Duration(seconds: 3), () {
            if (peerConnection?.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
              _attemptIceRestart();
            }
          });
        }
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          debugPrint("📡 WebRTC: Connection closed.");
        }
      };

      await _connectWebSocket();
    } catch (e, s) {
      AppLogger.e("Call Manager Init Error", error: e, stackTrace: s, feature: "webrtc_calling");
    }
  }

  Future<void> _connectWebSocket() async {
    if (isConnectingWebSocket) return;
    isConnectingWebSocket = true;
    notify();

    try {
      if (wsSubscription != null) {
        await wsSubscription!.cancel();
        wsSubscription = null;
      }
      SignalingService.closeWebSocket();

      debugPrint("🔌 CallManager: Connecting WebSocket for room $roomId");
      final stream = await SignalingService.connectWebSocket(roomId!);
      if (stream == null) {
        throw Exception("Failed to acquire WebSocket stream");
      }

      isConnectingWebSocket = false;
      isReconnecting = false;

      wsSubscription = stream.listen(
        _onWsMessage,
        onError: (err) {
          debugPrint("❌ CallManager WS Stream Error: $err");
          _handleWsDisconnect();
        },
        onDone: () {
          debugPrint("📡 CallManager WS Stream closed (onDone)");
          _handleWsDisconnect();
        },
      );

      _startHeartbeat();
      notify();
    } catch (e, s) {
      isConnectingWebSocket = false;
      AppLogger.e("CallManager WS Connection Setup Failed", error: e, stackTrace: s, feature: "webrtc_calling");
      _handleWsDisconnect();
    }
  }

  void _handleWsDisconnect() {
    _stopHeartbeat();
    _reconnectTimer?.cancel();

    if (roomId != null && peerConnection != null) {
      isReconnecting = true;
      callStatus = 'Reconnecting...';
      notify();

      debugPrint("🔄 CallManager: Disconnected. Scheduling WebSocket reconnect in 3 seconds...");
      _reconnectTimer = Timer(const Duration(seconds: 3), () {
        if (roomId != null && peerConnection != null) {
          _connectWebSocket();
        }
      });
    }
  }

  void _startHeartbeat() {
    heartbeatTimer?.cancel();
    heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (t) {
      if (roomId != null) {
        SignalingService.sendWsSignal('ping', {'room_id': roomId!});
      }
    });
  }

  void _stopHeartbeat() {
    heartbeatTimer?.cancel();
    heartbeatTimer = null;
  }

  void _onWsMessage(dynamic message) async {
    try {
      final data = jsonDecode(message);
      final type = data['type'];
      final payload = data['data'];

    switch (type) {
      case 'connection_established':
        debugPrint("✅ Server handshake confirmed for room $roomId");
        if (isCaller!) {
          if (callStatus == 'Initializing...') {
            callStatus = 'Ringing...';
            notify();
          }
          SignalingService.sendWsSignal('caller_ready', {'room_id': roomId!, 'video_enabled': !isCameraOff});
        } else {
          SignalingService.sendWsSignal('receiver_ready', {'room_id': roomId!, 'video_enabled': !isCameraOff});
        }
        break;
      case 'caller_ready':
        if (!isCaller! && isConnected == false) {
          SignalingService.sendWsSignal('receiver_ready', {'room_id': roomId!, 'video_enabled': !isCameraOff});
        }
        break;
      case 'receiver_ready':
        if (isCaller! && isConnected == false) {
          final offer = await peerConnection!.createOffer({'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true}});
          await peerConnection!.setLocalDescription(offer);
          SignalingService.sendWsSignal('offer', {'room_id': roomId!, 'sdp': offer.sdp, 'type': offer.type});
        }
        break;
      case 'offer':
        await peerConnection!.setRemoteDescription(RTCSessionDescription(payload['sdp'], payload['type']));
        isRemoteDescriptionSet = true;
        
        // Process queued candidates
        for (var candidate in remoteCandidatesQueue) {
          await peerConnection!.addCandidate(candidate);
        }
        remoteCandidatesQueue.clear();

        final answer = await peerConnection!.createAnswer({
          'mandatory': {
            'OfferToReceiveAudio': true,
            'OfferToReceiveVideo': true,
          }
        });
        await peerConnection!.setLocalDescription(answer);
        SignalingService.sendWsSignal('answer', {'room_id': roomId!, 'sdp': answer.sdp, 'type': answer.type});
        break;
      case 'answer':
        await peerConnection!.setRemoteDescription(RTCSessionDescription(payload['sdp'], payload['type']));
        isRemoteDescriptionSet = true;
        
        // Process queued candidates
        for (var candidate in remoteCandidatesQueue) {
          await peerConnection!.addCandidate(candidate);
        }
        remoteCandidatesQueue.clear();
        break;
      case 'candidate':
        final candidateStr = payload['candidate'];
        final sdpMid = payload['sdpMid'];
        final sdpMLineIndex = payload['sdpMLineIndex'] is String
            ? int.tryParse(payload['sdpMLineIndex'])
            : payload['sdpMLineIndex'];

        if (candidateStr != null) {
          final candidate = RTCIceCandidate(candidateStr, sdpMid, sdpMLineIndex);
          if (isRemoteDescriptionSet) {
            await peerConnection!.addCandidate(candidate);
          } else {
            remoteCandidatesQueue.add(candidate);
            debugPrint("WebRTC: Queued candidate (Remote description not yet set)");
          }
        }
        break;
      case 'video_toggle':
        remoteVideoEnabled = payload['enabled'];
        notify();
        break;
      case 'recording_started':
        onRemoteEvent?.call('recording_started', payload);
        break;
      case 'recording_stopped':
        onRemoteEvent?.call('recording_stopped', payload);
        break;
      case 'end_call':
        if (roomId == payload['room_id']) {
          endCall();
        }
        break;
    }
    } catch (e, stacktrace) {
      AppLogger.e("CallManager WebRTC Error in _onWsMessage", error: e, stackTrace: stacktrace, feature: "webrtc_calling");
    }
  }

  void _onUserJoined() {
    isConnected = true;
    callStatus = 'Connected';
    durationTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      callDuration++;
      notify();
    });
    notify();
    // ── Auto-start recording as soon as both peers are connected ──
    startRecording();
  }

  void toggleMic() {
    isMuted = !isMuted;
    localStream?.getAudioTracks().forEach((t) => t.enabled = !isMuted);
    notify();
  }
  
  void toggleSpeaker() {
    isSpeakerOn = !isSpeakerOn;
    Helper.setSpeakerphoneOn(isSpeakerOn);
    notify();
  }

  void toggleVideo() async {
    isCameraOff = !isCameraOff;
    localStream?.getVideoTracks().forEach((t) => t.enabled = !isCameraOff);
    SignalingService.sendWsSignal('video_toggle', {'room_id': roomId!, 'enabled': !isCameraOff});
    
    if (!isCameraOff && isConnected) {
      final offer = await peerConnection!.createOffer({'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true}});
      await peerConnection!.setLocalDescription(offer);
      SignalingService.sendWsSignal('offer', {'room_id': roomId!, 'sdp': offer.sdp, 'type': offer.type});
    }
    notify();
  }

  void switchCamera() {
    if (localStream != null && localStream!.getVideoTracks().isNotEmpty) {
      localStream!.getVideoTracks().first.switchCamera();
    }
  }

  void minimize(BuildContext context) {
    isMinimized = true;
    _showOverlay(context);
    Navigator.of(context).pop();
  }

  void maximize(BuildContext context) {
    isMinimized = false;
    _hideOverlay();
    RouteGenerator.navigateToPage(context, Routes.callRoute, arguments: {
      'roomId': roomId,
      'remoteUsername': remoteUsername,
      'callType': callType,
      'isCaller': isCaller,
      'fromMinimized': true,
    });
  }

  void _showOverlay(BuildContext context) {
    if (_overlayEntry != null) return;
    _overlayEntry = OverlayEntry(
      builder: (context) => CallOverlayWidget(),
    );
    // Find the root overlay to ensure it persists after pop
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    overlay?.insert(_overlayEntry!);
  }

  /// 🔹 ICE Restart: Re-negotiate the connection through TURN relay servers
  /// This is critical for cross-network calls (different WiFi / cellular)
  Future<void> _attemptIceRestart() async {
    if (_hasAttemptedIceRestart || peerConnection == null) return;
    _hasAttemptedIceRestart = true;

    debugPrint("🔄 WebRTC: Performing ICE restart...");
    callStatus = 'Reconnecting...';
    notify();

    try {
      final offer = await peerConnection!.createOffer({
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': true,
        },
        'iceRestart': true, // Forces new ICE candidates via TURN
      });
      await peerConnection!.setLocalDescription(offer);
      SignalingService.sendWsSignal('offer', {
        'room_id': roomId!,
        'sdp': offer.sdp,
        'type': offer.type,
      });
      debugPrint("🔄 WebRTC: ICE restart offer sent.");

      // Allow another restart attempt after 10 seconds if still not connected
      Future.delayed(const Duration(seconds: 10), () {
        _hasAttemptedIceRestart = false;
      });
    } catch (e, s) {
      AppLogger.e("WebRTC: ICE restart failed", error: e, stackTrace: s, feature: "webrtc_calling");
      _hasAttemptedIceRestart = false;
    }
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Future<void> endCall() async {
    if (isRecording) {
      await stopRecording();
    }
    _hideOverlay();
    wsSubscription?.cancel();
    wsSubscription = null;
    durationTimer?.cancel();
    durationTimer = null;
    heartbeatTimer?.cancel();
    heartbeatTimer = null;
    _iceRestartTimer?.cancel();
    _iceRestartTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    isReconnecting = false;
    isConnectingWebSocket = false;
    
    if (roomId != null) {
      SignalingService.sendWsSignal('end_call', {'room_id': roomId!});
      roomId = null;
    }
    
    SignalingService.closeWebSocket();
    localStream?.getTracks().forEach((t) => t.stop());
    localStream = null;
    remoteStream = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    peerConnection?.close();
    peerConnection = null;
    
    isRemoteDescriptionSet = false;
    remoteCandidatesQueue.clear();
    isConnected = false;
    isMinimized = false;
    _hasAttemptedIceRestart = false;
    notify();
  }

  Future<void> startRecording() async {
    if (isRecording) return;
    try {
      await Permission.storage.request();
      final hasMic = await Permission.microphone.request().isGranted;
      
      if (hasMic) {
        final title = 'call_${roomId}_${DateTime.now().millisecondsSinceEpoch}';
        final success = await FlutterScreenRecording.startRecordScreenAndAudio(title);
        if (success) {
          isRecording = true;
          recordingStartTime = DateTime.now();
          lastRecordingDuration = null;
          debugPrint("CallManager: Screen recording started: $title");
          if (roomId != null) {
            SignalingService.sendWsSignal('recording_started', {'room_id': roomId!});
          }
          notify();
        } else {
          debugPrint("CallManager: Failed to start screen recording");
        }
      } else {
        debugPrint("CallManager: Permissions denied for screen recording");
      }
    } catch (e, s) {
      AppLogger.e("CallManager: Error starting screen recording", error: e, stackTrace: s, feature: "call_recording");
    }
  }

  Future<void> stopRecording() async {
    if (!isRecording) return;
    try {
      final path = await FlutterScreenRecording.stopRecordScreen;
      isRecording = false;
      if (recordingStartTime != null) {
        lastRecordingDuration = DateTime.now().difference(recordingStartTime!).inSeconds;
      }
      recordingStartTime = null;
      if (roomId != null) {
        SignalingService.sendWsSignal('recording_stopped', {'room_id': roomId!});
      }
      notify();
      
      if (path != null && path.isNotEmpty) {
        debugPrint("CallManager: Screen recording stopped. Saved locally at $path");
        // Upload to backend
        final currentUser = await _getCurrentUsername();
        final response = await ApiService.saveCallRecording(
          callerUsername: isCaller == true ? currentUser : remoteUsername,
          calleeUsername: isCaller == true ? remoteUsername : currentUser,
          callType: callType ?? 'unknown',
          filePath: path,
        );
        debugPrint("CallManager: Save screen recording response: $response");
      }
    } catch (e, s) {
      AppLogger.e("CallManager: Error stopping screen recording", error: e, stackTrace: s, feature: "call_recording");
    }
  }

  Future<String?> _getCurrentUsername() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('username');
    } catch (_) {
      return null;
    }
  }
}
