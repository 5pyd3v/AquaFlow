import 'package:equatable/equatable.dart';

class VendorStatsEntity extends Equatable {
  final int todaysOrders;
  final int pendingOrders;
  final int completedOrders;
  final double todaysRevenue;
  final int totalProducts;
  final int lowStockProducts;
  final int totalRiders;

  const VendorStatsEntity({
    required this.todaysOrders,
    required this.pendingOrders,
    required this.completedOrders,
    required this.todaysRevenue,
    required this.totalProducts,
    required this.lowStockProducts,
    required this.totalRiders,
  });

  @override
  List<Object?> get props =>
      [todaysOrders, pendingOrders, completedOrders, todaysRevenue, totalProducts, lowStockProducts, totalRiders];
}
