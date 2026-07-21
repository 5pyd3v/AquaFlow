import 'package:equatable/equatable.dart';

enum CustomerPaymentStatus { fullyPaid, partiallyPaid, pending }

/// One row of the vendor's per-customer financial overview.
class CustomerPaymentOverviewEntity extends Equatable {
  final String customerProfileId;
  final String fullName;
  final String phone;
  final int totalOrders;
  final int totalPurchases;
  final int totalPaid;
  final int outstanding;
  final int availableCredit;
  final DateTime? lastPaymentAt;
  final CustomerPaymentStatus status;

  const CustomerPaymentOverviewEntity({
    required this.customerProfileId,
    required this.fullName,
    required this.phone,
    required this.totalOrders,
    required this.totalPurchases,
    required this.totalPaid,
    required this.outstanding,
    required this.availableCredit,
    this.lastPaymentAt,
    required this.status,
  });

  factory CustomerPaymentOverviewEntity.fromJson(Map<String, dynamic> json) {
    int i(String k) => (json[k] as num?)?.round() ?? 0;
    return CustomerPaymentOverviewEntity(
      customerProfileId: json['profile_id'] as String,
      fullName: (json['full_name'] as String?)?.trim().isNotEmpty == true
          ? json['full_name'] as String
          : 'Customer',
      phone: json['phone'] as String? ?? '',
      totalOrders: i('total_orders'),
      totalPurchases: i('total_purchases'),
      totalPaid: i('total_paid'),
      outstanding: i('outstanding'),
      availableCredit: i('available_credit'),
      lastPaymentAt: json['last_payment_at'] != null
          ? DateTime.tryParse(json['last_payment_at'] as String)
          : null,
      status: switch (json['payment_status'] as String?) {
        'fully_paid' => CustomerPaymentStatus.fullyPaid,
        'partially_paid' => CustomerPaymentStatus.partiallyPaid,
        _ => CustomerPaymentStatus.pending,
      },
    );
  }

  @override
  List<Object?> get props => [
        customerProfileId,
        fullName,
        phone,
        totalOrders,
        totalPurchases,
        totalPaid,
        outstanding,
        availableCredit,
        lastPaymentAt,
        status,
      ];
}
