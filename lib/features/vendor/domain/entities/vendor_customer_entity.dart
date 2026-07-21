import 'package:equatable/equatable.dart';

class VendorCustomerEntity extends Equatable {
  final String profileId;
  final String fullName;
  final String phone;
  final String? email;
  final String? pin;
  final int totalOrders;
  final int outstanding;
  final int availableCredit;
  final String? address;
  final DateTime createdAt;

  const VendorCustomerEntity({
    required this.profileId,
    required this.fullName,
    required this.phone,
    this.email,
    this.pin,
    this.totalOrders = 0,
    this.outstanding = 0,
    this.availableCredit = 0,
    this.address,
    required this.createdAt,
  });

  @override
  List<Object?> get props =>
      [profileId, fullName, phone, email, pin, totalOrders, outstanding, availableCredit, address, createdAt];
}
