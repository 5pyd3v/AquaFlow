import 'package:equatable/equatable.dart';

class VendorCodSummaryEntity extends Equatable {
  final double todaysVerified;
  final double totalVerified;
  final int pendingCount;
  final double pendingAmount;

  const VendorCodSummaryEntity({
    required this.todaysVerified,
    required this.totalVerified,
    required this.pendingCount,
    required this.pendingAmount,
  });

  @override
  List<Object?> get props => [todaysVerified, totalVerified, pendingCount, pendingAmount];
}
