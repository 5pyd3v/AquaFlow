import '../../../../core/utils/result.dart';
import '../entities/rating_draft.dart';

abstract class RatingRepository {
  /// Whether the current user has already left any rating on this order.
  Future<Result<bool>> hasRatedOrder(String orderId);

  /// Submit one or more ratings for an order (rider and/or vendor).
  /// Idempotent per target thanks to the DB unique constraints — a
  /// re-submit upserts rather than duplicating.
  Future<Result<void>> submitRatings(List<RatingDraft> drafts);
}
