import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/const.dart';

class GameVoiceService {
  WebSocketChannel? _channel;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  final ValueNotifier<MediaStream?> remoteStreamNotifier = ValueNotifier<MediaStream?>(null);
  final ValueNotifier<bool> isOpponentMuted = ValueNotifier<bool>(false);

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

    // Use the specific 'call' signaling route on the backend
    final url = Uri.parse('${AppConstants.webSocketUrl}/call/$gameId/?token=$token');
    debugPrint("GAME_VOICE_WS: Connecting to $url");
    _channel = WebSocketChannel.connect(url);

    _channel!.stream.listen(
      (message) {
        final data = jsonDecode(message);
        _handleMessage(data);
      },
      onDone: () => debugPrint("GAME_VOICE_WS: Disconnected"),
      onError: (e) => debugPrint("GAME_VOICE_WS: Error $e"),
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
      _remoteStream = stream;
      remoteStreamNotifier.value = stream;
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        remoteStreamNotifier.value = _remoteStream;
      }
    };

    await _setupLocalStream();
  }

  Future<void> _setupLocalStream() async {
    var status = await Permission.microphone.request();
    if (!status.isGranted) return;

    final constraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    
    // Default: Muted
    for (var track in _localStream!.getAudioTracks()) {
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
  }
}
