import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling_service.dart';
import '../widgets/call_overlay_widget.dart';
import '../utils/route_const.dart';
import '../utils/route_generator.dart';

class CallManager {
  static final CallManager _instance = CallManager._internal();
  factory CallManager() => _instance;
  CallManager._internal();

  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

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

  final _updateController = StreamController<void>.broadcast();
  Stream<void> get onUpdate => _updateController.stream;

  Future<void> init() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
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
      final constraints = {
        'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
        'video': {'facingMode': 'user', 'width': {'ideal': 1280}, 'height': {'ideal': 720}}
      };
      
      localStream = await navigator.mediaDevices.getUserMedia(constraints);
      localRenderer.srcObject = localStream;
      
      if (callType == 'audio') {
        localStream!.getVideoTracks().forEach((t) => t.enabled = false);
      }

      final servers = await SignalingService.getIceServers();
      debugPrint("WebRTC: Initializing with ${servers.length} ICE servers");

      final iceConfig = {
        'iceServers': servers,
        'iceCandidatePoolSize': 20,
        'sdpSemantics': 'unified-plan',
        'iceTransportPolicy': 'all',
      };

      peerConnection = await createPeerConnection(iceConfig);
      
      for (var track in localStream!.getTracks()) {
        await peerConnection!.addTrack(track, localStream!);
      }

      peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams[0];
          if (event.track.kind == 'video') {
            remoteVideoEnabled = true;
          }
          if (!isConnected) _onUserJoined();
          notify();
        }
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
          if (!isConnected) _onUserJoined();
        }
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          debugPrint("❌ WebRTC: Connection Failed - Likely network restriction or TURN failure.");
        }
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed || 
            state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          debugPrint("📡 WebRTC: Connection ${state.name}. Cleanup triggered.");
          // Don't call endCall() automatically on disconnect as it might be a temporary network flip
        }
      };

      final stream = await SignalingService.connectWebSocket(roomId!);
      wsSubscription = stream?.listen(_onWsMessage);

      if (isCaller!) {
        callStatus = 'Ringing...';
        SignalingService.sendWsSignal('caller_ready', {'room_id': roomId, 'video_enabled': !isCameraOff});
      } else {
        SignalingService.sendWsSignal('receiver_ready', {'room_id': roomId, 'video_enabled': !isCameraOff});
      }

      heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (t) {
        SignalingService.sendWsSignal('ping', {'room_id': roomId!});
      });

      notify();
    } catch (e) {
      debugPrint("Call Manager Init Error: $e");
    }
  }

  void _onWsMessage(dynamic message) async {
    final data = jsonDecode(message);
    final type = data['type'];
    final payload = data['data'];

    switch (type) {
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

        final answer = await peerConnection!.createAnswer();
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
        final candidate = RTCIceCandidate(payload['candidate'], payload['sdpMid'], payload['sdpMLineIndex']);
        if (isRemoteDescriptionSet) {
          await peerConnection!.addCandidate(candidate);
        } else {
          remoteCandidatesQueue.add(candidate);
          debugPrint("WebRTC: Queued candidate (Remote description not yet set)");
        }
        break;
      case 'video_toggle':
        remoteVideoEnabled = payload['enabled'];
        notify();
        break;
      case 'end_call':
        endCall();
        break;
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

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void endCall() {
    _hideOverlay();
    wsSubscription?.cancel();
    durationTimer?.cancel();
    heartbeatTimer?.cancel();
    
    if (roomId != null) {
      SignalingService.sendWsSignal('end_call', {'room_id': roomId!});
      roomId = null;
    }
    
    SignalingService.closeWebSocket();
    localStream?.getTracks().forEach((t) => t.stop());
    remoteRenderer.srcObject = null;
    peerConnection?.close();
    peerConnection = null;
    
    isRemoteDescriptionSet = false;
    remoteCandidatesQueue.clear();
    isConnected = false;
    isMinimized = false;
    notify();
  }
}
