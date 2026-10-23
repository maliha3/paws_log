import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/widgets/cat_illustration.dart';
import '../../core/widgets/pill_button.dart';
import '../../core/widgets/soft_backdrop.dart';

import 'add_pet_screen.dart';

/// First screen of onboarding: what the app is for.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SoftBackdrop(
        child: SafeArea(
          // Scrollable with a minimum height: the layout still centres itself
          // on a roomy screen, but at large text sizes it scrolls rather than
          // overflowing, because a Spacer cannot give ground. IntrinsicHeight
          // is what gives those Spacers a bounded height inside the scrollable.
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const Spacer(flex: 2),
                        // The cat sits on a soft disc, the way the
                        // reference rests its photo on a colour block.
                        Halo(
                              size: 230,
                              child: SleepingCat(size: 190),
                            )
                            .animate()
                            .fadeIn(duration: 500.ms)
                            .scale(
                              begin: const Offset(0.85, 0.85),
                              curve: Curves.easeOutBack,
                              duration: 600.ms,
                            ),
                        const SizedBox(height: 32),
                        Text(
                              'PawsLog',
                              style: theme.textTheme.displaySmall?.copyWith(
                                letterSpacing: -0.5,
                              ),
                            )
                            .animate(delay: 420.ms)
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.3, curve: Curves.easeOutCubic),
                        const SizedBox(height: 12),
                        Text(
                              'Keep track of your cat’s vaccines, deworming and '
                              'flea treatments — and get a nudge when something '
                              'is due.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            )
                            .animate(delay: 520.ms)
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.3, curve: Curves.easeOutCubic),
                        const Spacer(flex: 3),
                        PillButton(
                              label: 'Get started',
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (context) => const AddPetScreen(),
                                ),
                              ),
                            )
                            .animate(delay: 640.ms)
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.4, curve: Curves.easeOutCubic),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
