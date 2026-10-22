import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'data/providers.dart';
import 'features/onboarding/welcome_screen.dart';
import 'features/today/today_screen.dart';

class PawsLogApp extends StatelessWidget {
  const PawsLogApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PawsLog',
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    home: const _Root(),
  );
}

/// Sends a first-time owner through onboarding and everyone else to Today.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsOnboarding = ref.watch(needsOnboardingProvider);

    // Null while the first database read is in flight.
    if (needsOnboarding == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return needsOnboarding ? const WelcomeScreen() : const TodayScreen();
  }
}
