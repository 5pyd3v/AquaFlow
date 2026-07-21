import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/inputs/app_text_field.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../domain/entities/rider_profile_entity.dart';
import '../providers/rider_providers.dart';

class RiderAccountScreen extends ConsumerWidget {
  const RiderAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final riderAsync = ref.watch(myRiderProvider);
    final profile = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: riderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorStateView(message: e.toString(), onRetry: () => ref.invalidate(myRiderProvider)),
        data: (rider) => SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _RiderProfileHero(
                rider: rider,
                riderName: profile?.fullName ?? 'Delivery Rider',
                phone: profile?.phone ?? '',
              ),
              const SizedBox(height: 20),
              _RiderPerformanceStrip(rider: rider),
              const SizedBox(height: 22),
              const _SectionHeader(
                icon: Icons.two_wheeler_rounded,
                label: 'Vehicle',
                subtitle: 'Keep this current — vendors see it',
              ),
              const SizedBox(height: 12),
              AppCard(child: _VehicleInfoForm(rider: rider)),
              const SizedBox(height: 20),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: _MenuTile(
                  icon: Icons.logout_rounded,
                  tint: AppColors.error,
                  label: 'Sign Out',
                  subtitle: 'End your session on this device',
                  onTap: () => _confirmSignOut(context, ref),
                ),
              ),
              const SizedBox(height: 24),
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  final version = snapshot.data?.version ?? AppConfig.appVersion;
                  return Center(
                    child: Text('${AppConfig.appName} v$version',
                        style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Sign out?'),
        content: const Text('Your shift will end and you can sign back in anytime.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(authControllerProvider.notifier).signOut();
            },
            child: const Text('Sign Out', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _RiderProfileHero extends StatelessWidget {
  final RiderProfileEntity rider;
  final String riderName;
  final String phone;
  const _RiderProfileHero({required this.rider, required this.riderName, required this.phone});

  @override
  Widget build(BuildContext context) {
    final initial = riderName.isNotEmpty ? riderName[0].toUpperCase() : '?';
    final linked = rider.vendorName != null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFCB70), Color(0xFFFFA531), Color(0xFFE07B00)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppShadows.brand(color: AppColors.roleRider, opacity: 0.35),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 30,
            bottom: -40,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(riderName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 20)),
                        const SizedBox(height: 4),
                        Text(phone,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9), fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Icon(
                      linked ? Icons.storefront_rounded : Icons.info_outline_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        linked
                            ? 'Delivering for ${rider.vendorName}'
                            : 'Not linked — ask a vendor to add you by phone',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RiderPerformanceStrip extends StatelessWidget {
  final RiderProfileEntity rider;
  const _RiderPerformanceStrip({required this.rider});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatMini(
            icon: Icons.star_rounded,
            label: 'Rating',
            value: rider.rating.toStringAsFixed(1),
            tint: AppColors.secondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatMini(
            icon: Icons.local_shipping_rounded,
            label: 'Deliveries',
            value: '${rider.totalDeliveries}',
            tint: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatMini(
            icon: rider.isOnShift ? Icons.bolt_rounded : Icons.pause_circle_rounded,
            label: 'Status',
            value: rider.isOnShift ? 'Online' : 'Off',
            tint: rider.isOnShift ? AppColors.success : AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _StatMini extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color tint;
  const _StatMini({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tint, size: 20),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  const _SectionHeader({required this.icon, required this.label, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.roleRider.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: AppColors.roleRider, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              Text(subtitle,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _MenuTile({
    required this.icon,
    required this.tint,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onTap: onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: tint, size: 22),
      ),
      title: Text(label,
          style: TextStyle(
              color: tint == AppColors.error ? AppColors.error : AppColors.textPrimary,
              fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
    );
  }
}

class _VehicleInfoForm extends ConsumerStatefulWidget {
  final RiderProfileEntity rider;
  const _VehicleInfoForm({required this.rider});

  @override
  ConsumerState<_VehicleInfoForm> createState() => _VehicleInfoFormState();
}

class _VehicleInfoFormState extends ConsumerState<_VehicleInfoForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _vehicleTypeController;
  late final TextEditingController _vehiclePlateController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _vehicleTypeController = TextEditingController(text: widget.rider.vehicleType ?? '');
    _vehiclePlateController = TextEditingController(text: widget.rider.vehiclePlate ?? '');
  }

  @override
  void dispose() {
    _vehicleTypeController.dispose();
    _vehiclePlateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final result = await ref.read(riderRepositoryProvider).updateVehicleInfo(
          vehicleType: _vehicleTypeController.text.trim(),
          vehiclePlate: _vehiclePlateController.text.trim(),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
      ),
      (_) {
        ref.invalidate(myRiderProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vehicle info updated')),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _vehicleTypeController,
            label: 'Vehicle Type',
            hint: 'e.g. Motorcycle, Van',
            validator: (v) => Validators.required(v, field: 'Vehicle type'),
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _vehiclePlateController,
            label: 'Plate Number',
            hint: 'e.g. LEA-1234',
            validator: (v) => Validators.required(v, field: 'Plate number'),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: 'Save Changes', isLoading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}
