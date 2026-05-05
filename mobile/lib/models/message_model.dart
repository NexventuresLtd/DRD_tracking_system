class MessageModel {
  final String id;
  final String fromUserId;
  final String? toUserId;
  final String? toTeamId;
  final bool toAll;
  String content;
  final String priority;
  bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;
  final String? fromUserName;

  MessageModel({
    required this.id,
    required this.fromUserId,
    this.toUserId,
    this.toTeamId,
    this.toAll = false,
    required this.content,
    this.priority = 'normal',
    this.isRead = false,
    this.readAt,
    required this.createdAt,
    this.fromUserName,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] ?? '',
      fromUserId: json['from_user_id'] ?? '',
      toUserId: json['to_user_id'],
      toTeamId: json['to_team_id'],
      toAll: json['to_all'] ?? false,
      content: json['content'] ?? '',
      priority: json['priority'] ?? 'normal',
      isRead: json['is_read'] ?? false,
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at']) : null,
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      fromUserName: json['from_user_name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'from_user_id': fromUserId,
      'to_user_id': toUserId,
      'to_team_id': toTeamId,
      'to_all': toAll,
      'content': content,
      'priority': priority,
      'is_read': isRead,
      'read_at': readAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'from_user_name': fromUserName,
    };
  }
}