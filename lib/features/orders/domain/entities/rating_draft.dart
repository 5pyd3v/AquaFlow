import 'package:equatable/equatable.dart';

/// A customer's rating for one party on a delivered order. Used both for
/// the rider and the vendor — the repository decides which foreign key
/// to populate based on [isRider].
class RatingDraft extends Equatable {
  final String orderId;

  /// `riders.id` or `vendors.id` — the row being rated.
  final String targetId;
  final bool isRider;
  final int stars;
  final String? review;

  const RatingDraft({
    required this.orderId,
    required this.targetId,
    required this.isRider,
    required this.stars,
    this.review,
  });

  @override
  List<Object?> get props => [orderId, targetId, isRider, stars, review];
}
