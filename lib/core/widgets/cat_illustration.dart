import 'package:flutter/material.dart';

/// A Bengal's colouring.
///
/// Fixed rather than taken from the theme: a cat is the colour it is, and a
/// sandy coat reads on both a cream and a dark surface without going muddy
/// the way a brand-tinted one would.
@immutable
class CatColors {
  const CatColors({
    required this.coat,
    required this.pale,
    required this.marking,
    required this.nose,
    required this.ear,
  });

  /// Sandy tan — the base a Bengal's pattern sits on.
  static const CatColors bengal = CatColors(
    coat: Color(0xFFD9A86C),
    pale: Color(0xFFF5E6CC),
    marking: Color(0xFF4A3524),
    nose: Color(0xFFD1877F),
    ear: Color(0xFFE9BCA8),
  );

  final Color coat;

  /// Chest, belly, muzzle — a Bengal's underside is much lighter than its
  /// back, and that contrast is half of what makes it look like a Bengal.
  final Color pale;

  /// Rosettes, streaks, forehead stripes and tail rings.
  final Color marking;

  final Color nose;
  final Color ear;
}

/// A curled, sleeping Bengal.
///
/// Drawn rather than photographed: sharp at any size, nothing added to the
/// download, and no licence to honour. Shipping stock photography of someone
/// else's cat would be a problem this app does not need.
class SleepingCat extends StatelessWidget {
  const SleepingCat({
    required this.size,
    this.colors = CatColors.bengal,
    this.markings = true,
    super.key,
  });

  final double size;
  final CatColors colors;

  /// Rosettes, streaks and rings. Off below about 60px, where they stop
  /// being markings and start being mud.
  final bool markings;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    // Decorative: a screen reader has nothing useful to say about it.
    child: SizedBox(
      width: size,
      height: size * 0.72,
      child: CustomPaint(
        painter: _SleepingCatPainter(
          colors: colors,
          markings: markings && size >= 60,
        ),
      ),
    ),
  );
}

class _SleepingCatPainter extends CustomPainter {
  _SleepingCatPainter({required this.colors, required this.markings});

  final CatColors colors;
  final bool markings;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Offset at(double x, double y) => Offset(x * w, y * h);

    final coat = Paint()
      ..color = colors.coat
      ..isAntiAlias = true;
    final dark = Paint()
      ..color = colors.marking
      ..isAntiAlias = true;

    final bodyRect = Rect.fromCenter(
      center: at(0.57, 0.62),
      width: w * 0.74,
      height: h * 0.50,
    );
    final headCentre = at(0.33, 0.52);
    final headRadius = w * 0.21;

    _ears(canvas, w, h, coat);

    // The tail, outside the body so it is actually visible, with its rings.
    final tail = Path()
      ..moveTo(w * 0.88, h * 0.56)
      ..cubicTo(w * 0.99, h * 0.88, w * 0.78, h * 0.99, w * 0.55, h * 0.93);
    canvas.drawPath(
      tail,
      Paint()
        ..color = colors.coat
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.10
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
    if (markings) {
      _tailRings(canvas, tail, h);
    }

    canvas.drawOval(bodyRect, coat);

    // Everything on the body is clipped to it, so no marking can spill off
    // the silhouette however the geometry is tuned.
    canvas
      ..save()
      ..clipPath(Path()..addOval(bodyRect));
    // The pale belly, low and forward.
    canvas.drawOval(
      Rect.fromCenter(
        center: at(0.52, 0.80),
        width: w * 0.60,
        height: h * 0.26,
      ),
      Paint()
        ..color = colors.pale
        ..isAntiAlias = true,
    );
    if (markings) {
      _streaks(canvas, w, h);
      _rosettes(canvas, w, h);
    }
    canvas.restore();

    // A front paw tucked under the chin, in the pale of the underside.
    canvas.drawOval(
      Rect.fromCenter(
        center: at(0.44, 0.855),
        width: w * 0.19,
        height: h * 0.10,
      ),
      Paint()
        ..color = colors.pale
        ..isAntiAlias = true,
    );

    canvas.drawCircle(headCentre, headRadius, coat);

    canvas
      ..save()
      ..clipPath(
        Path()..addOval(
          Rect.fromCircle(center: headCentre, radius: headRadius),
        ),
      );
    _face(canvas, w, h, dark);
    canvas.restore();

    _whiskers(canvas, w, h);
  }

  void _ears(Canvas canvas, double w, double h, Paint coat) {
    const outer = [
      [(0.155, 0.41), (0.150, 0.06), (0.325, 0.30)],
      [(0.340, 0.30), (0.515, 0.06), (0.510, 0.41)],
    ];
    const inner = [
      [(0.195, 0.36), (0.182, 0.15), (0.300, 0.30)],
      [(0.365, 0.30), (0.482, 0.15), (0.470, 0.36)],
    ];

    Path triangle(List<(double, double)> points) => Path()
      ..moveTo(points[0].$1 * w, points[0].$2 * h)
      ..lineTo(points[1].$1 * w, points[1].$2 * h)
      ..lineTo(points[2].$1 * w, points[2].$2 * h)
      ..close();

    for (final ear in outer) {
      canvas.drawPath(triangle(ear), coat);
    }
    for (final ear in inner) {
      canvas.drawPath(
        triangle(ear),
        Paint()
          ..color = colors.ear
          ..isAntiAlias = true,
      );
    }
  }

