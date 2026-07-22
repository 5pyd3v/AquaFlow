import 'package:equatable/equatable.dart';
import '../../../../core/constants/order_status.dart';

class OrderItemEntity extends Equatable {
  final String id;
  final String productId;
  final String productName;
  final String? productImageUrl;
  final int quantity;
  final double unitPrice;
  final double unitDeposit;

  const OrderItemEntity({
    required this.id,
    required this.productId,
    required this.productName,
    this.productImageUrl,
    required this.quantity,
    required this.unitPrice,
    required this.unitDeposit,
  });

  double get lineTotal => unitPrice * quantity;

  @override
  List<Object?> get props =>
      [id, productId, productName, productImageUrl, quantity, unitPrice, unitDeposit];
}

class OrderEntity extends Equatable {
  final String id;
  final String orderNumber;
  final String vendorId;
  final String vendorName;
  final String? riderId;
  final String? riderName;
  final String? riderPhone;
  final String? deliveryCode;
  final OrderStatus status;
  final String deliveryAddress;
  final bool isEmergency;
  final double subtotal;
  final double depositTotal;
  final double discountAmount;
  final double deliveryFee;
  final double totalAmount;
  final String paymentMethod;
  final String paymentStatus;
  final int amountPaid;
  final int outstandingAmount;
  final int creditApplied;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final List<OrderItemEntity> items;

  const OrderEntity({
    required this.id,
    required this.orderNumber,
    required this.vendorId,
    required this.vendorName,
    this.riderId,
    this.riderName,
    this.riderPhone,
    this.deliveryCode,
    required this.status,
    required this.deliveryAddress,
    required this.isEmergency,
    required this.subtotal,
    required this.depositTotal,
    required this.discountAmount,
    required this.deliveryFee,
    required this.totalAmount,
    required this.paymentMethod,
    required this.paymentStatus,
    this.amountPaid = 0,
    this.outstandingAmount = 0,
    this.creditApplied = 0,
    required this.createdAt,
    this.deliveredAt,
    this.items = const [],
  });

  /// True once any part of this order's payment has been refunded.
  bool get isRefunded => paymentStatus == 'refunded';

  @override
  List<Object?> get props => [
        id,
        orderNumber,
        vendorId,
        vendorName,
        riderId,
        riderName,
        riderPhone,
        deliveryCode,
        status,
        deliveryAddress,
        isEmergency,
        subtotal,
        depositTotal,
        discountAmount,
        deliveryFee,
        totalAmount,
        paymentMethod,
        paymentStatus,
        amountPaid,
        outstandingAmount,
        creditApplied,
        createdAt,
        deliveredAt,
        items,
      ];
}
