import 'package:equatable/equatable.dart';

enum SettlementStatus { pending, verified, expired }

class SettlementEntity extends Equatable {
  final String id;
  final String riderId;
  final String vendorId;
  final double amount;
  final String code;
  final SettlementStatus status;
  final DateTime createdAt;
  final DateTime? verifiedAt;
  final DateTime expiresAt;
  final String? riderName;
  final String? riderPhone;
  final String? vendorName;

  const SettlementEntity({
    required this.id,
    required this.riderId,
    required this.vendorId,
    required this.amount,
    required this.code,
    required this.status,
    required this.createdAt,
    this.verifiedAt,
    required this.expiresAt,
    this.riderName,
    this.riderPhone,
    this.vendorName,
  });

  /// The OTP is only shown while the settlement is still pending AND
  /// within its 24h window. After verification or expiry it must be
  /// masked ("OTP Expired") even though the record stays visible forever.
  bool get isOtpVisible =>
      status == SettlementStatus.pending && DateTime.now().isBefore(expiresAt);

  /// Whole-second remaining until expiry (clamped at zero). Drives the
  /// live countdown on the settlement card while the OTP is valid.
  Duration get timeUntilExpiry {
    final diff = expiresAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  @override
  List<Object?> get props => [id, riderId, vendorId, amount, code, status, createdAt, verifiedAt, expiresAt];
}
