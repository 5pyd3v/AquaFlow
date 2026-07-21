import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/result.dart';
import '../../../rider/presentation/providers/rider_providers.dart';
import '../../../vendor/presentation/providers/vendor_providers.dart';
import '../../data/repositories/settlement_repository_impl.dart';
import '../../domain/entities/cod_balance_entity.dart';
import '../../domain/entities/generate_settlement_result.dart';
import '../../domain/entities/settlement_entity.dart';
import '../../domain/entities/vendor_cod_summary_entity.dart';
import '../../domain/entities/verify_settlement_result.dart';
import '../../domain/repositories/settlement_repository.dart';

final settlementRepositoryProvider =
    Provider<SettlementRepository>((ref) => SettlementRepositoryImpl());

final riderCodBalanceProvider =
    FutureProvider.autoDispose.family<CodBalanceEntity, String>((ref, vendorId) async {
  final rider = await ref.watch(myRiderProvider.future);
  final result = await ref.read(settlementRepositoryProvider).getRiderCodBalance(
        riderId: rider.id,
        vendorId: vendorId,
      );
  return result.fold((failure) => throw failure, (data) => data);
});

final vendorCodSummaryProvider =
    FutureProvider.autoDispose<VendorCodSummaryEntity>((ref) async {
  final vendor = await ref.watch(myVendorProvider.future);
  final result =
      await ref.read(settlementRepositoryProvider).getVendorCodSummary(vendorId: vendor.id);
  return result.fold((failure) => throw failure, (data) => data);
});

final riderSettlementsProvider =
    FutureProvider.autoDispose<List<SettlementEntity>>((ref) async {
  final rider = await ref.watch(myRiderProvider.future);
  final result =
      await ref.read(settlementRepositoryProvider).getRiderSettlements(riderId: rider.id);
  return result.fold((failure) => throw failure, (data) => data);
});

final vendorSettlementsProvider =
    FutureProvider.autoDispose<List<SettlementEntity>>((ref) async {
  final vendor = await ref.watch(myVendorProvider.future);
  final result =
      await ref.read(settlementRepositoryProvider).getVendorSettlements(vendorId: vendor.id);
  return result.fold((failure) => throw failure, (data) => data);
});

class SettlementController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<Result<GenerateSettlementResult>> generate({
    required String riderId,
    required String vendorId,
    required double amount,
  }) async {
    state = const AsyncLoading();
    final result = await ref.read(settlementRepositoryProvider).generateSettlement(
          riderId: riderId,
          vendorId: vendorId,
          amount: amount,
        );
    state = result.fold(
      (f) => AsyncError(f, StackTrace.current),
      (_) => const AsyncData(null),
    );
    if (result.isSuccess) {
      ref.invalidate(riderSettlementsProvider);
    }
    return result;
  }

  Future<Result<VerifySettlementResult>> verify({
    required String code,
    required String vendorId,
  }) async {
    state = const AsyncLoading();
    final result = await ref.read(settlementRepositoryProvider).verifySettlement(
          code: code,
          vendorId: vendorId,
        );
    state = result.fold(
      (f) => AsyncError(f, StackTrace.current),
      (_) => const AsyncData(null),
    );
    if (result.isSuccess) {
      ref.invalidate(vendorSettlementsProvider);
      ref.invalidate(vendorCodSummaryProvider);
    }
    return result;
  }
}

final settlementControllerProvider =
    AsyncNotifierProvider.autoDispose<SettlementController, void>(SettlementController.new);
