import 'package:flutter/material.dart';

/// A curled, sleeping cat.
///
/// Drawn rather than photographed, for the same reasons as the paw mark: it
/// is sharp at any size, takes the colours it is given, and adds nothing to
/// the download. Shipping stock photography of someone else's cat would also
/// be a licensing problem this app does not need.
class SleepingCat extends StatelessWidget {
  const SleepingCat({required this.size, this.color, this.accent, super.key});

  final double size;

  /// The cat's body. Defaults to a soft step of the theme's primary.
  final Color? color;

  /// Ears, nose and the closed eyes.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Opaque: the shapes overlap, and a translucent fill shows every seam
    // where they do.
    final body = color ?? scheme.primary;

    // Decorative: a screen reader has nothing useful to say about it.
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size * 0.72,
        child: CustomPaint(
          painter: _SleepingCatPainter(
            body: body,
            accent: accent ?? scheme.onPrimary,
          ),
        ),
      ),
    );
  }
}

class _SleepingCatPainter extends CustomPainter {
  _SleepingCatPainter({required this.body, required this.accent});

  final Color body;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Offset at(double x, double y) => Offset(x * w, y * h);

    final fill = Paint()
      ..color = body
      ..isAntiAlias = true;

    // A darker step of the body, so the tail and the tucked paw read as
    // separate limbs rather than vanishing into the silhouette.
    final shade = Paint()
      ..color = Color.alphaBlend(const Color(0x22000000), body)
      ..isAntiAlias = true;

    final line = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Ears first, so the head lands on top and hides where they join.
    for (final ear in const [
      [(0.155, 0.41), (0.150, 0.06), (0.325, 0.30)],
      [(0.340, 0.30), (0.515, 0.06), (0.510, 0.41)],
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(ear[0].$1 * w, ear[0].$2 * h)
          ..lineTo(ear[1].$1 * w, ear[1].$2 * h)
          ..lineTo(ear[2].$1 * w, ear[2].$2 * h)
          ..close(),
        fill,
      );
    }

    // The body: a long curled back.
    canvas.drawOval(
      Rect.fromCenter(
        center: at(0.57, 0.62),
        width: w * 0.74,
        height: h * 0.50,
      ),
      fill,
    );

    // The tail, sweeping out past the back and curling round the front. Drawn
    // over the body in the darker step, or it would not be there at all.
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.88, h * 0.56)
        ..cubicTo(w * 0.99, h * 0.88, w * 0.78, h * 0.99, w * 0.55, h * 0.93),
      Paint()
        ..color = shade.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.10
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );

    // A front paw tucked under the chin.
    canvas.drawOval(
      Rect.fromCenter(
        center: at(0.44, 0.855),
        width: w * 0.19,
        height: h * 0.10,
      ),
      shade,
    );

    // The head, resting on the body.
    canvas.drawCircle(at(0.33, 0.52), w * 0.21, fill);

    // Closed eyes: two small downward arcs. Asleep, not staring.
    line.strokeWidth = h * 0.032;
    for (final eye in const [0.245, 0.415]) {
      canvas.drawArc(
        Rect.fromCenter(
          center: at(eye, 0.47),
          width: w * 0.08,
          height: h * 0.065,
        ),
        0,
        3.14159,
        false,
        line,
      );
    }

    // Nose.
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.305, h * 0.575)
        ..lineTo(w * 0.355, h * 0.575)
        ..lineTo(w * 0.330, h * 0.615)
        ..close(),
      Paint()
        ..color = accent
        ..isAntiAlias = true,
    );

    // Whiskers.
    line.strokeWidth = h * 0.016;
    for (final whisker in const [
      [(0.20, 0.60), (0.07, 0.57)],
      [(0.20, 0.64), (0.08, 0.67)],
      [(0.46, 0.60), (0.59, 0.57)],
      [(0.46, 0.64), (0.58, 0.67)],
    ]) {
      canvas.drawLine(
        at(whisker[0].$1, whisker[0].$2),
        at(whisker[1].$1, whisker[1].$2),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(_SleepingCatPainter old) =>
      old.body != body || old.accent != accent;
}
