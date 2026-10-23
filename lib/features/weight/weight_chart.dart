import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models/weight_entry.dart';

/// Weight over time.
///
/// One series, so there is no legend — the section heading names it — and no
/// number is printed on every point; the axis labels and the touch tooltip
/// carry the values. Grid and axes stay recessive so the line reads first.
class WeightChart extends StatelessWidget {
  const WeightChart({required this.entries, required this.unit, super.key});

  /// Oldest first.
  final List<WeightEntry> entries;

  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final spots = [
      for (var index = 0; index < entries.length; index++)
        FlSpot(
          entries[index].measuredOn.millisecondsSinceEpoch.toDouble(),
          unit.fromGrams(entries[index].grams),
        ),
    ];

    final values = spots.map((spot) => spot.y);
    final lowest = values.reduce((a, b) => a < b ? a : b);
    final highest = values.reduce((a, b) => a > b ? a : b);
    // A flat series would otherwise collapse to a zero-height band.
    final padding = (highest - lowest) == 0 ? 0.5 : (highest - lowest) * 0.2;

    return LineChart(
      LineChartData(
        minY: lowest - padding,
        maxY: highest + padding,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: scheme.primary,
            barWidth: 2,
            isCurved: false,
            isStrokeCapRound: true,
            dotData: FlDotData(
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(
                    radius: 4,
                    color: scheme.primary,
                    // A ring in the surface colour keeps touching dots apart.
                    strokeWidth: 2,
                    strokeColor: scheme.surface,
                  ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: scheme.primary.withValues(alpha: 0.10),
            ),
          ),
        ],
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  value.toStringAsFixed(1),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              // Only the ends, so labels cannot collide on a narrow phone.
              interval: _bottomInterval(spots),
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  DateFormat.MMMd().format(
                    DateTime.fromMillisecondsSinceEpoch(
                      value.toInt(),
                      isUtc: true,
                    ),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (spot) => scheme.inverseSurface,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  '${spot.y.toStringAsFixed(unit == WeightUnit.kilograms ? 2 : 1)}'
                  ' ${unit.label}\\n'
                  '${DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(spot.x.toInt(), isUtc: true))}',
                  TextStyle(
                    color: scheme.onInverseSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Enough spacing that only a handful of date labels are drawn.
  static double? _bottomInterval(List<FlSpot> spots) {
    if (spots.length < 2) {
      return null;
    }
    final span = spots.last.x - spots.first.x;
    return span <= 0 ? null : span / 2;
  }
}
