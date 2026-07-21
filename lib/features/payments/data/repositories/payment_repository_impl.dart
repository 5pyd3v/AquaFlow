import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/utils/result.dart';
import '../../../settlements/domain/entities/settlement_detail_entity.dart';
import '../../domain/entities/customer_ledger_entity.dart';
import '../../domain/entities/customer_payment_overview_entity.dart';
import '../../domain/entities/payment_amendment_entity.dart';
import '../../domain/entities/payment_transaction_entity.dart';
import '../../domain/entities/record_payment_result.dart';
import '../../domain/entities/rider_cash_position_entity.dart';
import '../../domain/entities/vendor_finance_kpis_entity.dart';
import '../../domain/repositories/payment_repository.dart';
import '../models/customer_ledger_model.dart';
import '../models/payment_amendment_model.dart';
import '../models/payment_transaction_model.dart';
import '../models/rider_cash_position_model.dart';

class PaymentRepositoryImpl implements PaymentRepository {
  final sb.SupabaseClient _client;

  PaymentRepositoryImpl({sb.SupabaseClient? client})
      : _client = client ?? SupabaseConfig.client;

  @override
  Future<Result<bool>> verifyDeliveryPin({
    required String orderId,
    required String enteredOtp,
  }) async {
    try {
      final ok = await _client.rpc('verify_delivery_pin_only', params: {
        'p_order_id': orderId,
        'p_entered_otp': enteredOtp,
      });
      return Success(ok == true);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<String>> uploadReceipt({
    required String vendorId,
    required Uint8List bytes,
  }) async {
    try {
      final path = '$vendorId/${const Uuid().v4()}.jpg';
      await _client.storage.from(SupabaseConfig.bucketProofs).uploadBinary(
            path,
            bytes,
            fileOptions: const sb.FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      final url = _client.storage.from(SupabaseConfig.bucketProofs).getPublicUrl(path);
      return Success(url);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<RecordPaymentResult>> completeDeliveryWithPayment({
    required String orderId,
    required String enteredOtp,
    required int amount,
    String? receiptUrl,
    ReceiptMeta? receiptMeta,
    String? notes,
  }) async {
    try {
      final result = await _client.rpc('complete_delivery_with_payment', params: {
        'p_order_id': orderId,
        'p_entered_otp': enteredOtp,
        'p_amount': amount,
        'p_receipt_url': receiptUrl,
        'p_receipt_meta': (receiptMeta ?? const ReceiptMeta()).toJson(),
        'p_notes': notes,
      });
      return Success(RecordPaymentResult.fromJson(_asMap(result)));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> editPayment({
    required String transactionId,
    required int newAmount,
    required String reason,
  }) async {
    try {
      await _client.rpc('edit_payment', params: {
        'p_transaction_id': transactionId,
        'p_new_amount': newAmount,
        'p_reason': reason,
      });
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> deletePayment({
    required String transactionId,
    required String reason,
  }) async {
    try {
      await _client.rpc('delete_payment', params: {
        'p_transaction_id': transactionId,
        'p_reason': reason,
      });
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> requestAmendment({
    required String transactionId,
    required AmendmentAction action,
    int? amount,
    required String reason,
  }) async {
    try {
      await _client.rpc('request_payment_amendment', params: {
        'p_transaction_id': transactionId,
        'p_action': action == AmendmentAction.delete ? 'delete' : 'edit',
        'p_amount': amount,
        'p_reason': reason,
      });
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> resolveAmendment({
    required String requestId,
    required bool approve,
    String? reason,
  }) async {
    try {
      await _client.rpc('resolve_payment_amendment', params: {
        'p_request_id': requestId,
        'p_approve': approve,
        'p_reason': reason,
      });
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<int>> applyCustomerCredit({
    required String orderId,
    int? amount,
  }) async {
    try {
      final result = await _client.rpc('apply_customer_credit', params: {
        'p_order_id': orderId,
        'p_amount': amount,
      });
      final map = _asMap(result);
      return Success((map['applied'] as num?)?.round() ?? 0);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<CustomerLedgerEntity>> getCustomerLedger(String customerProfileId) async {
    try {
      final result = await _client.rpc('get_customer_ledger', params: {
        'p_customer_profile_id': customerProfileId,
      });
      return Success(CustomerLedgerModel.fromJson(_asMap(result)));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<List<PaymentTransactionEntity>>> getOrderPayments(String orderId) async {
    try {
      final rows = await _client
          .from(SupabaseConfig.paymentTransactions)
          .select('*, orders(order_number), payment_receipts(receipt_url)')
          .eq('order_id', orderId)
          .order('created_at', ascending: false);
      final list = (rows as List)
          .map((r) => PaymentTransactionModel.fromJson(r as Map<String, dynamic>))
          .toList();
      return Success(list);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<List<CustomerPaymentOverviewEntity>>> getVendorPaymentOverview(
      String vendorId) async {
    try {
      final rows = await _client.rpc('get_vendor_payment_overview', params: {
        'p_vendor_id': vendorId,
      });
      final list = (rows as List)
          .map((r) => CustomerPaymentOverviewEntity.fromJson(_asMap(r)))
          .toList();
      return Success(list);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<List<RiderCashPositionEntity>>> getVendorRiderCashPositions(
      String vendorId) async {
    try {
      final rows = await _client.rpc('get_vendor_rider_cash_positions', params: {
        'p_vendor_id': vendorId,
      });
      final list = (rows as List)
          .map((r) => RiderCashPositionModel.fromJson(_asMap(r)))
          .toList();
      return Success(list);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<VendorFinanceKpisEntity>> getVendorFinanceKpis(String vendorId) async {
    try {
      final result = await _client.rpc('get_vendor_finance_kpis', params: {
        'p_vendor_id': vendorId,
      });
      return Success(VendorFinanceKpisEntity.fromJson(_asMap(result)));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<List<PaymentAmendmentEntity>>> getVendorAmendmentRequests(
      String vendorId) async {
    try {
      final rows = await _client
          .from(SupabaseConfig.paymentAmendmentRequests)
          .select(
              '*, payment_transactions(amount, orders(order_number)), riders(profiles(full_name))')
          .eq('vendor_id', vendorId)
          .order('created_at', ascending: false);
      final list = (rows as List)
          .map((r) => PaymentAmendmentModel.fromJson(r as Map<String, dynamic>))
          .toList();
      return Success(list);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<SettlementDetailEntity>> getSettlementDetail(String settlementId) async {
    try {
      final result = await _client.rpc('get_settlement_detail', params: {
        'p_settlement_id': settlementId,
      });
      return Success(SettlementDetailEntity.fromJson(_asMap(result)));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  /// Supabase RPC returns dynamic JSON; normalise to a String-keyed map.
  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const FormatException('Unexpected RPC response shape');
  }
}
