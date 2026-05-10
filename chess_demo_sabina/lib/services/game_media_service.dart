import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/const.dart';

class GameMediaService {
  WebSocketChannel? _channel;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  final ValueNotifier<MediaStream?> remoteStreamNotifier = ValueNotifier<MediaStream?>(null);
  final ValueNotifier<MediaStream?> localStreamNotifier = ValueNotifier<MediaStream?>(null);
  final ValueNotifier<bool> isOpponentMuted = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isOpponentVideoEnabled = ValueNotifier<bool>(false);

  final _videoRequestController = StreamController<void>.broadcast();
  Stream<void> get onVideoRequest => _videoRequestController.stream;

  final _videoResponseController = StreamController<bool>.broadcast();
  Stream<bool> get onVideoResponse => _videoResponseController.stream;

  bool _isCaller = false;
  String? _gameId;
  String? _token;

  final Map<String, dynamic> _iceConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turn:openrelay.metered.ca:3478',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'sdpSemantics': 'unified-plan',
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

    await _initPeerConnection();
    
    if (_isCaller) {
      await _createOffer();
    }
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

    _peerConnection!.onAddStream = (stream) {
      debugPrint("GAME_MEDIA_WEBRTC: Remote stream added: ${stream.id}");
      _remoteStream = stream;
      remoteStreamNotifier.value = stream;
    };

    _peerConnection!.onTrack = (event) {
      debugPrint("GAME_MEDIA_WEBRTC: onTrack: ${event.track.kind}");
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        remoteStreamNotifier.value = _remoteStream;
      }
    };

    await _setupLocalStream();
  }

  Future<void> _setupLocalStream() async {
    var micStatus = await Permission.microphone.request();
    var camStatus = await Permission.camera.request();
    
    if (!micStatus.isGranted) return;

    final constraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': {
        'mandatory': {
          'minWidth': '640',
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': [],
      },
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    localStreamNotifier.value = _localStream;
    
    // Default: BOTH Audio and Video Muted initially for privacy
    for (var track in _localStream!.getAudioTracks()) {
      track.enabled = false;
    }
    for (var track in _localStream!.getVideoTracks()) {
      track.enabled = false;
    }

    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });
  }

  void toggleMic(bool enabled) {
    if (_localStream != null) {
      for (var track in _localStream!.getAudioTracks()) {
        track.enabled = enabled;
      }
      _sendSignal('toggle_mute', {'isMuted': !enabled});
    }
  }

  void toggleVideo(bool enabled) {
    if (_localStream != null) {
      for (var track in _localStream!.getVideoTracks()) {
        track.enabled = enabled;
      }
      _sendSignal('toggle_video', {'isVideoEnabled': enabled});
      // Force update of local notifier
      localStreamNotifier.value = null;
      localStreamNotifier.value = _localStream;
    }
  }

  void requestVideo() {
    _sendSignal('video_request', {});
  }

  void respondVideo(bool accepted) {
    _sendSignal('video_response', {'accepted': accepted});
  }

  Future<void> _createOffer() async {
    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    _sendSignal('offer', offer.sdp);
  }

  void _handleMessage(Map<String, dynamic> data) async {
    final type = data['type'];
    final payload = data['data'];

    switch (type) {
      case 'offer':
        await _peerConnection!.setRemoteDescription(RTCSessionDescription(payload, 'offer'));
        RTCSessionDescription answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        _sendSignal('answer', answer.sdp);
        break;

      case 'answer':
        await _peerConnection!.setRemoteDescription(RTCSessionDescription(payload, 'answer'));
        break;

      case 'candidate':
        await _peerConnection!.addCandidate(RTCIceCandidate(
          payload['candidate'],
          payload['sdpMid'],
          payload['sdpMLineIndex'],
        ));
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
    }
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
    _localStream?.dispose();
    _remoteStream?.dispose();
    _peerConnection?.dispose();
    _channel?.sink.close();
    _videoRequestController.close();
  }
}
