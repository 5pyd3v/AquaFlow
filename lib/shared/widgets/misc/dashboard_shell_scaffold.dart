import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../features/authentication/presentation/providers/auth_providers.dart';
import 'gradient_hero_header.dart';
import 'role_badge.dart';

/// Shared shell for the four role dashboards. Each role's
/// `presentation/screens` folder renders one of these, passing in the
/// modules that are already built vs. arriving in upcoming slices —
/// this keeps every dashboard honest about what's real today instead
/// of showing broken nav for unfinished sections.
class DashboardModule {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isReady;

  const DashboardModule({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isReady = false,
  });
}

class DashboardShellScaffold extends ConsumerWidget {
  final UserRole role;
  final Color accent;
  final List<DashboardModule> modules;

  const DashboardShellScaffold({
    super.key,
    required this.role,
    required this.accent,
    required this.modules,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: GradientHeroHeader(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(accent, Colors.white, 0.12)!,
                      accent,
                      Color.lerp(accent, Colors.black, 0.28)!,
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: Text(
                          (profile?.fullName.isNotEmpty == true
                                  ? profile!.fullName[0]
                                  : '?')
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile?.fullName.isNotEmpty == true
                                  ? 'Welcome, ${profile!.fullName.split(' ').first}'
                                  : 'Welcome',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            RoleBadge(role: role),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
                        icon: const Icon(Icons.logout_rounded, color: Colors.white),
                        tooltip: 'Sign out',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    '${role.label} Dashboard',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Core modules below light up as each build slice ships.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 18),
                  ...modules.map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ModuleTile(module: m, accent: accent),
                      )),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  final DashboardModule module;
  final Color accent;
  const _ModuleTile({required this.module, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (module.isReady ? accent : AppColors.textTertiary).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(module.icon,
                color: module.isReady ? accent : AppColors.textTertiary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(module.title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(module.subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: module.isReady ? AppColors.successBg : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              module.isReady ? 'Live' : 'Soon',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: module.isReady ? AppColors.success : AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
