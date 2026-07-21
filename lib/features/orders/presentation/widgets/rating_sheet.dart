import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../domain/entities/order_entity.dart';
import '../../domain/entities/rating_draft.dart';
import '../providers/rating_providers.dart';

/// Bottom sheet shown once an order is delivered. Lets the customer rate
/// the vendor and (if one was assigned) the rider, plus leave an optional
/// note. Returns `true` when a rating was successfully submitted.
Future<bool?> showRatingSheet(BuildContext context, OrderEntity order) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => RatingSheet(order: order),
  );
}

class RatingSheet extends ConsumerStatefulWidget {
  final OrderEntity order;
  const RatingSheet({super.key, required this.order});

  @override
  ConsumerState<RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends ConsumerState<RatingSheet> {
  int _vendorStars = 0;
  int _riderStars = 0;
  final _reviewController = TextEditingController();

  bool get _hasRider => widget.order.riderId != null;

  bool get _canSubmit =>
      _vendorStars > 0 || (_hasRider && _riderStars > 0);

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final drafts = <RatingDraft>[
      if (_vendorStars > 0)
        RatingDraft(
          orderId: widget.order.id,
          targetId: widget.order.vendorId,
          isRider: false,
          stars: _vendorStars,
          review: _reviewController.text,
        ),
      if (_hasRider && _riderStars > 0)
        RatingDraft(
          orderId: widget.order.id,
          targetId: widget.order.riderId!,
          isRider: true,
          stars: _riderStars,
          review: _reviewController.text,
        ),
    ];

    final result =
        await ref.read(submitRatingControllerProvider.notifier).submit(drafts);
    if (!mounted) return;
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
      ),
      (_) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thanks for your feedback! 💙'),
            backgroundColor: AppColors.success,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSubmitting = ref.watch(submitRatingControllerProvider).isLoading;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      gradient: AppColors.brandGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 34),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Order delivered!',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'How was order #${widget.order.orderNumber}?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                _RatingRow(
                  title: 'Rate ${widget.order.vendorName}',
                  subtitle: 'The store & products',
                  icon: Icons.storefront_rounded,
                  stars: _vendorStars,
                  onChanged: (v) => setState(() => _vendorStars = v),
                ),
                if (_hasRider) ...[
                  const SizedBox(height: 16),
                  _RatingRow(
                    title: 'Rate ${widget.order.riderName ?? 'your rider'}',
                    subtitle: 'Delivery experience',
                    icon: Icons.pedal_bike_rounded,
                    stars: _riderStars,
                    onChanged: (v) => setState(() => _riderStars = v),
                  ),
                ],
                const SizedBox(height: 20),
                TextField(
                  controller: _reviewController,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Add a note (optional)',
                  ),
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Submit Rating',
                  isLoading: isSubmitting,
                  onPressed: _canSubmit ? _submit : null,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Maybe later'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final int stars;
  final ValueChanged<int> onChanged;

  const _RatingRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.stars,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(5, (i) {
              final value = i + 1;
              final filled = value <= stars;
              return GestureDetector(
                onTap: () => onChanged(value),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 38,
                    color: filled ? AppColors.secondary : AppColors.textTertiary,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
