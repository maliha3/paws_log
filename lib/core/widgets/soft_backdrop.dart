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
      child: CustomPaint(
        painter: _PawPrints(
          color: scheme.primary.withValues(alpha: isLight ? 0.09 : 0.07),
        ),
        child: child,
      ),
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


/// A scatter of faint paw prints, like the one tucked behind the headline in
/// a good pet app's opening screen.
///
/// Fixed positions rather than random: a layout that reshuffles every rebuild
/// is distracting, and a pattern nobody can predict is not a pattern.
class _PawPrints extends CustomPainter {
  _PawPrints({required this.color});

  final Color color;

  /// Fractions of the canvas, with a size and a lean for each print.
  static const _prints = [
    (x: 0.84, y: 0.10, size: 0.16, tilt: 0.35),
    (x: 0.12, y: 0.22, size: 0.10, tilt: -0.5),
    (x: 0.90, y: 0.46, size: 0.09, tilt: 0.1),
    (x: 0.07, y: 0.62, size: 0.13, tilt: 0.6),
    (x: 0.78, y: 0.78, size: 0.11, tilt: -0.3),
    (x: 0.30, y: 0.90, size: 0.08, tilt: 0.2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;

    for (final print in _prints) {
      final side = size.width * print.size;
      canvas
        ..save()
        ..translate(print.x * size.width, print.y * size.height)
        ..rotate(print.tilt)
        ..translate(-side / 2, -side / 2);
      _paw(canvas, side, paint);
      canvas.restore();
    }
  }

  /// The same paw as the app's mark, at pattern scale.
  void _paw(Canvas canvas, double side, Paint paint) {
    void oval(double cx, double cy, double rx, double ry, double rot) {
      canvas
        ..save()
        ..translate(cx * side, cy * side)
        ..rotate(rot)
        ..drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: rx * 2 * side,
            height: ry * 2 * side,
          ),
          paint,
        )
        ..restore();
    }

    oval(0.50, 0.70, 0.235, 0.185, 0);
    oval(0.215, 0.395, 0.082, 0.108, -0.46);
    oval(0.405, 0.275, 0.084, 0.118, -0.16);
    oval(0.595, 0.275, 0.084, 0.118, 0.16);
    oval(0.785, 0.395, 0.082, 0.108, 0.46);
  }

  @override
  bool shouldRepaint(_PawPrints old) => old.color != color;
}

