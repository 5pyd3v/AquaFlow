import 'package:equatable/equatable.dart';
import '../../../../core/constants/user_role.dart';

/// Pure domain entity — no JSON/Supabase concerns here. The
/// data-layer model (`UserProfileModel`) maps onto this.
class UserProfileEntity extends Equatable {
  final String id;
  final String fullName;
  final String? email;
  final String phone;
  final UserRole role;
  final String? avatarUrl;
  final bool isVerified;
  final bool isActive;
  final DateTime createdAt;

  const UserProfileEntity({
    required this.id,
    required this.fullName,
    this.email,
    required this.phone,
    required this.role,
    this.avatarUrl,
    required this.isVerified,
    required this.isActive,
    required this.createdAt,
  });

  @override
  List<Object?> get props =>
      [id, fullName, email, phone, role, avatarUrl, isVerified, isActive, createdAt];
}
