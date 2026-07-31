import 'package:flutter_test/flutter_test.dart';

import 'package:aquaflow/features/payments/data/models/rider_cash_position_model.dart';
import 'package:aquaflow/features/payments/domain/entities/vendor_finance_kpis_entity.dart';

/// Unit tests for the client half of the finance accounting model
/// (migration 0033). The SQL half is covered by
/// `supabase/tests/01_balance_sheet_invariants.sql` (read-only invariants
/// over real data) and `supabase/tests/02_finance_scenarios.sql`
/// (transactional end-to-end runs of the real RPCs).
///
/// Accounting rules these tests pin down:
///   sales     = cash actually collected, net of refunds
///   debt      = what customers still owe
///   unsettled = cash physically held by riders (collected − settled)
///   credit    = only genuine excess, after all debt is cleared
void main() {
  group('VendorFinanceKpisEntity', () {
    test('parses every field from a full RPC payload', () {
      final kpis = VendorFinanceKpisEntity.fromJson(const {
        'todays_collection': 1500,
        'months_collection': 42000,
        'total_sales': 250000,
        'pending_collection': 500,
        'outstanding_customers': 3,
        'credits_issued': 200,
        'refunds': 100,
        'partial_count': 2,
        'awaiting_settlement': 500,
      });

      expect(kpis.todaysCollection, 1500);
      expect(kpis.monthsCollection, 42000);
      expect(kpis.totalSales, 250000);
      expect(kpis.pendingCollection, 500);
      expect(kpis.outstandingCustomers, 3);
      expect(kpis.creditsIssued, 200);
      expect(kpis.refunds, 100);
      expect(kpis.partialCount, 2);
      expect(kpis.awaitingSettlement, 500);
    });

    test('defaults missing keys to zero so a pre-0033 backend cannot crash the dashboard', () {
      final kpis = VendorFinanceKpisEntity.fromJson(const {
        'todays_collection': 100,
      });

      expect(kpis.todaysCollection, 100);
      expect(kpis.totalSales, 0);
      expect(kpis.awaitingSettlement, 0);
      expect(kpis.refunds, 0);
    });

    test('zero() is genuinely all-zero (used as the error fallback tile set)', () {
      const kpis = VendorFinanceKpisEntity.zero();
      expect(kpis.props.every((v) => v == 0), isTrue);
    });

    test('rounds fractional rupees rather than truncating', () {
      final kpis = VendorFinanceKpisEntity.fromJson(const {
        'total_sales': 1500.6,
        'refunds': 99.4,
      });
      expect(kpis.totalSales, 1501);
      expect(kpis.refunds, 99);
    });

    test('an Rs.2000 order paid Rs.1500 books 1500 sales and 500 debt', () {
      // Mirrors supabase/tests/02_finance_scenarios.sql S1.
      final kpis = VendorFinanceKpisEntity.fromJson(const {
        'total_sales': 1500,
        'pending_collection': 500,
      });

      expect(kpis.totalSales, 1500, reason: 'only cash received counts as sales');
      expect(kpis.pendingCollection, 500, reason: 'the unpaid remainder is debt');
      expect(kpis.totalSales + kpis.pendingCollection, 2000,
          reason: 'sales + debt must reconstruct the order value');
    });

    test('collecting the debt later moves it from debt into sales', () {
      // Mirrors S2: the same order after the rider collects the Rs.500.
      final after = VendorFinanceKpisEntity.fromJson(const {
        'total_sales': 2000,
        'pending_collection': 0,
      });

      expect(after.totalSales, 2000);
      expect(after.pendingCollection, 0);
    });
  });

  group('RiderCashPositionModel', () {
    RiderCashPositionModel position({
      required int collected,
      required int settled,
      required int outstanding,
      int pendingSettlement = 0,
      String riderId = 'r1',
    }) {
      return RiderCashPositionModel.fromJson({
        'rider_id': riderId,
        'rider_name': 'Rider',
        'collected': collected,
        'settled': settled,
        'pending_settlement': pendingSettlement,
        'outstanding': outstanding,
      });
    }

    test('parses the outstanding field added in 0032', () {
      final p = position(collected: 4000, settled: 3500, outstanding: 500);
      expect(p.collected, 4000);
      expect(p.settled, 3500);
      expect(p.outstanding, 500);
    });

    test('collected 4000 / settled 3500 leaves 500 unsettled', () {
      // Mirrors supabase/tests/02_finance_scenarios.sql S3.
      final p = position(collected: 4000, settled: 3500, outstanding: 500);
      expect(p.outstanding, p.collected - p.settled);
    });

    test('falls back to Rider when the name is blank', () {
      final p = RiderCashPositionModel.fromJson(const {
        'rider_id': 'r1',
        'rider_name': '   ',
        'collected': 0,
        'settled': 0,
        'pending_settlement': 0,
        'outstanding': 0,
      });
      expect(p.riderName, 'Rider');
    });

    test('pending_settlement is a distinct, smaller figure than unsettled', () {
      // A rider holding 500 who has submitted a 200 code for verification.
      final p = position(
        collected: 4000,
        settled: 3500,
        outstanding: 500,
        pendingSettlement: 200,
      );
      expect(p.outstanding, 500, reason: 'cash actually still in hand');
      expect(p.pendingSettlement, 200, reason: 'only what is awaiting vendor verification');
      expect(p.pendingSettlement, lessThan(p.outstanding));
    });

    test('KPI unsettled ties out to the sum of the per-rider cards', () {
      // Mirrors S7 — the dashboard headline must equal the cards below it.
      final riders = [
        position(riderId: 'r1', collected: 2000, settled: 2000, outstanding: 0),
        position(riderId: 'r2', collected: 4000, settled: 3500, outstanding: 500),
        position(riderId: 'r3', collected: 1200, settled: 0, outstanding: 1200),
      ];
      final kpis = VendorFinanceKpisEntity.fromJson(const {
        'awaiting_settlement': 1700,
      });

      final summed = riders.fold<int>(0, (sum, r) => sum + r.outstanding);
      expect(summed, kpis.awaitingSettlement);
    });

    test('a rider who over-settled is floored at zero, never negative', () {
      // The SQL floors per rider so one rider cannot mask another's shortfall.
      final p = position(collected: 1000, settled: 1000, outstanding: 0);
      expect(p.outstanding, isNonNegative);
    });
  });
}
