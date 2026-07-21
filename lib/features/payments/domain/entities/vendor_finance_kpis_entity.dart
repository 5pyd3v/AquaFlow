import 'package:equatable/equatable.dart';

/// Vendor finance dashboard KPI aggregates (all whole PKR rupees / counts).
class VendorFinanceKpisEntity extends Equatable {
  final int todaysCollection;
  final int monthsCollection;
  final int pendingCollection;
  final int outstandingCustomers;
  final int creditsIssued;
  final int refunds;
  final int partialCount;
  final int awaitingSettlement;

  const VendorFinanceKpisEntity({
    required this.todaysCollection,
    required this.monthsCollection,
    required this.pendingCollection,
    required this.outstandingCustomers,
    required this.creditsIssued,
    required this.refunds,
    required this.partialCount,
    required this.awaitingSettlement,
  });

  factory VendorFinanceKpisEntity.fromJson(Map<String, dynamic> json) {
    int i(String k) => (json[k] as num?)?.round() ?? 0;
    return VendorFinanceKpisEntity(
      todaysCollection: i('todays_collection'),
      monthsCollection: i('months_collection'),
      pendingCollection: i('pending_collection'),
      outstandingCustomers: i('outstanding_customers'),
      creditsIssued: i('credits_issued'),
      refunds: i('refunds'),
      partialCount: i('partial_count'),
      awaitingSettlement: i('awaiting_settlement'),
    );
  }

  @override
  List<Object?> get props => [
        todaysCollection,
        monthsCollection,
        pendingCollection,
        outstandingCustomers,
        creditsIssued,
        refunds,
        partialCount,
        awaitingSettlement,
      ];
}
