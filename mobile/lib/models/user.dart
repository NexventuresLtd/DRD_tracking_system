enum UserRole {
  operationsCoordinator,
  planningOfficer,
  teamLeader,
  fieldUser;

  static UserRole fromString(String s) {
    switch (s) {
      case 'operations_coordinator':
        return UserRole.operationsCoordinator;
      case 'planning_officer':
        return UserRole.planningOfficer;
      case 'team_leader':
        return UserRole.teamLeader;
      default:
        return UserRole.fieldUser;
    }
  }

  String get displayName {
    switch (this) {
      case UserRole.operationsCoordinator:
        return 'Operations Coordinator';
      case UserRole.planningOfficer:
        return 'Planning Officer';
      case UserRole.teamLeader:
        return 'Team Leader';
      case UserRole.fieldUser:
        return 'Field User';
    }
  }

  String get apiValue {
    switch (this) {
      case UserRole.operationsCoordinator:
        return 'operations_coordinator';
      case UserRole.planningOfficer:
        return 'planning_officer';
      case UserRole.teamLeader:
        return 'team_leader';
      case UserRole.fieldUser:
        return 'field_user';
    }
  }
}

class User {
  final String id;
  final String email;
  final String username;
  final String fullName;
  final UserRole role;
  final String? phone;
  final String? avatarUrl;
  final bool isActive;
  final bool isVerified;
  final DateTime? lastSeen;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.email,
    required this.username,
    required this.fullName,
    required this.role,
    this.phone,
    this.avatarUrl,
    required this.isActive,
    required this.isVerified,
    this.lastSeen,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        email: j['email'] as String,
        username: j['username'] as String,
        fullName: j['full_name'] as String,
        role: UserRole.fromString(j['role'] as String),
        phone: j['phone'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        isActive: j['is_active'] as bool? ?? true,
        isVerified: j['is_verified'] as bool? ?? false,
        lastSeen: j['last_seen'] != null ? DateTime.parse(j['last_seen'] as String) : null,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'username': username,
        'full_name': fullName,
        'role': role.apiValue,
        'phone': phone,
        'avatar_url': avatarUrl,
        'is_active': isActive,
        'is_verified': isVerified,
        'last_seen': lastSeen?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  User copyWith({
    String? fullName,
    String? phone,
    String? avatarUrl,
  }) =>
      User(
        id: id,
        email: email,
        username: username,
        fullName: fullName ?? this.fullName,
        role: role,
        phone: phone ?? this.phone,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        isActive: isActive,
        isVerified: isVerified,
        lastSeen: lastSeen,
        createdAt: createdAt,
      );
}
