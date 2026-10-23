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

  @override
  Widget build(BuildContext context) => Scaffold(
    // IndexedStack rather than rebuilding: switching tabs should not throw
    // away a scroll position or restart a database stream.
    body: IndexedStack(
      index: _index,
      children: const [TodayScreen(), PetsScreen()],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (index) => setState(() => _index = index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.today_outlined),
          selectedIcon: Icon(Icons.today),
          label: 'Today',
        ),
        NavigationDestination(
          icon: Icon(Icons.pets_outlined),
          selectedIcon: Icon(Icons.pets),
          label: 'Pets',
        ),
      ],
    ),
  );
}
