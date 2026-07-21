import 'package:equatable/equatable.dart';

/// Per-rider cash reconciliation for the vendor dashboard.
/// `pending = collected − settled` is the cash the rider still holds.
class RiderCashPositionEntity extends Equatable {
  final String riderId;
  final String riderName;
  final int collected;
  final int settled;
  final int pendingSettlement;

  const RiderCashPositionEntity({
    required this.riderId,
    required this.riderName,
    required this.collected,
    required this.settled,
    required this.pendingSettlement,
  });

  @override
  List<Object?> get props => [riderId, riderName, collected, settled, pendingSettlement];
}
