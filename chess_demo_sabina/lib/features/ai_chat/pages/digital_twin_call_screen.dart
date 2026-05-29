import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:chess_demo_sabina/features/ai_chat/services/voice_service.dart';
import 'package:chess_demo_sabina/core/utils/color_utils.dart';

class DigitalTwinCallScreen extends StatefulWidget {
  const DigitalTwinCallScreen({super.key});

  @override
  State<DigitalTwinCallScreen> createState() => _DigitalTwinCallScreenState();
}

class _DigitalTwinCallScreenState extends State<DigitalTwinCallScreen>
    with SingleTickerProviderStateMixin {
  final VoiceService _voiceService = VoiceService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isThinking = false;
  bool _isSpeaking = false;
  String _statusText = "Idle";
  String _transcriptText = "Tap the mic and say something...";
  String _lastWords = "";
  final List<Map<String, dynamic>> _callHistory = [];

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed) {
        if (mounted) {
          setState(() {
            _isSpeaking = false;
            _statusText = "Idle";
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _pulseController.dispose();
    if (_isListening) _speech.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted && _isListening) {
            setState(() {
              _isListening = false;
              _statusText = "Thinking...";
            });
            _sendMessage();
          }
        }
      },
      onError: (error) {
        print('Speech error: $error');
        if (mounted) {
          setState(() {
            _isListening = false;
            _statusText = "Idle";
            _transcriptText = "Could not hear you. Tap to try again.";
          });
        }
      },
    );
  }

  Future<void> _toggleListening() async {
    // Cannot start listening if AI is speaking or thinking
    if (_isThinking || _isSpeaking) return;

    if (_isListening) {
      await _speech.stop();
      setState(() {
        _isListening = false;
        _statusText = "Thinking...";
      });
      _sendMessage();
      return;
    }

    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech recognition not available on this device'),
        ),
      );
      return;
    }

    setState(() {
      _isListening = true;
      _statusText = "Listening...";
      _lastWords = '';
      _transcriptText = "Listening...";
    });

    await _speech.listen(
      onResult: (result) {
        setState(() {
          _lastWords = result.recognizedWords;
          _transcriptText = _lastWords.isEmpty ? "Listening..." : _lastWords;
        });
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      listenMode: stt.ListenMode.dictation,
      cancelOnError: false,
      localeId: 'en_US',
    );
  }

  Future<void> _sendMessage() async {
    if (_lastWords.trim().isEmpty) {
      setState(() {
        _statusText = "Idle";
        _transcriptText = "Tap the mic and say something...";
      });
      return;
    }

    // Add user message to call history
    _callHistory.add({"text": _lastWords, "is_me": true});

    setState(() {
      _isThinking = true;
      _statusText = "Thinking...";
    });

    final response = await _voiceService.chatWithSelf(
      _lastWords,
      skipCache: true,
      conversationHistory: _callHistory,
    );

    if (!mounted) return;

    setState(() {
      _isThinking = false;
    });

    if (response == null || (response['error'] != null && response['text'] == null)) {
      setState(() {
        _statusText = "Error connecting";
        _transcriptText = response?['error'] ?? "Failed to get response.";
      });
      return;
    }

    final responseText = response['text'] ?? "No response text";
    // Add AI response to call history
    _callHistory.add({"text": responseText, "is_me": false});

    setState(() {
      _isSpeaking = true;
      _statusText = "Speaking...";
      _transcriptText = responseText;
    });

    if (response['audio_base64'] != null) {
      final Uint8List bytes = base64Decode(response['audio_base64']);
      _audioPlayer.play(BytesSource(bytes));
    } else if (response['audio_url'] != null) {
      _audioPlayer.play(UrlSource(response['audio_url']));
    } else {
      setState(() {
        _isSpeaking = false;
        _statusText = "Idle";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Digital Twin Call", style: TextStyle(color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 1),
            // Avatar
            Center(
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isSpeaking || _isListening
                            ? Colors.blueAccent.withValues(alpha: 0.5 * (_isListening || _isSpeaking ? _pulseAnimation.value : 1.0))
                            : Colors.blueAccent.withValues(alpha: 0.5),
                        width: 4 * (_isListening || _isSpeaking ? _pulseAnimation.value : 1.0),
                      ),
                      boxShadow: _isSpeaking || _isListening
                          ? [
                              BoxShadow(
                                color: Colors.blueAccent.withValues(alpha: 0.2),
                                blurRadius: 20 * _pulseAnimation.value,
                                spreadRadius: 10 * _pulseAnimation.value,
                              )
                            ]
                          : [],
                    ),
                    child: const CircleAvatar(
                      backgroundColor: Colors.transparent,
                      radius: 70,
                      child: Icon(Icons.person, size: 80, color: Colors.blueAccent),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),
            // Status Text
            Text(
              _statusText,
              style: const TextStyle(
                color: Colors.blueAccent,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            // Transcript Text Box
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _transcriptText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            const Spacer(flex: 5),
            // Mic Button (Replaces Green Call Button)
            GestureDetector(
              onTap: _toggleListening,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _isThinking || _isSpeaking
                      ? Colors.grey.withValues(alpha: 0.5)
                      : _isListening
                          ? Colors.redAccent
                          : Colors.green,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_isListening ? Colors.redAccent : Colors.green).withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    )
                  ],
                ),
                child: Icon(
                  _isThinking ? Icons.more_horiz : (_isListening ? Icons.mic_off : Icons.mic),
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
