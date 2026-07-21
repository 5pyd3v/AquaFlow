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
    this.vendorName,
  });

  @override
  List<Object?> get props => [id, riderId, vendorId, amount, code, status, createdAt, verifiedAt, expiresAt];
}
