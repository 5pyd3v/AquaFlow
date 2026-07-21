import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';

class AppNavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const AppNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// Bottom-nav host shared by the customer / vendor / rider shells.
///
/// Owns the tab [IndexedStack] (so each tab keeps its scroll + provider
/// state) and, crucially, the system-back behaviour: on any tab other
/// than the first, back returns to the first tab; on the first tab, a
/// single back press shows a "press again to exit" hint and only a
/// second press within two seconds actually leaves the app. This is
/// what stops the back button from popping the home route off the
/// stack and re-triggering the router's onboarding/login redirects.
class AppNavShell extends StatefulWidget {
  final List<Widget> tabs;
  final List<AppNavDestination> destinations;
  final Color indicatorColor;
  final ValueChanged<int>? onTabChanged;

  const AppNavShell({
    super.key,
    required this.tabs,
    required this.destinations,
    required this.indicatorColor,
    this.onTabChanged,
  });

  @override
  State<AppNavShell> createState() => _AppNavShellState();
}

class _AppNavShellState extends State<AppNavShell> {
  int _index = 0;
  DateTime? _lastBackPress;

  Future<bool> _handlePop() async {
    if (_index != 0) {
      setState(() => _index = 0);
      widget.onTabChanged?.call(0);
      return false;
    }
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
          ),
        );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await _handlePop();
        if (shouldExit) {
          // Minimise to background rather than tearing down the app —
          // matches native launcher behaviour on Android.
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(index: _index, children: widget.tabs),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) {
            setState(() => _index = value);
            widget.onTabChanged?.call(value);
          },
          backgroundColor: AppColors.surface,
          indicatorColor: widget.indicatorColor,
          destinations: [
            for (final d in widget.destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      ),
    );
  }
}
