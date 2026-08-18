class CehUser {
  const CehUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.isActive,
    this.username,
    this.phone,
  });

  final int id;
  final String fullName;
  final String? username;
  final String email;
  final String? phone;
  final String role;
  final bool isActive;

  bool get isAdmin => role.toUpperCase() == 'ADMIN';
  bool get isSupervisor => role.toUpperCase() == 'SUPERVISOR';
  bool get isOperator => role.toUpperCase() == 'OPERATOR';

  factory CehUser.fromJson(Map<String, dynamic> json) {
    return CehUser(
      id: (json['id'] as num).toInt(),
      fullName: (json['full_name'] ?? '').toString(),
      username: json['username']?.toString(),
      email: (json['email'] ?? '').toString(),
      phone: json['phone']?.toString(),
      role: (json['role'] ?? '').toString().toUpperCase(),
      isActive: json['is_active'] == true ||
          json['is_active'] == 1 ||
          json['is_active']?.toString() == '1',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'username': username,
      'email': email,
      'phone': phone,
      'role': role,
      'is_active': isActive,
    };
  }
}

class CehSession {
  const CehSession({
    required this.token,
    required this.tokenType,
    required this.expiresAt,
    required this.user,
  });

  final String token;
  final String tokenType;
  final String expiresAt;
  final CehUser user;

  factory CehSession.fromJson(Map<String, dynamic> json) {
    return CehSession(
      token: (json['token'] ?? '').toString(),
      tokenType: (json['tokenType'] ?? 'Bearer').toString(),
      expiresAt: (json['expiresAt'] ?? '').toString(),
      user: CehUser.fromJson(
        Map<String, dynamic>.from(json['user'] as Map),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'tokenType': tokenType,
      'expiresAt': expiresAt,
      'user': user.toJson(),
    };
  }
}
