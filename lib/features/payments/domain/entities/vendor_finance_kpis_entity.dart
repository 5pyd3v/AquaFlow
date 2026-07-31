import 'package:equatable/equatable.dart';

/// Vendor finance dashboard KPI aggregates (all whole PKR rupees / counts).
///
/// Accounting model (see migration 0033):
/// - [totalSales] / [todaysCollection] / [monthsCollection] are cash actually
///   collected, net of refunds. An Rs. 2000 order paid Rs. 1500 contributes
///   Rs. 1500 here and Rs. 500 to [pendingCollection]; collecting that debt
///   later moves it into sales.
/// - [pendingCollection] is money customers still owe.
/// - [awaitingSettlement] is cash physically held by riders only
///   (collected − verified settlements, per rider).
/// - [creditsIssued] is genuine excess only — money left after every
///   outstanding debt the customer had was cleared.
class VendorFinanceKpisEntity extends Equatable {
  final int todaysCollection;
  final int monthsCollection;
  final int totalSales;
  final int pendingCollection;
  final int outstandingCustomers;
  final int creditsIssued;
  final int refunds;
  final int partialCount;
  final int awaitingSettlement;

  const VendorFinanceKpisEntity({
    required this.todaysCollection,
    required this.monthsCollection,
    required this.totalSales,
    required this.pendingCollection,
    required this.outstandingCustomers,
    required this.creditsIssued,
    required this.refunds,
    required this.partialCount,
    required this.awaitingSettlement,
  });

  const VendorFinanceKpisEntity.zero()
      : todaysCollection = 0,
        monthsCollection = 0,
        totalSales = 0,
        pendingCollection = 0,
        outstandingCustomers = 0,
        creditsIssued = 0,
        refunds = 0,
        partialCount = 0,
        awaitingSettlement = 0;

  factory VendorFinanceKpisEntity.fromJson(Map<String, dynamic> json) {
    int i(String k) => (json[k] as num?)?.round() ?? 0;
    return VendorFinanceKpisEntity(
      todaysCollection: i('todays_collection'),
      monthsCollection: i('months_collection'),
      totalSales: i('total_sales'),
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
        totalSales,
        pendingCollection,
        outstandingCustomers,
        creditsIssued,
        refunds,
        partialCount,
        awaitingSettlement,
      ];
}
