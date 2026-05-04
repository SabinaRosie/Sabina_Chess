import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/call_manager.dart';
import '../utils/color_utils.dart';

class CallOverlayWidget extends StatefulWidget {
  const CallOverlayWidget({super.key});

  @override
  State<CallOverlayWidget> createState() => _CallOverlayWidgetState();
}

class _CallOverlayWidgetState extends State<CallOverlayWidget> {
  Offset _offset = const Offset(20, 100);
  final CallManager _callManager = CallManager();

  @override
  void initState() {
    super.initState();
    _callManager.onUpdate.listen((_) {
      if (mounted) setState(() {});
    });
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_callManager.roomId == null) return const SizedBox.shrink();

    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _offset += details.delta;
          });
        },
        onTap: () => _callManager.maximize(context),
        child: Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(20),
          color: AppColors.surfaceColor,
          child: Container(
            width: 120,
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.secondaryColor.withOpacity(0.5), width: 2),
              boxShadow: [
                BoxShadow(color: Colors.black54, blurRadius: 10, spreadRadius: 2),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  if (_callManager.remoteVideoEnabled && _callManager.remoteRenderer.srcObject != null)
                    RTCVideoView(
                      _callManager.remoteRenderer,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  else
                    Container(
                      color: AppColors.backgroundColor,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 25,
                              backgroundColor: AppColors.secondaryColor.withOpacity(0.2),
                              child: Text(
                                _callManager.remoteUsername?[0].toUpperCase() ?? "?",
                                style: const TextStyle(color: AppColors.secondaryColor, fontSize: 20),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatDuration(_callManager.callDuration),
                              style: const TextStyle(color: AppColors.secondaryColor, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  // Top Row Controls
                  Positioned(
                    top: 5,
                    right: 5,
                    child: GestureDetector(
                      onTap: () => _callManager.endCall(),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                  
                  // Mute/Camera Status Icons
                  Positioned(
                    bottom: 5,
                    left: 5,
                    child: Row(
                      children: [
                        if (_callManager.isMuted)
                          const Icon(Icons.mic_off, color: Colors.red, size: 14),
                        const SizedBox(width: 4),
                        if (_callManager.isCameraOff)
                          const Icon(Icons.videocam_off, color: Colors.red, size: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
