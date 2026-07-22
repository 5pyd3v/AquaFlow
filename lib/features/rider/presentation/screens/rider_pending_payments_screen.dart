import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../../payments/domain/repositories/payment_repository.dart';
import '../../../payments/presentation/providers/payment_providers.dart';
import '../../../settlements/presentation/providers/settlement_providers.dart';
import '../../../vendor/domain/entities/vendor_customer_entity.dart';
import '../../../vendor/presentation/providers/vendor_providers.dart';
import '../providers/rider_providers.dart';

/// Rider Pending Payments Collection Module
class RiderPendingPaymentsScreen extends ConsumerStatefulWidget {
  const RiderPendingPaymentsScreen({super.key});

  @override
  ConsumerState<RiderPendingPaymentsScreen> createState() =>
      _RiderPendingPaymentsScreenState();
}

class _RiderPendingPaymentsScreenState
    extends ConsumerState<RiderPendingPaymentsScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final riderAsync = ref.watch(myRiderProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: riderAsync.when(
        loading: () => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 5,
          itemBuilder: (_, __) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: ListTileSkeleton(),
          ),
        ),
        error: (err, _) => ErrorStateView(
          message: err.toString(),
          onRetry: () => ref.invalidate(myRiderProvider),
        ),
        data: (rider) {
          if (rider.vendorId == null) {
            return _NoVendorLinkedView(
              onSignIn: () => ref.invalidate(myRiderProvider),
            );
          }

          final customersAsync = ref.watch(riderPendingCustomersProvider(rider.id));

          return CustomScrollView(
            slivers: [
              _PendingPaymentsHeader(
                vendorName: rider.vendorName ?? 'Vendor',
                query: _query,
                searchController: _searchController,
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
              SliverToBoxAdapter(
                child: customersAsync.when(
                  loading: () => ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: 5,
                    itemBuilder: (_, __) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: ListTileSkeleton(),
                    ),
                  ),
                  error: (e, _) => ErrorStateView(
                    message: e.toString(),
                    onRetry: () => ref.invalidate(riderPendingCustomersProvider(rider.id)),
                  ),
                  data: (allCustomers) {
                    // Filter to customers with outstanding debt > 0
                    final pendingCustomers = allCustomers.where((c) {
                      final hasDebt = c.outstanding > 0;
                      if (!hasDebt) return false;
                      if (_query.isEmpty) return true;
                      return c.fullName.toLowerCase().contains(_query) ||
                          c.phone.contains(_query);
                    }).toList();

                    if (pendingCustomers.isEmpty) {
                      return const EmptyStateView(
                        title: 'No Pending Payments',
                        message: 'All customer orders assigned to you are settled!',
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(riderPendingCustomersProvider(rider.id));
                      },
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: pendingCustomers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          final customer = pendingCustomers[index];
                          return _PendingCustomerCard(
                            customer: customer,
                            vendorId: rider.vendorId!,
                            riderId: rider.id,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );


        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fintech-style Header
// ---------------------------------------------------------------------------
class _PendingPaymentsHeader extends StatelessWidget {
  final String vendorName;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onChanged;

  const _PendingPaymentsHeader({
    required this.vendorName,
    required this.query,
    required this.searchController,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Glass-morphism header with gradient
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFFC96B),
                  Color(0xFFFF9A2E),
                  Color(0xFFF06E0F),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF06E0F).withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  child: const Icon(Icons.payments_rounded,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pending Collections',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        vendorName,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Search bar with modern styling
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: searchController,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: 'Search customer by name or phone...',
                hintStyle: const TextStyle(
                    color: AppColors.textTertiary, fontSize: 14),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: AppColors.textTertiary),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          searchController.clear();
                          onChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// No vendor linked view
// ---------------------------------------------------------------------------
class _NoVendorLinkedView extends StatelessWidget {
  final VoidCallback onSignIn;

  const _NoVendorLinkedView({required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.roleRider.withValues(alpha: 0.3),
                    AppColors.roleRider.withValues(alpha: 0.1),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.link_off_rounded,
                  color: AppColors.roleRider, size: 48),
            ),
            const SizedBox(height: 24),
            Text(
              'Not Linked to Vendor',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'You need to be linked to a vendor to collect pending payments. Ask your vendor to link your account.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 28),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppShadows.brand(opacity: 0.3),
              ),
              child: FilledButton.icon(
                onPressed: onSignIn,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingCustomerCard extends StatelessWidget {
  final VendorCustomerEntity customer;
  final String vendorId;
  final String riderId;

  const _PendingCustomerCard({
    required this.customer,
    required this.vendorId,
    required this.riderId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF8F00), Color(0xFFE65100)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE65100).withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    customer.fullName.isNotEmpty
                        ? customer.fullName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.fullName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      customer.phone,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      customer.outstanding.toCurrency,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFE65100),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pending',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (customer.address != null && customer.address!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_rounded,
                      size: 14, color: AppColors.textTertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      customer.address!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _CollectPendingSheet(
                    customer: customer,
                    vendorId: vendorId,
                    riderId: riderId,
                  ),
                );
              },
              icon: const Icon(Icons.payments_rounded, size: 19),
              label: const Text('Collect Payment'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectPendingSheet extends ConsumerStatefulWidget {
  final VendorCustomerEntity customer;
  final String vendorId;
  final String riderId;

  const _CollectPendingSheet({
    required this.customer,
    required this.vendorId,
    required this.riderId,
  });

  @override
  ConsumerState<_CollectPendingSheet> createState() => _CollectPendingSheetState();
}

class _CollectPendingSheetState extends ConsumerState<_CollectPendingSheet> {
  late final TextEditingController _amountController;
  final _notesController = TextEditingController();

  Uint8List? _receiptBytes;
  bool _submitting = false;
  List<Map<String, dynamic>> _outstandingOrders = [];
  bool _loadingOrders = true;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.customer.outstanding.toString());
    _fetchOutstandingOrders();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _fetchOutstandingOrders() async {
    try {
      // Use outstanding_amount column which is maintained by the server
      // including during refunds (process_refund sets it to 0)
      final rows = await SupabaseConfig.client
          .from(SupabaseConfig.orders)
          .select('id, order_number, outstanding_amount, created_at, status')
          .eq('customer_profile_id', widget.customer.profileId)
          .eq('vendor_id', widget.vendorId)
          .eq('rider_id', widget.riderId)
          .not('status', 'in', '("cancelled","rejected")')
          .gt('outstanding_amount', 0)  // Only fetch orders with outstanding debt
          .order('created_at', ascending: true);


      final list = <Map<String, dynamic>>[];
      for (final r in (rows as List)) {
        final debt = (r['outstanding_amount'] as num?)?.toInt() ?? 0;
        if (debt > 0) {
          list.add({
            'id': r['id'],
            'order_number': r['order_number'],
            'total': (r['outstanding_amount'] as num?)?.toInt() ?? 0, // For display
            'debt': debt,
            'created_at': r['created_at'],
          });
        }
      }

      if (mounted) {
        setState(() {
          _outstandingOrders = list;
          _loadingOrders = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingOrders = false);
    }
  }

  int get _enteredAmount => int.tryParse(_amountController.text.trim()) ?? 0;

  Future<void> _pickReceipt(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 80);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() => _receiptBytes = bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load image: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<(double?, double?)> _captureGps() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return (null, null);
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (null, null);
      }
      final pos = await Geolocator.getCurrentPosition();
      return (pos.latitude, pos.longitude);
    } catch (_) {
      return (null, null);
    }
  }

  Future<void> _submit() async {
    final amount = _enteredAmount;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _submitting = true);
    final controller = ref.read(paymentControllerProvider.notifier);
    final idempotencyKey = const Uuid().v4();

    String? receiptUrl;
    ReceiptMeta? meta;

    if (_receiptBytes != null) {
      // Upload using first order id or fallback customer profile id
      final uploadOrderId = _outstandingOrders.isNotEmpty
          ? _outstandingOrders.first['id'] as String
          : widget.customer.profileId;

      final upload = await controller.uploadReceipt(
        orderId: uploadOrderId,
        bytes: _receiptBytes!,
      );
      final failure = upload.failureOrNull;
      if (failure != null) {
        if (!mounted) return;
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
        );
        return;
      }
      receiptUrl = upload.dataOrNull;
      final hash = sha256.convert(_receiptBytes!).toString();
      final (lat, lng) = await _captureGps();
      meta = ReceiptMeta(
        receiptType: 'cash',
        imageHash: hash,
        gpsLat: lat,
        gpsLng: lng,
        deviceTime: DateTime.now(),
      );
    }

    final result = await controller.collectPendingPayment(
      customerProfileId: widget.customer.profileId,
      vendorId: widget.vendorId,
      amount: amount,
      receiptUrl: receiptUrl,
      receiptMeta: meta,
      notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      idempotencyKey: idempotencyKey,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
      ),
      (data) {
        Navigator.of(context).pop();

        // Invalidate all related providers immediately
        ref.invalidate(vendorCustomersProvider);
        ref.invalidate(vendorCustomersFamilyProvider(widget.vendorId));
        ref.invalidate(customerLedgerProvider(widget.customer.profileId));

        ref.invalidate(myRiderProvider);
        ref.invalidate(riderStatsProvider);
        ref.invalidate(riderCodBalanceProvider(widget.vendorId));

        final settled = (data['settled_amount'] as num?)?.toInt() ?? amount;
        final excess = (data['excess_credit'] as num?)?.toInt() ?? 0;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Collected ${settled.toCurrency} successfully!${excess > 0 ? ' ${excess.toCurrency} added to customer wallet credit.' : ''}',
            ),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 30,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Header
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF8F00), Color(0xFFE65100)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.payments_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Collect Payment',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      widget.customer.fullName,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  widget.customer.outstanding.toCurrency,
                  style: const TextStyle(
                    color: Color(0xFFE65100),
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Total Pending Debt',
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Outstanding Orders (FIFO Allocation)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_loadingOrders)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_outstandingOrders.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'No specific unpaid orders found.',
                        style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                      ),
                    )
                  else
                    Column(
                      children: _outstandingOrders.map((o) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Text(
                                'Order #${o['order_number']}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              const Spacer(),
                              Text(
                                (o['debt'] as int).toCurrency,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.error,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: false),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Amount Collected (PKR)',
                      prefixText: 'PKR ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('Exact Debt'),
                        onPressed: () => _amountController.text = widget.customer.outstanding.toString(),
                      ),
                      ActionChip(
                        label: const Text('500'),
                        onPressed: () => _amountController.text = '500',
                      ),
                      ActionChip(
                        label: const Text('1000'),
                        onPressed: () => _amountController.text = '1000',
                      ),
                      ActionChip(
                        label: const Text('2000'),
                        onPressed: () => _amountController.text = '2000',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Receipt Image (Optional / COD Verification)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickReceipt(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_rounded, size: 18),
                          label: const Text('Camera'),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickReceipt(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_rounded, size: 18),
                          label: const Text('Gallery'),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_receiptBytes != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _receiptBytes!,
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _notesController,
                    decoration: InputDecoration(
                      labelText: 'Notes (Optional)',
                      hintText: 'e.g. Received via cash from customer home',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Submit Pending Collection',
            isLoading: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}
