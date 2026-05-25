class VideoModel {
  final int id;
  final String title;
  final String description;
  final String videoUrl;
  final String thumbnailUrl;
  final String streamUrl;
  final int duration;
  final int fileSize;
  final int views;
  final Map<String, int> reactionCounts;
  final String? userReaction;
  final int commentsCount;
  final String channelName;
  final String createdAt;

  VideoModel({
    required this.id,
    required this.title,
    required this.description,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.streamUrl,
    required this.duration,
    required this.fileSize,
    required this.views,
    required this.reactionCounts,
    this.userReaction,
    this.commentsCount = 0,
    this.channelName = "Sabina Chess",
    this.createdAt = "",
  });

  factory VideoModel.fromJson(Map<String, dynamic> json) {
    Map<String, int> parsedReactions = {};
    if (json['reaction_counts'] != null) {
      json['reaction_counts'].forEach((key, value) {
        parsedReactions[key.toString()] = value as int;
      });
    }

    return VideoModel(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      videoUrl: json['video_url'] ?? '',
      thumbnailUrl: json['thumbnail_url'] ?? '',
      streamUrl: json['stream_url'] ?? '',
      duration: json['duration'] ?? 0,
      fileSize: json['file_size'] ?? 0,
      views: json['views'] ?? 0,
      reactionCounts: parsedReactions,
      userReaction: json['user_reaction'],
      commentsCount: json['comments_count'] ?? 0,
      createdAt: json['created_at'] ?? DateTime.now().toIso8601String(),
    );
  }
}

class VideoCommentModel {
  final int id;
  final int userId;
  final String userName;
  final String text;
  final String createdAt;

  VideoCommentModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.text,
    required this.createdAt,
  });

  factory VideoCommentModel.fromJson(Map<String, dynamic> json) {
    return VideoCommentModel(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? 0,
      userName: json['user_name'] ?? 'Unknown',
      text: json['text'] ?? '',
      createdAt: json['created_at'] ?? '',
    );
  }
}
