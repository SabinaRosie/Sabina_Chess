import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../models/video_model.dart';
import '../../services/video_api_service.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../core/services/api_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final VideoModel video;
  const VideoPlayerScreen({super.key, required this.video});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isPlayerReady = false;
  bool _viewIncremented = false;
  String? _errorMessage;
  bool _useSampleVideo = false;

  late VideoModel _currentVideo;
  final VideoApiService _videoApiService = VideoApiService();

  List<VideoCommentModel> _comments = [];
  bool _isLoadingComments = true;
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmittingComment = false;

  final Map<String, IconData> _reactionIcons = {
    'like': Icons.thumb_up_rounded,
    'heart': Icons.favorite_rounded,
    'laugh': Icons.sentiment_very_satisfied_rounded,
    'surprised': Icons.sentiment_neutral_rounded,
    'sad': Icons.sentiment_dissatisfied_rounded,
    'angry': Icons.mood_bad_rounded,
  };

  final Map<String, Color> _reactionColors = {
    'like': Colors.blue,
    'heart': Colors.red,
    'laugh': Colors.orange,
    'surprised': Colors.yellow,
    'sad': Colors.blueGrey,
    'angry': Colors.redAccent,
  };

  @override
  void initState() {
    super.initState();
    _currentVideo = widget.video;
    _initializePlayer();
    _loadComments();
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isPlayerReady = false;
      _errorMessage = null;
    });
    try {
      final url = _useSampleVideo
          ? "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
          : (widget.video.streamUrl.isNotEmpty
              ? widget.video.streamUrl
              : widget.video.videoUrl);

      _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(url));
      await _videoPlayerController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio,
        allowFullScreen: true,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.secondaryColor,
          handleColor: AppColors.secondaryColor,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white54,
        ),
      );

      _videoPlayerController!.addListener(_videoListener);

      setState(() {
        _isPlayerReady = true;
      });

      // If backend has duration=0, send the real duration from the player
      if (_currentVideo.duration == 0 &&
          _videoPlayerController!.value.duration.inSeconds > 0) {
        _videoApiService.updateVideoDuration(
          _currentVideo.id,
          _videoPlayerController!.value.duration.inSeconds,
        );
      }
    } catch (e) {
      debugPrint("Error initializing video player: $e");
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _videoListener() {
    if (_videoPlayerController != null &&
        _videoPlayerController!.value.isInitialized) {
      if (_videoPlayerController!.value.position >=
              _videoPlayerController!.value.duration &&
          _videoPlayerController!.value.duration > Duration.zero) {
        if (!_viewIncremented) {
          _viewIncremented = true;
          _videoApiService.getVideoDetail(_currentVideo.id);
        }
      }
    }
  }

  Future<void> _loadComments() async {
    setState(() => _isLoadingComments = true);
    final token = await ApiService.getValidToken();
    final comments = await _videoApiService.getVideoComments(
      _currentVideo.id,
      token: token,
    );
    if (mounted) {
      setState(() {
        _comments = comments;
        _isLoadingComments = false;
      });
    }
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSubmittingComment = true);
    final token = await ApiService.getValidToken();
    if (token != null) {
      final newComment = await _videoApiService.addComment(
        _currentVideo.id,
        text,
        token,
      );
      if (newComment != null && mounted) {
        setState(() {
          _comments.insert(0, newComment);
          _commentController.clear();
        });
      }
    } else {
      // Handle no token
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login to comment')),
        );
      }
    }
    setState(() => _isSubmittingComment = false);
  }

  Future<void> _toggleReaction(String reactionType) async {
    final token = await ApiService.getValidToken();
    if (token != null) {
      final updatedVideo = await _videoApiService.toggleReaction(
        _currentVideo.id,
        reactionType,
        token,
      );
      if (updatedVideo != null && mounted) {
        setState(() {
          _currentVideo = updatedVideo;
        });
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please login to react')));
      }
    }
  }

  @override
  void dispose() {
    _videoPlayerController?.removeListener(_videoListener);
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Video Player
          Container(
            color: Colors.black,
            width: double.infinity,
            height: MediaQuery.of(context).size.width * (9 / 16),
            child: _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 36,
                          ),
                          const SizedBox(height: 8),
                           Text(
                            "Error: $_errorMessage",
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.secondaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                ),
                                onPressed: _initializePlayer,
                                child: const Text("Retry"),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueGrey,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _useSampleVideo = true;
                                  });
                                  _initializePlayer();
                                },
                                child: const Text("Test Sample Video"),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                : _isPlayerReady && _chewieController != null
                ? Chewie(controller: _chewieController!)
                : const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.secondaryColor,
                    ),
                  ),
          ),

          // Video Details, Reactions, and Comments
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentVideo.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "${_currentVideo.views} Views",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_currentVideo.description.isNotEmpty) ...[
                    Text(
                      _currentVideo.description,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Reactions Row
                  _buildReactionsRow(),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Divider(color: Colors.white24),
                  ),

                  // Comments Section
                  const Text(
                    "Comments",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Add Comment Input
                  _buildCommentInput(),

                  const SizedBox(height: 24),

                  // Comments List
                  _buildCommentsList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionsRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _reactionIcons.keys.map((reactionKey) {
          final isUserReaction = _currentVideo.userReaction == reactionKey;
          final count = _currentVideo.reactionCounts[reactionKey] ?? 0;

          return Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: GestureDetector(
              onTap: () => _toggleReaction(reactionKey),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isUserReaction
                      ? (_reactionColors[reactionKey] ??
                                AppColors.secondaryColor)
                            .withValues(alpha: 0.2)
                      : AppColors.surfaceColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isUserReaction
                        ? (_reactionColors[reactionKey] ??
                              AppColors.secondaryColor)
                        : Colors.white10,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _reactionIcons[reactionKey],
                      size: 18,
                      color: isUserReaction
                          ? (_reactionColors[reactionKey] ??
                                AppColors.secondaryColor)
                          : Colors.white54,
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        count.toString(),
                        style: TextStyle(
                          color: isUserReaction
                              ? (_reactionColors[reactionKey] ??
                                    AppColors.secondaryColor)
                              : Colors.white70,
                          fontWeight: isUserReaction
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCommentInput() {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
            ),
            child: TextField(
              controller: _commentController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: "Add a comment...",
                hintStyle: TextStyle(color: Colors.white38),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: _isSubmittingComment ? null : _submitComment,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: AppColors.secondaryColor,
              shape: BoxShape.circle,
            ),
            child: _isSubmittingComment
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.black,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.send_rounded, color: Colors.black, size: 24),
          ),
        ),
      ],
    );
  }

  Widget _buildCommentsList() {
    if (_isLoadingComments) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: CircularProgressIndicator(color: AppColors.secondaryColor),
        ),
      );
    }

    if (_comments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            "No comments yet. Be the first to comment!",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _comments.length,
      itemBuilder: (context, index) {
        final comment = _comments[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: AppColors.surfaceColor,
                radius: 18,
                child: Text(
                  comment.userName.isNotEmpty
                      ? comment.userName[0].toUpperCase()
                      : 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          comment.userName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(comment.createdAt),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      comment.text,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 7) {
        return "${date.day}/${date.month}/${date.year}";
      } else if (difference.inDays > 0) {
        return "${difference.inDays}d ago";
      } else if (difference.inHours > 0) {
        return "${difference.inHours}h ago";
      } else if (difference.inMinutes > 0) {
        return "${difference.inMinutes}m ago";
      } else {
        return "Just now";
      }
    } catch (e) {
      return dateStr;
    }
  }
}
