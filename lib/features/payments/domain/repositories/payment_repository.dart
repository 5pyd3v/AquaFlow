import 'dart:typed_data';

import '../../../../core/utils/result.dart';
import '../../../settlements/domain/entities/settlement_detail_entity.dart';
import '../entities/customer_ledger_entity.dart';
import '../entities/customer_payment_overview_entity.dart';
import '../entities/payment_amendment_entity.dart';
import '../entities/payment_transaction_entity.dart';
import '../entities/record_payment_result.dart';
import '../entities/rider_cash_position_entity.dart';
import '../entities/vendor_finance_kpis_entity.dart';

/// Metadata captured alongside a receipt image for fraud-prevention /
/// audit (hash, capture location, device time).
class ReceiptMeta {
  final String receiptType;
  final String? imageHash;
  final double? gpsLat;
  final double? gpsLng;
  final DateTime? deviceTime;

  const ReceiptMeta({
    this.receiptType = 'cash',
    this.imageHash,
    this.gpsLat,
    this.gpsLng,
    this.deviceTime,
  });

  Map<String, dynamic> toJson() => {
        'receipt_type': receiptType,
        if (imageHash != null) 'image_hash': imageHash,
        if (gpsLat != null) 'gps_lat': gpsLat,
        if (gpsLng != null) 'gps_lng': gpsLng,
        if (deviceTime != null) 'device_time': deviceTime!.toIso8601String(),
      };
}

/// Contract for the payment/credit/settlement-detail layer. Every method
/// returns a `Result` and delegates money mutations to SECURITY DEFINER
/// RPCs so balance math stays transactional and server-side.
abstract class PaymentRepository {
  /// Validates the customer's delivery PIN without changing order state.
  Future<Result<bool>> verifyDeliveryPin({
    required String orderId,
    required String enteredOtp,
  });

  /// Uploads a receipt image to storage and returns its public URL.
  /// Filed under the order id to satisfy the `delivery-proofs` bucket RLS.
  Future<Result<String>> uploadReceipt({
    required String orderId,
    required Uint8List bytes,
  });

  /// Records the payment AND marks the order delivered in one transaction.
  Future<Result<RecordPaymentResult>> completeDeliveryWithPayment({
    required String orderId,
    required String enteredOtp,
    required int amount,
    String? receiptUrl,
    ReceiptMeta? receiptMeta,
    String? notes,
  });

  /// Edit a still-unsettled payment (free). Fails if already settled.
  Future<Result<void>> editPayment({
    required String transactionId,
    required int newAmount,
    required String reason,
  });

  /// Soft-delete a still-unsettled payment. Fails if already settled.
  Future<Result<void>> deletePayment({
    required String transactionId,
    required String reason,
  });

  /// File an amendment request for a settled payment (needs vendor approval).
  Future<Result<void>> requestAmendment({
    required String transactionId,
    required AmendmentAction action,
    int? amount,
    required String reason,
  });

  /// Vendor approves/rejects an amendment request.
  Future<Result<void>> resolveAmendment({
    required String requestId,
    required bool approve,
    String? reason,
  });

  /// Applies available customer wallet credit to a freshly placed order.
  /// Safe no-op when the customer has no credit. Returns the amount applied.
  Future<Result<int>> applyCustomerCredit({
    required String orderId,
    int? amount,
  });

  Future<Result<CustomerLedgerEntity>> getCustomerLedger(String customerProfileId);

  Future<Result<List<PaymentTransactionEntity>>> getOrderPayments(String orderId);

  Future<Result<List<CustomerPaymentOverviewEntity>>> getVendorPaymentOverview(String vendorId);

  Future<Result<List<RiderCashPositionEntity>>> getVendorRiderCashPositions(String vendorId);

  Future<Result<VendorFinanceKpisEntity>> getVendorFinanceKpis(String vendorId);

  Future<Result<List<PaymentAmendmentEntity>>> getVendorAmendmentRequests(String vendorId);

  Future<Result<SettlementDetailEntity>> getSettlementDetail(String settlementId);
}
