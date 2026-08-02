import 'package:flutter_test/flutter_test.dart';

import 'package:aquaflow/features/payments/domain/entities/payment_transaction_entity.dart';

/// Regression coverage for migration 0035: a refund record must never offer
/// its own "Refund" action. `isEditable` alone isn't enough to gate that
/// button because a refund row is itself active+unsettled (refunds are
/// never settled), so it would otherwise pass.
void main() {
  PaymentTransactionEntity txn({
    required PaymentType type,
    required PaymentTxnStatus status,
    required bool settled,
  }) {
    return PaymentTransactionEntity(
      id: 't1',
      orderId: 'o1',
      customerProfileId: 'c1',
      vendorId: 'v1',
      amount: 500,
      outstandingBefore: 500,
      outstandingAfter: 0,
      creditBefore: 0,
      creditAfter: 0,
      type: type,
      status: status,
      settled: settled,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  group('isEditable', () {
    test('true when active and unsettled', () {
      final t = txn(type: PaymentType.full, status: PaymentTxnStatus.active, settled: false);
      expect(t.isEditable, isTrue);
    });

    test('false once settled', () {
      final t = txn(type: PaymentType.full, status: PaymentTxnStatus.active, settled: true);
      expect(t.isEditable, isFalse);
    });

    test('false once soft-deleted', () {
      final t = txn(type: PaymentType.full, status: PaymentTxnStatus.deleted, settled: false);
      expect(t.isEditable, isFalse);
    });

    test('an unsettled refund row is (wrongly, on its own) editable — this is exactly why isRefundable exists', () {
      final t = txn(type: PaymentType.refund, status: PaymentTxnStatus.active, settled: false);
      expect(t.isEditable, isTrue);
    });
  });

  group('isRefundable', () {
    test('true for a normal unsettled full payment', () {
      final t = txn(type: PaymentType.full, status: PaymentTxnStatus.active, settled: false);
      expect(t.isRefundable, isTrue);
    });

    test('true for a normal unsettled partial payment', () {
      final t = txn(type: PaymentType.partial, status: PaymentTxnStatus.active, settled: false);
      expect(t.isRefundable, isTrue);
    });

    test('false for a refund row, even though isEditable is true', () {
      final t = txn(type: PaymentType.refund, status: PaymentTxnStatus.active, settled: false);
      expect(t.isEditable, isTrue, reason: 'sanity check: this is the trap isRefundable must close');
      expect(t.isRefundable, isFalse, reason: 'a refund must never itself be refundable');
    });

    test('false for a settled payment regardless of type', () {
      final t = txn(type: PaymentType.full, status: PaymentTxnStatus.active, settled: true);
      expect(t.isRefundable, isFalse);
    });

    test('false for a deleted row regardless of type', () {
      final t = txn(type: PaymentType.full, status: PaymentTxnStatus.deleted, settled: false);
      expect(t.isRefundable, isFalse);
    });
  });
}
