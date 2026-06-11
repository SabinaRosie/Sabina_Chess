import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/utils/const.dart';
import '../../../core/services/signaling_service.dart';
import '../../../core/services/api_service.dart';

class GameMediaService {
  WebSocketChannel? _channel;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  final ValueNotifier<MediaStream?> remoteStreamNotifier = ValueNotifier<MediaStream?>(null);
  final ValueNotifier<MediaStream?> localStreamNotifier = ValueNotifier<MediaStream?>(null);
  final ValueNotifier<bool> isOpponentMuted = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isOpponentVideoEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isRecordingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isRemoteMutedLocally = ValueNotifier<bool>(false);
  DateTime? recordingStartTime;
  int? lastRecordingDuration;

  bool _isRemoteDescriptionSet = false;
  final List<RTCIceCandidate> _remoteCandidatesQueue = [];

  final _videoRequestController = StreamController<void>.broadcast();
  Stream<void> get onVideoRequest => _videoRequestController.stream;

  final _videoResponseController = StreamController<bool>.broadcast();
  Stream<bool> get onVideoResponse => _videoResponseController.stream;
  
  Function(String event, dynamic payload)? onRemoteEvent;

  bool _isCaller = false;
  String? _gameId;
  String? _token;

  Map<String, dynamic> _iceConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun.relay.metered.ca:80'},
      {
        'urls': 'turn:global.relay.metered.ca:80',
        'username': '709362ac5e79d7848563aaba',
        'credential': '9kwUXSQwK6gbOJMm',
      },
      {
        'urls': 'turn:global.relay.metered.ca:80?transport=tcp',
        'username': '709362ac5e79d7848563aaba',
        'credential': '9kwUXSQwK6gbOJMm',
      },
      {
        'urls': 'turn:global.relay.metered.ca:443',
        'username': '709362ac5e79d7848563aaba',
        'credential': '9kwUXSQwK6gbOJMm',
      },
      {
        'urls': 'turns:global.relay.metered.ca:443?transport=tcp',
        'username': '709362ac5e79d7848563aaba',
        'credential': '9kwUXSQwK6gbOJMm',
      },
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turns:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'iceCandidatePoolSize': 20,
    'sdpSemantics': 'unified-plan',
    'iceTransportPolicy': 'all',
  };

  Future<void> connect(String gameId, String token, bool isCaller) async {
    _gameId = gameId;
    _token = token;
    _isCaller = isCaller;

    final url = Uri.parse('${AppConstants.webSocketUrl}/call/$gameId/?token=$token');
    debugPrint("GAME_MEDIA_WS: Connecting to $url");
    _channel = WebSocketChannel.connect(url);

    _channel!.stream.listen(
      (message) {
        final data = jsonDecode(message);
        _handleMessage(data);
      },
      onDone: () => debugPrint("GAME_MEDIA_WS: Disconnected"),
      onError: (e) => debugPrint("GAME_MEDIA_WS: Error $e"),
    );

    // Fetch dynamic ICE servers and MERGE with our hardened defaults
    try {
      final servers = await SignalingService.getIceServers();
      if (servers.isNotEmpty) {
        // We keep our hardened defaults (TCP/TLS) and ADD the backend's servers
        final List<dynamic> currentServers = List.from(_iceConfiguration['iceServers'] ?? []);
        currentServers.addAll(servers);
        _iceConfiguration['iceServers'] = currentServers;
        debugPrint("GAME_MEDIA_WEBRTC: Merged backend servers. Total: ${currentServers.length}");
      }
    } catch (e) {
      debugPrint("GAME_MEDIA_WARNING: Could not fetch ICE servers, using defaults: $e");
    }

    await _initPeerConnection();
    
    // 🔹 HANDSHAKE: Signal that we are connected and ready
    _sendSignal('peer_ready', {'isCaller': _isCaller});
  }

  Future<void> _initPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceConfiguration);

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _sendSignal('candidate', {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    _peerConnection!.onIceConnectionState = (state) {
      debugPrint("GAME_MEDIA_WEBRTC: ICE Connection State: ${state.name}");
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        debugPrint("GAME_MEDIA_WEBRTC: ICE Connection Failed. Restarting ICE...");
        _peerConnection!.restartIce();
      }
    };

    _peerConnection!.onConnectionState = (state) {
      debugPrint("GAME_MEDIA_WEBRTC: Peer Connection State: ${state.name}");
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        debugPrint("GAME_MEDIA_WEBRTC: Connection Failed. Requesting renegotiation...");
        _sendSignal('renegotiate_request', {});
      }
    };

    _peerConnection!.onTrack = (event) {
      debugPrint("GAME_MEDIA_WEBRTC: onTrack: ${event.track.kind}");
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        remoteStreamNotifier.value = null;
        remoteStreamNotifier.value = _remoteStream;
      }
    };

    await _setupLocalStream();
  }

  Future<void> _setupLocalStream() async {
    var micStatus = await Permission.microphone.request();
    var camStatus = await Permission.camera.request();
    
    debugPrint("GAME_MEDIA_PERMISSIONS: Mic: $micStatus, Cam: $camStatus");

    final constraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': {
        'width': {'ideal': 640},
        'height': {'ideal': 480},
        'facingMode': 'user',
      },
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      debugPrint("GAME_MEDIA_WEBRTC: Local stream acquired: ${_localStream?.id}");
      
      // Default: BOTH Audio and Video Muted initially for privacy
      for (var track in _localStream!.getAudioTracks()) {
        track.enabled = false;
      }
      for (var track in _localStream!.getVideoTracks()) {
        track.enabled = false;
      }

      localStreamNotifier.value = _localStream;

      if (_peerConnection != null) {
        _localStream!.getTracks().forEach((track) {
          _peerConnection!.addTrack(track, _localStream!);
          debugPrint("GAME_MEDIA_WEBRTC: Added track to PeerConnection: ${track.kind}");
        });
      }
    } catch (e) {
      debugPrint("GAME_MEDIA_ERROR: Could not get user media: $e");
    }
  }

  void toggleMic(bool enabled) {
    if (_localStream != null) {
      for (var track in _localStream!.getAudioTracks()) {
        track.enabled = enabled;
        debugPrint("GAME_MEDIA_WEBRTC: Audio track enabled: $enabled");
      }
      if (enabled) {
        Helper.setSpeakerphoneOn(true);
      }
      _sendSignal('toggle_mute', {'isMuted': !enabled});
    }
  }

  void toggleRemoteAudioLocally() {
    if (_remoteStream != null) {
      final isCurrentlyMuted = isRemoteMutedLocally.value;
      for (var track in _remoteStream!.getAudioTracks()) {
        track.enabled = isCurrentlyMuted; // If currently muted, we want to unmute (enable = true)
      }
      isRemoteMutedLocally.value = !isCurrentlyMuted;
    }
  }

  Future<void> toggleVideo(bool enabled) async {
    if (_localStream != null) {
      for (var track in _localStream!.getVideoTracks()) {
        track.enabled = enabled;
        debugPrint("GAME_MEDIA_WEBRTC: Video track enabled: $enabled");
      }
      
      _sendSignal('toggle_video', {'isVideoEnabled': enabled});
      
      debugPrint("GAME_MEDIA_WEBRTC: toggleVideo($enabled), isCaller: $_isCaller");
      
      // Renegotiate to ensure peer sees the track state change
      if (enabled) {
        // Wait slightly for track to be fully active
        await Future.delayed(const Duration(milliseconds: 300));
        
        if (_isCaller) {
          debugPrint("GAME_MEDIA_WEBRTC: Renegotiating as caller...");
          await _createOffer();
        } else {
          debugPrint("GAME_MEDIA_WEBRTC: Requesting renegotiation as receiver...");
          _sendSignal('renegotiate_request', {});
        }
      }

      // Force update of local notifier
      localStreamNotifier.value = null;
      localStreamNotifier.value = _localStream;
    } else {
      debugPrint("GAME_MEDIA_WARNING: Cannot toggle video, local stream is null. Attempting setup...");
      await _setupLocalStream();
    }
  }

  void switchCamera() {
    try {
      if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
        Helper.switchCamera(_localStream!.getVideoTracks().first);
        debugPrint("GAME_MEDIA: Switched camera");
      }
    } catch (e) {
      debugPrint("GAME_MEDIA: Error switching camera: $e");
    }
  }

  void requestVideo() {
    _sendSignal('video_request', {});
  }

  void respondVideo(bool accepted) {
    _sendSignal('video_response', {'accepted': accepted});
  }

  Future<void> _createOffer() async {
    try {
      final constraints = {
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': true,
        },
      };
      RTCSessionDescription offer = await _peerConnection!.createOffer(constraints);
      await _peerConnection!.setLocalDescription(offer);
      _sendSignal('offer', offer.sdp);
      debugPrint("GAME_MEDIA_WEBRTC: Offer created and sent");
    } catch (e) {
      debugPrint("GAME_MEDIA_ERROR: Could not create offer: $e");
    }
  }

  void _handleMessage(Map<String, dynamic> data) async {
    final type = data['type'];
    final payload = data['data'];

    switch (type) {
      case 'offer':
        debugPrint("GAME_MEDIA_WEBRTC: Received offer, creating answer...");
        await _peerConnection!.setRemoteDescription(RTCSessionDescription(payload, 'offer'));
        _isRemoteDescriptionSet = true;
        _processCandidateQueue();
        
        final constraints = {
          'mandatory': {
            'OfferToReceiveAudio': true,
            'OfferToReceiveVideo': true,
          },
        };
        RTCSessionDescription answer = await _peerConnection!.createAnswer(constraints);
        await _peerConnection!.setLocalDescription(answer);
        _sendSignal('answer', answer.sdp);
        break;

      case 'answer':
        await _peerConnection!.setRemoteDescription(RTCSessionDescription(payload, 'answer'));
        _isRemoteDescriptionSet = true;
        _processCandidateQueue();
        break;

      case 'candidate':
        final candidate = RTCIceCandidate(
          payload['candidate'],
          payload['sdpMid'],
          payload['sdpMLineIndex'],
        );
        if (_isRemoteDescriptionSet) {
          await _peerConnection!.addCandidate(candidate);
        } else {
          _remoteCandidatesQueue.add(candidate);
        }
        break;

      case 'toggle_mute':
        isOpponentMuted.value = payload['isMuted'] ?? false;
        break;

      case 'toggle_video':
        isOpponentVideoEnabled.value = payload['isVideoEnabled'] ?? false;
        break;

      case 'video_request':
        _videoRequestController.add(null);
        break;
        
      case 'video_response':
        _videoResponseController.add(payload['accepted'] ?? false);
        break;

      case 'renegotiate_request':
        if (_isCaller) {
          debugPrint("GAME_MEDIA_WEBRTC: Received renegotiate request. Creating new offer...");
          await _createOffer();
        }
        break;

      case 'peer_ready':
        debugPrint("GAME_MEDIA_WEBRTC: Peer is ready. IsCaller: ${payload['isCaller']}");
        // If we are the caller and the peer just became ready, send the initial offer
        if (_isCaller) {
          debugPrint("GAME_MEDIA_WEBRTC: Starting initial negotiation...");
          await _createOffer();
        } else {
          // If we are not caller, just confirm we are ready too
          _sendSignal('peer_ready', {'isCaller': _isCaller});
        }
        break;

      case 'recording_started':
        onRemoteEvent?.call('recording_started', payload);
        break;
        
      case 'recording_stopped':
        onRemoteEvent?.call('recording_stopped', payload);
        break;
    }
  }

  void _processCandidateQueue() async {
    for (var candidate in _remoteCandidatesQueue) {
      await _peerConnection!.addCandidate(candidate);
    }
    _remoteCandidatesQueue.clear();
  }

  void _sendSignal(String type, dynamic data) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({
        'type': type,
        'data': data,
      }));
    }
  }

  void dispose() {
    if (isRecordingNotifier.value) {
      FlutterScreenRecording.stopRecordScreen;
    }
    _localStream?.dispose();
    _remoteStream?.dispose();
    _peerConnection?.dispose();
    _channel?.sink.close();
    _videoRequestController.close();
    _videoResponseController.close();
    debugPrint("GAME_MEDIA_WEBRTC: Disposed");
  }

  Future<void> startRecording() async {
    if (isRecordingNotifier.value) return;
    try {
      await Permission.storage.request();
      final hasMic = await Permission.microphone.request().isGranted;

      if (hasMic) {
        final title = 'game_${_gameId}_${DateTime.now().millisecondsSinceEpoch}';
        final success = await FlutterScreenRecording.startRecordScreenAndAudio(title);
        if (success) {
          isRecordingNotifier.value = true;
          recordingStartTime = DateTime.now();
          lastRecordingDuration = null;
          debugPrint("GameMediaService: Screen recording started: $title");
          _sendSignal('recording_started', {});
        } else {
          debugPrint("GameMediaService: Failed to start screen recording");
        }
      } else {
        debugPrint("GameMediaService: Permissions denied for screen recording");
      }
    } catch (e) {
      debugPrint("GameMediaService: Error starting screen recording: $e");
    }
  }

  Future<void> stopRecording(String? opponentUsername) async {
    if (!isRecordingNotifier.value) return;
    try {
      final path = await FlutterScreenRecording.stopRecordScreen;
      isRecordingNotifier.value = false;
      if (recordingStartTime != null) {
        lastRecordingDuration = DateTime.now().difference(recordingStartTime!).inSeconds;
      }
      recordingStartTime = null;
      _sendSignal('recording_stopped', {});
      
      if (path != null && path.isNotEmpty) {
        debugPrint("GameMediaService: Screen recording stopped. Saved locally at $path");
        final currentUser = await _getCurrentUsername();
        // Upload to backend
        final response = await ApiService.saveCallRecording(
          callerUsername: _isCaller ? currentUser : opponentUsername,
          calleeUsername: _isCaller ? opponentUsername : currentUser,
          callType: 'game_call',
          filePath: path,
        );
        debugPrint("GameMediaService: Save screen recording response: $response");
      }
    } catch (e) {
      debugPrint("GameMediaService: Error stopping screen recording: $e");
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
