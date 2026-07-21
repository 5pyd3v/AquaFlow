import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../domain/entities/settlement_entity.dart';
import '../providers/settlement_providers.dart';

/// Premium, permanent archive of every settlement a rider has generated.
/// The OTP stays visible + copyable with a live countdown for 24h, then
/// is masked ("OTP Expired") — but the record itself never disappears.
class RiderSettlementHistoryScreen extends ConsumerStatefulWidget {
  const RiderSettlementHistoryScreen({super.key});

  @override
  ConsumerState<RiderSettlementHistoryScreen> createState() =>
      _RiderSettlementHistoryScreenState();
}

class _RiderSettlementHistoryScreenState
    extends ConsumerState<RiderSettlementHistoryScreen> {
  String _search = '';
  SettlementStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(riderSettlementsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settlement History')),
      body: Column(
        children: [
          _searchBar(),
          _statusChips(),
          Expanded(
            child: async.when(
              loading: () => ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: 5,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, __) => const ShimmerBox(height: 92),
              ),
              error: (e, _) => ErrorStateView(
                message: e.toString(),
                onRetry: () => ref.invalidate(riderSettlementsProvider),
              ),
              data: (all) {
                final list = _applyFilters(all);
                if (list.isEmpty) {
                  return const EmptyStateView(
                    title: 'No settlements yet',
                    message:
                        'When you submit collected cash to a vendor, each settlement code shows up here — with a live 24-hour timer.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(riderSettlementsProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _SettlementCard(settlement: list[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<SettlementEntity> _applyFilters(List<SettlementEntity> all) {
    return all.where((s) {
      if (_statusFilter != null && s.status != _statusFilter) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        final hay = '${s.amount} ${s.code} ${s.vendorName ?? ''}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: 'Search by amount, code or vendor',
          prefixIcon: const Icon(Icons.search_rounded),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );
  }

  Widget _statusChips() {
    final options = <(String, SettlementStatus?)>[
      ('All', null),
      ('Pending', SettlementStatus.pending),
      ('Verified', SettlementStatus.verified),
      ('Expired', SettlementStatus.expired),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final (label, status) in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: _statusFilter == status,
                onSelected: (_) => setState(() => _statusFilter = status),
              ),
            ),
        ],
      ),
    );
  }
}

/// One settlement card. Shows the live OTP + countdown while valid,
/// masks it once verified/expired.
class _SettlementCard extends StatefulWidget {
  final SettlementEntity settlement;
  const _SettlementCard({required this.settlement});

  @override
  State<_SettlementCard> createState() => _SettlementCardState();
}

class _SettlementCardState extends State<_SettlementCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (widget.settlement.isOtpVisible) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  (Color, String, IconData) get _statusMeta => switch (widget.settlement.status) {
        SettlementStatus.verified => (const Color(0xFF10B981), 'Verified', Icons.check_circle_rounded),
        SettlementStatus.expired => (AppColors.error, 'Expired', Icons.cancel_rounded),
        SettlementStatus.pending => (const Color(0xFFFF8F00), 'Pending', Icons.hourglass_top_rounded),
      };

  String _fmtCountdown(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settlement;
    final (color, label, icon) = _statusMeta;
    final date = s.verifiedAt ?? s.createdAt;
    final dateStr =
        '${date.day}/${date.month}/${date.year}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.amount.toCurrency,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(dateStr,
                        style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label,
                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _otpBlock(s),
        ],
      ),
    );
  }

  Widget _otpBlock(SettlementEntity s) {
    if (!s.isOtpVisible) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.textTertiary),
            const SizedBox(width: 8),
            Text(
              s.status == SettlementStatus.verified ? 'Settlement verified' : 'OTP Expired',
              style: const TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            const Text('••••••',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 18,
                    letterSpacing: 3,
                    color: AppColors.textTertiary)),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('SETTLEMENT CODE',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
              const Spacer(),
              Icon(Icons.timer_outlined, size: 14, color: Colors.white.withValues(alpha: 0.85)),
              const SizedBox(width: 4),
              Text(_fmtCountdown(s.timeUntilExpiry),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  s.code,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 8,
                      fontFamily: 'monospace'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, color: Colors.white),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: s.code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Settlement code copied')),
                  );
                },
              ),
            ],
          ),
          Text('Share this code with the vendor to confirm your cash settlement.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
        ],
      ),
    );
  }
}
