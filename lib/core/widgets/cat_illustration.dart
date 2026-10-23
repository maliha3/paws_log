import 'package:flutter/material.dart';

/// A curled, sleeping cat.
///
/// Drawn rather than photographed, for the same reasons as the paw mark: it
/// is sharp at any size, takes the colours it is given, and adds nothing to
/// the download. Shipping stock photography of someone else's cat would also
/// be a licensing problem this app does not need.
class SleepingCat extends StatelessWidget {
  const SleepingCat({
    required this.size,
    this.color,
    this.accent,
    this.markings = true,
    super.key,
  });

  final double size;

  /// The base coat. Defaults to the theme's primary, which is already the
  /// golden tan a Bengal's coat sits on.
  final Color? color;

  /// Nose and the closed eyes.
  final Color? accent;

  /// Rosettes, forehead stripes and tail rings. Turn them off below about
  /// 60px, where they stop being markings and start being mud.
  final bool markings;

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
            markings: markings && size >= 60,
          ),
        ),
      ),
    );
  }
}

class _SleepingCatPainter extends CustomPainter {
  _SleepingCatPainter({
    required this.body,
    required this.accent,
    required this.markings,
  });

  final Color body;
  final Color accent;
  final bool markings;

  /// The dark brown a Bengal's rosettes and rings are, mixed from the coat
  /// so it stays in key whatever the base colour is.
  Color get _marking => Color.alphaBlend(const Color(0xC43A1E06), body);

  /// The pale belly and muzzle a Bengal carries.
  Color get _pale => Color.alphaBlend(const Color(0x88FFFFFF), body);

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
    final tail = Path()
      ..moveTo(w * 0.88, h * 0.56)
      ..cubicTo(w * 0.99, h * 0.88, w * 0.78, h * 0.99, w * 0.55, h * 0.93);
    canvas.drawPath(
      tail,
      Paint()
        ..color = shade.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.10
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );

    if (markings) {
      _rosettes(canvas, w, h);
      _tailRings(canvas, tail, h);
    }

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

    if (markings) {
      // Forehead stripes, the Bengal's other signature after the rosettes.
      final stripe = Paint()
        ..color = _marking
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.028
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      for (final x in const [0.255, 0.330, 0.405]) {
        canvas.drawLine(at(x, 0.335), at(x - 0.015, 0.265), stripe);
      }

      // A pale muzzle, so the face reads against the coat.
      canvas.drawOval(
        Rect.fromCenter(
          center: at(0.330, 0.605),
          width: w * 0.165,
          height: h * 0.115,
        ),
        Paint()
          ..color = _pale
          ..isAntiAlias = true,
      );
    }

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

  /// Rosettes across the flank, in a fixed scatter. Random spots would
  /// reshuffle on every repaint.
  void _rosettes(Canvas canvas, double w, double h) {
    const spots = [
      (x: 0.60, y: 0.50, r: 0.050, tilt: 0.3),
      (x: 0.74, y: 0.56, r: 0.044, tilt: -0.2),
      (x: 0.66, y: 0.68, r: 0.047, tilt: 0.1),
      (x: 0.82, y: 0.70, r: 0.038, tilt: 0.4),
      (x: 0.55, y: 0.74, r: 0.040, tilt: -0.3),
      (x: 0.74, y: 0.42, r: 0.034, tilt: 0.2),
    ];

    final paint = Paint()
      ..color = _marking
      ..isAntiAlias = true;

    for (final spot in spots) {
      canvas
        ..save()
        ..translate(spot.x * w, spot.y * h)
        ..rotate(spot.tilt)
        ..drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: spot.r * 2 * w,
            height: spot.r * 1.5 * w,
          ),
          paint,
        )
        ..restore();
    }
  }

  /// Bands across the tail, placed along the curve itself so they sit square
  /// to it rather than at some fixed angle.
  void _tailRings(Canvas canvas, Path tail, double h) {
    final paint = Paint()
      ..color = _marking
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.030
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (final metric in tail.computeMetrics()) {
      for (final fraction in const [0.18, 0.42, 0.66]) {
        final tangent = metric.getTangentForOffset(metric.length * fraction);
        if (tangent == null) {
          continue;
        }
        // Perpendicular to the tail's direction at this point.
        final across = Offset(-tangent.vector.dy, tangent.vector.dx) *
            (h * 0.045);
        canvas.drawLine(
          tangent.position - across,
          tangent.position + across,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SleepingCatPainter old) =>
      old.body != body || old.accent != accent || old.markings != markings;
}
