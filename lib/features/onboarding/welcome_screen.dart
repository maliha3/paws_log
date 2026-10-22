import 'package:flutter/material.dart';

import 'add_pet_screen.dart';

/// First screen of onboarding: what the app is for.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Icon(Icons.pets, size: 88, color: theme.colorScheme.primary),
              const SizedBox(height: 32),
              Text(
                'PawsLog',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Keep track of your cat’s vaccines, deworming and flea '
                'treatments — and get a nudge when something is due.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(flex: 3),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const AddPetScreen(),
                  ),
                ),
                child: const Text('Get started'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