  /// Elongated streaks over the shoulder, which is how a Bengal's pattern
  /// runs there — the round rosettes start further back along the flank.
  void _streaks(Canvas canvas, double w, double h) {
    // Thin and long. Short and fat, they merge into one dark mass rather
    // than reading as separate streaks.
    const streaks = [
      (x: 0.475, y: 0.49, len: 0.30, thick: 0.0115, tilt: 1.20),
      (x: 0.560, y: 0.44, len: 0.27, thick: 0.0110, tilt: 1.08),
      (x: 0.645, y: 0.41, len: 0.22, thick: 0.0100, tilt: 0.98),
    ];

    final paint = Paint()
      ..color = colors.marking
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (final streak in streaks) {
      paint.strokeWidth = streak.thick * 2 * w;
      final half = streak.len * h / 2;
      canvas
        ..save()
        ..translate(streak.x * w, streak.y * h)
        ..rotate(streak.tilt)
        ..drawLine(Offset(0, -half), Offset(0, half), paint)
        ..restore();
    }
  }

  /// Rosettes along the flank. A Bengal's are mostly *open* — a dark ring
  /// with coat showing through — rather than solid dots, which is the
  /// difference between a Bengal and a leopard-print cushion.
  void _rosettes(Canvas canvas, double w, double h) {
    // Kept clear of each other and of the silhouette's edge, where a clipped
    // rosette stops reading as a ring and becomes a smudge.
    const spots = [
      (x: 0.695, y: 0.545, r: 0.052, tilt: 0.3, open: true),
      (x: 0.825, y: 0.575, r: 0.046, tilt: -0.2, open: true),
      (x: 0.715, y: 0.705, r: 0.046, tilt: 0.1, open: true),
      (x: 0.845, y: 0.700, r: 0.032, tilt: 0.4, open: false),
      (x: 0.775, y: 0.455, r: 0.030, tilt: 0.2, open: false),
    ];

    final dark = Paint()
      ..color = colors.marking
      ..isAntiAlias = true;
    final hole = Paint()
      ..color = colors.coat
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
          dark,
        );
      if (spot.open) {
        // The coat showing through, pushed off-centre so the ring is heavier
        // on one side, the way a real rosette is.
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(spot.r * 0.22 * w, -spot.r * 0.18 * w),
            width: spot.r * 1.18 * w,
            height: spot.r * 0.82 * w,
          ),
          hole,
        );
      }
      canvas.restore();
    }
  }

  void _face(Canvas canvas, double w, double h, Paint dark) {
    Offset at(double x, double y) => Offset(x * w, y * h);

    // Fine forehead stripes, running back between the ears. Several thin
    // ones, not three fat ones.
    final stripe = Paint()
      ..color = colors.marking
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.016
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (final x in const [0.230, 0.280, 0.330, 0.380, 0.430]) {
      canvas.drawLine(at(x, 0.355), at(x - 0.012, 0.230), stripe);
    }

    // The pale muzzle and chin.
    canvas.drawOval(
      Rect.fromCenter(
        center: at(0.330, 0.620),
        width: w * 0.185,
        height: h * 0.130,
      ),
      Paint()
        ..color = colors.pale
        ..isAntiAlias = true,
    );

    // Mascara lines, from the outer eye down across the cheek.
    final mascara = Paint()
      ..color = colors.marking
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.018
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas
      ..drawLine(at(0.195, 0.495), at(0.165, 0.575), mascara)
      ..drawLine(at(0.465, 0.495), at(0.495, 0.575), mascara);

    // Closed eyes: asleep, not staring.
    final lid = Paint()
      ..color = colors.marking
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.030
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (final eye in const [0.245, 0.415]) {
      canvas.drawArc(
        Rect.fromCenter(
          center: at(eye, 0.470),
          width: w * 0.080,
          height: h * 0.065,
        ),
        0,
        3.14159,
        false,
        lid,
      );
    }

    // A pink nose, outlined.
    final nose = Path()
      ..moveTo(w * 0.303, h * 0.572)
      ..lineTo(w * 0.357, h * 0.572)
      ..lineTo(w * 0.330, h * 0.616)
      ..close();
    canvas
      ..drawPath(
        nose,
        Paint()
          ..color = colors.nose
          ..isAntiAlias = true,
      )
      ..drawPath(
        nose,
        Paint()
          ..color = colors.marking
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * 0.010
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      );
  }

  void _whiskers(Canvas canvas, double w, double h) {
    Offset at(double x, double y) => Offset(x * w, y * h);
    final paint = Paint()
      ..color = colors.marking.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.012
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (final whisker in const [
      [(0.21, 0.605), (0.07, 0.575)],
      [(0.21, 0.645), (0.08, 0.675)],
      [(0.45, 0.605), (0.59, 0.575)],
      [(0.45, 0.645), (0.58, 0.675)],
    ]) {
      canvas.drawLine(
        at(whisker[0].$1, whisker[0].$2),
        at(whisker[1].$1, whisker[1].$2),
        paint,
      );
    }
  }

  /// Bands across the tail, placed along the curve itself so each sits square
  /// to it, and a dark tip.
  void _tailRings(Canvas canvas, Path tail, double h) {
    final paint = Paint()
      ..color = colors.marking
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (final metric in tail.computeMetrics()) {
      for (final band in const [
        (at: 0.20, width: 0.026),
        (at: 0.44, width: 0.028),
        (at: 0.68, width: 0.030),
        (at: 0.94, width: 0.055),
      ]) {
        final tangent = metric.getTangentForOffset(metric.length * band.at);
        if (tangent == null) {
          continue;
        }
        paint.strokeWidth = h * band.width;
        final across =
            Offset(-tangent.vector.dy, tangent.vector.dx) * (h * 0.045);
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
      old.colors != colors || old.markings != markings;
}
