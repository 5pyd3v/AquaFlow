import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/result.dart';
import '../../../settlements/domain/entities/settlement_detail_entity.dart';
import '../../../vendor/presentation/providers/vendor_providers.dart';
import '../../data/repositories/payment_repository_impl.dart';
import '../../domain/entities/customer_ledger_entity.dart';
import '../../domain/entities/customer_payment_overview_entity.dart';
import '../../domain/entities/payment_amendment_entity.dart';
import '../../domain/entities/payment_transaction_entity.dart';
import '../../domain/entities/record_payment_result.dart';
import '../../domain/entities/rider_cash_position_entity.dart';
import '../../domain/entities/vendor_finance_kpis_entity.dart';
import '../../domain/repositories/payment_repository.dart';

final paymentRepositoryProvider =
    Provider<PaymentRepository>((ref) => PaymentRepositoryImpl());

// ---------------------------------------------------------------------------
// Read providers (vendor dashboard + ledgers)
// ---------------------------------------------------------------------------
final vendorFinanceKpisProvider =
    FutureProvider.autoDispose<VendorFinanceKpisEntity>((ref) async {
  final vendor = await ref.watch(myVendorProvider.future);
  final result = await ref.read(paymentRepositoryProvider).getVendorFinanceKpis(vendor.id);
  return result.fold((f) => throw f, (d) => d);
});

final vendorRiderCashPositionsProvider =
    FutureProvider.autoDispose<List<RiderCashPositionEntity>>((ref) async {
  final vendor = await ref.watch(myVendorProvider.future);
  final result =
      await ref.read(paymentRepositoryProvider).getVendorRiderCashPositions(vendor.id);
  return result.fold((f) => throw f, (d) => d);
});

final vendorPaymentOverviewProvider =
    FutureProvider.autoDispose<List<CustomerPaymentOverviewEntity>>((ref) async {
  final vendor = await ref.watch(myVendorProvider.future);
  final result =
      await ref.read(paymentRepositoryProvider).getVendorPaymentOverview(vendor.id);
  return result.fold((f) => throw f, (d) => d);
});

final vendorAmendmentRequestsProvider =
    FutureProvider.autoDispose<List<PaymentAmendmentEntity>>((ref) async {
  final vendor = await ref.watch(myVendorProvider.future);
  final result =
      await ref.read(paymentRepositoryProvider).getVendorAmendmentRequests(vendor.id);
  return result.fold((f) => throw f, (d) => d);
});

final customerLedgerProvider =
    FutureProvider.autoDispose.family<CustomerLedgerEntity, String>((ref, customerProfileId) async {
  final result = await ref.read(paymentRepositoryProvider).getCustomerLedger(customerProfileId);
  return result.fold((f) => throw f, (d) => d);
});

final orderPaymentsProvider =
    FutureProvider.autoDispose.family<List<PaymentTransactionEntity>, String>((ref, orderId) async {
  final result = await ref.read(paymentRepositoryProvider).getOrderPayments(orderId);
  return result.fold((f) => throw f, (d) => d);
});

final settlementDetailProvider =
    FutureProvider.autoDispose.family<SettlementDetailEntity, String>((ref, settlementId) async {
  final result = await ref.read(paymentRepositoryProvider).getSettlementDetail(settlementId);
  return result.fold((f) => throw f, (d) => d);
});

// ---------------------------------------------------------------------------
// Command controller (writes)
// ---------------------------------------------------------------------------
class PaymentController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  PaymentRepository get _repo => ref.read(paymentRepositoryProvider);

  Future<Result<bool>> verifyPin({required String orderId, required String otp}) async {
    state = const AsyncLoading();
    final result = await _repo.verifyDeliveryPin(orderId: orderId, enteredOtp: otp);
    state = result.fold((f) => AsyncError(f, StackTrace.current), (_) => const AsyncData(null));
    return result;
  }

  Future<Result<String>> uploadReceipt({
    required String orderId,
    required Uint8List bytes,
  }) async {
    return _repo.uploadReceipt(orderId: orderId, bytes: bytes);
  }

  Future<Result<RecordPaymentResult>> completeWithPayment({
    required String orderId,
    required String otp,
    required int amount,
    String? receiptUrl,
    ReceiptMeta? receiptMeta,
    String? notes,
  }) async {
    state = const AsyncLoading();
    final result = await _repo.completeDeliveryWithPayment(
      orderId: orderId,
      enteredOtp: otp,
      amount: amount,
      receiptUrl: receiptUrl,
      receiptMeta: receiptMeta,
      notes: notes,
    );
    state = result.fold((f) => AsyncError(f, StackTrace.current), (_) => const AsyncData(null));
    return result;
  }

  Future<Result<void>> editPayment({
    required String transactionId,
    required int newAmount,
    required String reason,
  }) async {
    state = const AsyncLoading();
    final result =
        await _repo.editPayment(transactionId: transactionId, newAmount: newAmount, reason: reason);
    state = result.fold((f) => AsyncError(f, StackTrace.current), (_) => const AsyncData(null));
    _invalidateVendorViews();
    return result;
  }

  Future<Result<void>> deletePayment({
    required String transactionId,
    required String reason,
  }) async {
    state = const AsyncLoading();
    final result = await _repo.deletePayment(transactionId: transactionId, reason: reason);
    state = result.fold((f) => AsyncError(f, StackTrace.current), (_) => const AsyncData(null));
    _invalidateVendorViews();
    return result;
  }

  Future<Result<void>> requestAmendment({
    required String transactionId,
    required AmendmentAction action,
    int? amount,
    required String reason,
  }) async {
    state = const AsyncLoading();
    final result = await _repo.requestAmendment(
        transactionId: transactionId, action: action, amount: amount, reason: reason);
    state = result.fold((f) => AsyncError(f, StackTrace.current), (_) => const AsyncData(null));
    return result;
  }

  Future<Result<void>> resolveAmendment({
    required String requestId,
    required bool approve,
    String? reason,
  }) async {
    state = const AsyncLoading();
    final result =
        await _repo.resolveAmendment(requestId: requestId, approve: approve, reason: reason);
    state = result.fold((f) => AsyncError(f, StackTrace.current), (_) => const AsyncData(null));
    if (result.isSuccess) {
      ref.invalidate(vendorAmendmentRequestsProvider);
      _invalidateVendorViews();
    }
    return result;
  }

  Future<Result<int>> getOrderOutstanding(String orderId) async {
    return _repo.getOrderOutstanding(orderId);
  }

  Future<Result<int>> getCustomerTotalOutstanding({
    required String customerProfileId,
    required String vendorId,
  }) async {
    return _repo.getCustomerTotalOutstanding(
      customerProfileId: customerProfileId,
      vendorId: vendorId,
    );
  }

  Future<Result<void>> processRefund({
    required String transactionId,
    required int amount,
    required String reason,
  }) async {
    state = const AsyncLoading();
    final result = await _repo.processRefund(
      transactionId: transactionId,
      amount: amount,
      reason: reason,
    );
    state = result.fold((f) => AsyncError(f, StackTrace.current), (_) => const AsyncData(null));
    return result;
  }

  void _invalidateVendorViews() {
    ref.invalidate(vendorFinanceKpisProvider);
    ref.invalidate(vendorPaymentOverviewProvider);
    ref.invalidate(vendorRiderCashPositionsProvider);
  }
}

final paymentControllerProvider =
    AsyncNotifierProvider.autoDispose<PaymentController, void>(PaymentController.new);
