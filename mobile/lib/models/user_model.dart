class UserModel {
  final String id;
  final String email;
  final String username;
  final String fullName;
  final String role;
  final String? phone;
  final String? teamId;
  final String? teamName;
  final String? teamRole;
  final bool isActive;

  UserModel({
    required this.id,
    required this.email,
    required this.username,
    required this.fullName,
    required this.role,
    this.phone,
    this.teamId,
    this.teamName,
    this.teamRole,
    this.isActive = true,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      username: json['username'] ?? '',
      fullName: json['full_name'] ?? '',
      role: json['role'] ?? 'viewer',
      phone: json['phone'],
      teamId: json['team_id'],
      teamName: json['team_name'],
      teamRole: json['team_role'],
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'full_name': fullName,
      'role': role,
      'phone': phone,
      'team_id': teamId,
      'team_name': teamName,
      'team_role': teamRole,
      'is_active': isActive,
    };
  }

  bool get isAdmin => role == 'super_admin' || role == 'admin';
  bool get isCommander => isAdmin || role == 'commander';
  bool get isOperator => isCommander || role == 'operator';
  bool get isFieldUnit => role == 'field_unit';
  bool get isViewer => role == 'viewer';
}