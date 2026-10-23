import 'package:flutter/material.dart';

/// A quiet wash of brand colour behind a screen.
///
/// Two very soft blooms rather than a flat fill: enough to stop a screen
/// reading as white paper, faint enough that text on top of it keeps its
/// contrast.
class SoftBackdrop extends StatelessWidget {
  const SoftBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final strength = isLight ? 0.30 : 0.18;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              scheme.primary.withValues(alpha: strength * 0.5),
              scheme.surface,
            ),
            scheme.surface,
            Color.alphaBlend(
              scheme.tertiary.withValues(alpha: strength * 0.35),
              scheme.surface,
            ),
          ],
          stops: const [0, 0.55, 1],
        ),
      ),
      child: child,
    );
  }
}

/// A soft disc behind a mark, so it sits on something rather than floating.
class Halo extends StatelessWidget {
  const Halo({required this.size, required this.child, super.key});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.18),
            scheme.primary.withValues(alpha: 0.04),
          ],
        ),
      ),
      child: child,
    );
  }
}
