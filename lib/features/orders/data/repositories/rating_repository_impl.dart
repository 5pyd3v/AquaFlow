import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/rating_draft.dart';
import '../../domain/repositories/rating_repository.dart';

class RatingRepositoryImpl implements RatingRepository {
  final sb.SupabaseClient _client;
  RatingRepositoryImpl({sb.SupabaseClient? client})
      : _client = client ?? SupabaseConfig.client;

  @override
  Future<Result<bool>> hasRatedOrder(String orderId) async {
    try {
      final result =
          await _client.rpc('has_rated_order', params: {'p_order_id': orderId});
      return Success(result as bool? ?? false);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> submitRatings(List<RatingDraft> drafts) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        return const Error(AuthFailure('You need to be signed in to leave a rating.'));
      }
      if (drafts.isEmpty) return const Success(null);

      final rows = drafts
          .map((d) => {
                'order_id': d.orderId,
                'rater_profile_id': userId,
                'rated_rider_id': d.isRider ? d.targetId : null,
                'rated_vendor_id': d.isRider ? null : d.targetId,
                'stars': d.stars,
                'review': (d.review?.trim().isEmpty ?? true) ? null : d.review!.trim(),
              })
          .toList();

      // Plain insert — the ratings RLS grants insert only (no update),
      // and the partial unique indexes on (order_id, rated_rider_id) /
      // (order_id, rated_vendor_id) reject a second rating for the same
      // target. The UI guards this path with `hasRatedOrder`, so we only
      // reach here for a first-time rating.
      await _client.from(SupabaseConfig.ratings).insert(rows);
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }
}
