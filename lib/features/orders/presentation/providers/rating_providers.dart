import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/result.dart';
import '../../data/repositories/rating_repository_impl.dart';
import '../../domain/entities/rating_draft.dart';
import '../../domain/repositories/rating_repository.dart';

final ratingRepositoryProvider = Provider<RatingRepository>((ref) {
  return RatingRepositoryImpl();
});

/// Whether the signed-in customer has already rated a given order —
/// gates the auto-opening rating sheet on the tracking screen.
final hasRatedOrderProvider =
    FutureProvider.family.autoDispose<bool, String>((ref, orderId) async {
  final result = await ref.read(ratingRepositoryProvider).hasRatedOrder(orderId);
  return result.fold((_) => true, (rated) => rated);
});

final submitRatingControllerProvider =
    AsyncNotifierProvider.autoDispose<SubmitRatingController, void>(
        SubmitRatingController.new);

class SubmitRatingController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<Result<void>> submit(List<RatingDraft> drafts) async {
    state = const AsyncLoading();
    final result = await ref.read(ratingRepositoryProvider).submitRatings(drafts);
    state = result.fold(
      (failure) => AsyncError(failure, StackTrace.current),
      (_) => const AsyncData(null),
    );
    return result;
  }
}
