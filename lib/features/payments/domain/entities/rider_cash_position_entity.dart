import 'package:equatable/equatable.dart';

/// Per-rider cash reconciliation for the vendor dashboard.
/// `outstanding = collected − settled` (both refund-netted) is the true
/// cash the rider still holds. `pendingSettlement` is a separate, smaller
/// figure: the sum of settlement codes the rider has generated but the
/// vendor hasn't verified yet.
class RiderCashPositionEntity extends Equatable {
  final String riderId;
  final String riderName;
  final int collected;
  final int settled;
  final int pendingSettlement;
  final int outstanding;

  const RiderCashPositionEntity({
    required this.riderId,
    required this.riderName,
    required this.collected,
    required this.settled,
    required this.pendingSettlement,
    required this.outstanding,
  });

  @override
  List<Object?> get props =>
      [riderId, riderName, collected, settled, pendingSettlement, outstanding];
}
