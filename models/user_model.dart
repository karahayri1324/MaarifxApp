class UserModel {
  final String uid;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final String? schoolName;
  final String? classLevel;
  final String role;

  UserModel({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.schoolName,
    this.classLevel,
    this.role = 'user',
  });

  String get initials {
    if (displayName != null && displayName!.isNotEmpty) {
      final parts = displayName!.split(' ');
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
      return displayName![0].toUpperCase();
    }
    return email[0].toUpperCase();
  }

  String get displayNameOrEmail => displayName ?? email.split('@')[0];

  bool get isAdmin => role == 'admin';

  String get classLevelDisplay {
    if (classLevel == '7') return '7. Sınıf';
    if (classLevel == '8') return '8. Sınıf';
    if (classLevel == '9') return '9. Sınıf';
    if (classLevel == '10') return '10. Sınıf';
    if (classLevel == '11') return '11. Sınıf';
    return '-';
  }

  UserModel copyWith({
    String? displayName,
    String? schoolName,
    String? classLevel,
    String? role,
  }) {
    return UserModel(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl,
      schoolName: schoolName ?? this.schoolName,
      classLevel: classLevel ?? this.classLevel,
      role: role ?? this.role,
    );
  }
}
