import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:chess_demo_sabina/features/ai_chat/services/voice_service.dart';
import 'package:chess_demo_sabina/core/utils/color_utils.dart';

class SelfChatScreen extends StatefulWidget {
  const SelfChatScreen({super.key});

  @override
  State<SelfChatScreen> createState() => _SelfChatScreenState();
}

class _SelfChatScreenState extends State<SelfChatScreen>
    with SingleTickerProviderStateMixin {
  final VoiceService _voiceService = VoiceService();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isTrained = false;
  bool _isLoading = true;
  bool _isRecording = false;

  // Training State
  int _sampleCount = 0;
  final int _targetSamples = 5;
  List<String> _recordedPaths = [];

  // Chat State
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isTyping = false;

  // Voice Chat State
  bool _isListening = false;
  bool _speechAvailable = false;
  String _lastWords = '';

  // Mic pulse animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _loadLocalStatus();
    _initSpeech();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _recorder.dispose();
    _audioPlayer.dispose();
    _msgController.dispose();
    _scrollController.dispose();
    _pulseController.dispose();
    if (_isListening) _speech.stop();
    super.dispose();
  }

  /// Initialize speech recognition
  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted && _isListening) {
            setState(() => _isListening = false);
            // Auto-send if we got any words
            if (_msgController.text.trim().isNotEmpty) {
              _sendMessage();
            }
          }
        }
      },
      onError: (error) {
        print('Speech error: $error');
        if (mounted) setState(() => _isListening = false);
      },
    );
  }

  /// Toggle speech listening
  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      // Send accumulated text
      if (_msgController.text.trim().isNotEmpty) {
        _sendMessage();
      }
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
      _lastWords = '';
    });

    await _speech.listen(
      onResult: (result) {
        setState(() {
          _lastWords = result.recognizedWords;
          _msgController.text = _lastWords;
          _msgController.selection = TextSelection.fromPosition(
            TextPosition(offset: _msgController.text.length),
          );
        });
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
    );
  }

  Future<void> _loadLocalStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final localTrained = prefs.getBool('is_voice_trained') ?? false;
    if (localTrained && mounted) {
      setState(() {
        _isTrained = true;
        _isLoading = false;
      });
    }
    await _checkStatus();
  }

  Future<void> _checkStatus() async {
    final status = await _voiceService.getVoiceStatus();
    final isTrained = status['is_trained'] ?? false;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_voice_trained', isTrained);

    if (mounted) {
      setState(() {
        _isTrained = isTrained;
        _isLoading = false;
      });
    }
  }

  // --- TRAINING LOGIC ---

  Future<void> _startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/sample_${_sampleCount + 1}.m4a';

        await _recorder.start(const RecordConfig(), path: path);
        setState(() => _isRecording = true);
      }
    } catch (e) {
      print("ERROR: Recording failed: $e");
    }
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    setState(() => _isRecording = false);

    if (path != null) {
      setState(() {
        _recordedPaths.add(path);
        _sampleCount++;
      });

      if (_sampleCount >= _targetSamples) {
        _uploadSamples();
      }
    }
  }

  Future<void> _uploadSamples() async {
    setState(() => _isLoading = true);
    final success = await _voiceService.uploadVoiceSamples(_recordedPaths);

    if (success) {
      _checkStatus();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Training failed. Please try again.")),
        );
        setState(() {
          _isLoading = false;
          _sampleCount = 0;
          _recordedPaths.clear();
        });
      }
    }
  }

  Future<void> _deleteProfile() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        title: const Text("Delete Voice Profile?",
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          "This will permanently delete your voice samples and profile. You will need to re-train the AI to talk with yourself again.",
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel",
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      final success = await _voiceService.deleteVoiceProfile();
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('is_voice_trained');
        setState(() {
          _isTrained = false;
          _sampleCount = 0;
          _recordedPaths.clear();
          _messages.clear();
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Voice profile deleted.")),
          );
        }
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to delete profile.")),
          );
        }
      }
    }
  }

  // --- CHAT LOGIC ---

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({"text": text, "is_me": true});
      _msgController.clear();
      _isTyping = true;
    });
    _scrollToBottom();

    final response = await _voiceService.chatWithSelf(
      text,
      conversationHistory: _messages,
    );

    if (!mounted) return;

    if (response == null) {
      setState(() => _isTyping = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Server error: Failed to get response.")),
      );
      return;
    }

    if (response['error'] != null && response['text'] == null) {
      setState(() => _isTyping = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response['error'])),
      );
      return;
    }

    setState(() {
      _isTyping = false;
      _messages.add({
        "text": response['text'] ?? "Error: No response text",
        "is_me": false,
        "audio_id": response['audio_id'],
      });
    });
    _scrollToBottom();

    if (response['audio_url'] == null && response['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Voice Error: ${response['error']}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.woodGradient,
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(color: AppColors.secondaryColor),
          ),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Talk with Yourself",
            style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          if (_isTrained) ...[
            IconButton(
              icon: const Icon(Icons.call, color: AppColors.secondaryColor),
              tooltip: "Digital Twin Call",
              onPressed: () {
                Navigator.pushNamed(context, '/digital-twin-call');
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white70),
              tooltip: "Delete Voice Profile",
              onPressed: _deleteProfile,
            ),
          ],
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.woodGradient,
          ),
        ),
        child: SafeArea(
          child: _isTrained ? _buildChatUI() : _buildTrainingUI(),
        ),
      ),
    );
  }

  Widget _buildTrainingUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mic, size: 80, color: AppColors.secondaryColor),
            const SizedBox(height: 24),
            const Text(
              "Train your digital twin",
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            const Text(
              "Read the following sentence 5 times to clone your voice:\n'Hello, I am training my digital assistant in the Chess Mobile App.'",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 40),
            Text(
              "Samples: $_sampleCount / $_targetSamples",
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AppColors.secondaryColor),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onLongPressStart: (_) => _startRecording(),
              onLongPressEnd: (_) => _stopRecording(),
              child: CircleAvatar(
                radius: 40,
                backgroundColor:
                    _isRecording ? Colors.redAccent : AppColors.secondaryColor,
                child: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  color: AppColors.backgroundColor,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text("Hold to record",
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildChatUI() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              final isMe = msg['is_me'];
              return Align(
                alignment:
                    isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? AppColors.secondaryColor.withOpacity(0.9)
                        : AppColors.surfaceColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.secondaryColor.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Text(msg['text'],
                          style: TextStyle(
                              color: isMe
                                  ? AppColors.backgroundColor
                                  : AppColors.textPrimary)),
                      if (!isMe && msg['audio_id'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: GestureDetector(
                            onTap: () {
                              _audioPlayer
                                  .play(UrlSource(msg['audio_id']));
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.volume_up,
                                    size: 18,
                                    color: AppColors.secondaryColor
                                        .withOpacity(0.8)),
                                const SizedBox(width: 4),
                                Text("Play voice",
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.secondaryColor
                                            .withOpacity(0.8))),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_isTyping)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                SizedBox(width: 16),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.secondaryColor,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  "Your twin is thinking...",
                  style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        // Input area
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Row(
            children: [
              // Text field
              Expanded(
                child: TextField(
                  controller: _msgController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: "Type a message...",
                    hintStyle:
                        const TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: const BorderSide(
                          color: AppColors.secondaryColor),
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              // Send button
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.secondaryColor,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send,
                      color: AppColors.backgroundColor, size: 20),
                  onPressed: _sendMessage,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
