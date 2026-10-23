import 'package:flutter/material.dart';

import '../pets/pets_screen.dart';
import '../today/today_screen.dart';

/// The app's two tabs once onboarding is behind us.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = [
    (icon: Icons.today_outlined, active: Icons.today, label: 'Today'),
    (icon: Icons.pets_outlined, active: Icons.pets, label: 'Pets'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      // The bar floats over the list rather than sitting in a slab, so the
      // cream background runs the full height of the screen.
      extendBody: true,
      // IndexedStack rather than rebuilding: switching tabs should not throw
      // away a scroll position or restart a database stream.
      body: IndexedStack(
        index: _index,
        children: const [TodayScreen(), PetsScreen()],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: scheme.secondary,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                for (final (index, tab) in _tabs.indexed)
                  Expanded(
                    child: _Tab(
                      icon: index == _index ? tab.active : tab.icon,
                      label: tab.label,
                      selected: index == _index,
                      onTap: () => setState(() => _index = index),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected ? scheme.onPrimary : scheme.onSecondary;

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          // The label is always shown, not just on the selected tab. An
          // icon alone is a guess, and a screen reader has nothing to read.
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
