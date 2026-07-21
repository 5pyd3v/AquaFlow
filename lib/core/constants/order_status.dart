import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Order lifecycle. Order matters — the index is used to render the
/// tracking timeline and to guard against illegal status transitions
/// on the vendor/rider side.
enum OrderStatus {
  pending,
  accepted,
  assigned,
  pickedUp,
  onTheWay,
  delivered,
  returned,
  completed,
  cancelled,
  rejected;

  String get dbValue => switch (this) {
        OrderStatus.pending => 'pending',
        OrderStatus.accepted => 'accepted',
        OrderStatus.assigned => 'assigned',
        OrderStatus.pickedUp => 'picked_up',
        OrderStatus.onTheWay => 'on_the_way',
        OrderStatus.delivered => 'delivered',
        OrderStatus.returned => 'returned',
        OrderStatus.completed => 'completed',
        OrderStatus.cancelled => 'cancelled',
        OrderStatus.rejected => 'rejected',
      };

  String get label => switch (this) {
        OrderStatus.pending => 'Preparing',
        OrderStatus.accepted => 'Accepted',
        OrderStatus.assigned => 'Rider Assigned',
        OrderStatus.pickedUp => 'Picked Up',
        OrderStatus.onTheWay => 'On the Way',
        OrderStatus.delivered => 'Delivered',
        OrderStatus.returned => 'Bottles Returned',
        OrderStatus.completed => 'Completed',
        OrderStatus.cancelled => 'Cancelled',
        OrderStatus.rejected => 'Rejected',
      };

  Color get color => switch (this) {
        OrderStatus.pending => AppColors.statusPreparing,
        OrderStatus.accepted => AppColors.statusAccepted,
        OrderStatus.assigned => AppColors.statusAssigned,
        OrderStatus.pickedUp => AppColors.statusPickedUp,
        OrderStatus.onTheWay => AppColors.statusOnTheWay,
        OrderStatus.delivered => AppColors.statusDelivered,
        OrderStatus.returned => AppColors.success,
        OrderStatus.completed => AppColors.success,
        OrderStatus.cancelled => AppColors.statusCancelled,
        OrderStatus.rejected => AppColors.statusCancelled,
      };

  bool get isTerminal => this == OrderStatus.completed ||
      this == OrderStatus.cancelled ||
      this == OrderStatus.rejected;

  static OrderStatus fromDbValue(String value) {
    return OrderStatus.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => OrderStatus.pending,
    );
  }

  static const List<OrderStatus> timelineOrder = [
    OrderStatus.pending,
    OrderStatus.accepted,
    OrderStatus.assigned,
    OrderStatus.pickedUp,
    OrderStatus.onTheWay,
    OrderStatus.delivered,
  ];
}
