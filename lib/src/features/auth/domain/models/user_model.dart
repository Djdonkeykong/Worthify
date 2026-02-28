class UserModel {
  final String id;
  final String email;
  final String? fullName;
  final String? avatarUrl;
  final bool notificationEnabled;
  final bool uploadRemindersEnabled;
  final bool promotionsEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserModel({
    required this.id,
    required this.email,
    this.fullName,
    this.avatarUrl,
    this.notificationEnabled = false,
    this.uploadRemindersEnabled = false,
    this.promotionsEnabled = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      notificationEnabled: json['notification_enabled'] as bool? ?? false,
      uploadRemindersEnabled: json['upload_reminders_enabled'] as bool? ?? false,
      promotionsEnabled: json['promotions_enabled'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'notification_enabled': notificationEnabled,
      'upload_reminders_enabled': uploadRemindersEnabled,
      'promotions_enabled': promotionsEnabled,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? fullName,
    String? avatarUrl,
    bool? notificationEnabled,
    bool? uploadRemindersEnabled,
    bool? promotionsEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      notificationEnabled: notificationEnabled ?? this.notificationEnabled,
      uploadRemindersEnabled: uploadRemindersEnabled ?? this.uploadRemindersEnabled,
      promotionsEnabled: promotionsEnabled ?? this.promotionsEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
