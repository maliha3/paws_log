import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants.dart';
import '../../domain/models/medicine.dart';
import '../../core/money.dart';
import '../../domain/models/pet.dart';
import '../../domain/models/vet_summary.dart';
import '../../domain/models/weight_entry.dart';

/// Lays the vet summary out as a PDF.
///
/// A pure function of its input: no repositories, no plugins, no clock. That
/// is what lets the layout be exercised in a plain test.
class VetSummaryPdf {
  const VetSummaryPdf();

  static final DateFormat _date = DateFormat.yMMMd();

  static const PdfColor _ink = PdfColors.blueGrey900;
  static const PdfColor _muted = PdfColors.blueGrey600;
  static const PdfColor _rule = PdfColors.blueGrey200;

  Future<Uint8List> build(VetSummary summary) async {
    final document = pw.Document(
      title: 'Paws Log summary — ${summary.pet.name}',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 48),
        footer: (context) => _footer(context, summary),
        build: (context) => [
          _header(summary),
          pw.SizedBox(height: 18),
          _profile(summary.pet),
          // Allergies first, before the vaccination table, because a vet who
          // has not met this cat needs them before anything else on the page.
          if (summary.allergies.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            _allergies(summary),
          ],
          pw.SizedBox(height: 20),
          _section('Conditions', _conditions(summary)),
          pw.SizedBox(height: 18),
          _section('Vaccinations', _vaccinations(summary)),
          pw.SizedBox(height: 18),
          _section('Current medicines', _medicines(summary)),
          pw.SizedBox(height: 18),
          _section('Weight', _weight(summary)),
          pw.SizedBox(height: 18),
          _section('Recent visits', _visits(summary)),
        ],
      ),
    );

    return document.save();
  }

  pw.Widget _header(VetSummary summary) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        summary.pet.name,
        style: pw.TextStyle(
          fontSize: 26,
          fontWeight: pw.FontWeight.bold,
          color: _ink,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        'Care summary · ${_date.format(summary.generatedAt)}',
        style: const pw.TextStyle(fontSize: 11, color: _muted),
      ),
      pw.SizedBox(height: 10),
      pw.Divider(color: _rule, thickness: 1),
    ],
  );

  pw.Widget _profile(Pet pet) {
    final facts = <(String, String)>[
      if (pet.species != null) ('Species', pet.species!),
      if (pet.breed != null) ('Breed', pet.breed!),
      if (pet.sex != PetSex.unknown)
        ('Sex', pet.sex == PetSex.female ? 'Female' : 'Male'),
      (
        'Neutered',
        switch (pet.neutered) {
          true => 'Yes',
          false => 'No',
          null => 'Not recorded',
        },
      ),
      if (pet.birthday != null) ('Date of birth', _date.format(pet.birthday!)),
      // The number a vet would scan for, which is exactly the sort of thing
      // nobody has to hand at the counter.
      if (pet.microchip != null) ('Microchip', pet.microchip!),
    ];

    return pw.Wrap(
      spacing: 28,
      runSpacing: 8,
      children: [
        for (final fact in facts)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                fact.$1.toUpperCase(),
                style: const pw.TextStyle(fontSize: 8, color: _muted),
              ),
              pw.Text(
                fact.$2,
                style: pw.TextStyle(
                  fontSize: 12,
                  color: _ink,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _section(String title, pw.Widget body) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
          color: _ink,
        ),
      ),
      pw.SizedBox(height: 6),
      body,
    ],
  );

  pw.Widget _empty(String message) =>
      pw.Text(message, style: const pw.TextStyle(fontSize: 11, color: _muted));

  /// Boxed rather than tabled: this is a warning, not a list of records.
  pw.Widget _allergies(VetSummary summary) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _ink, width: 0.8),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          summary.allergies.length == 1 ? 'ALLERGY' : 'ALLERGIES',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
        pw.SizedBox(height: 4),
        for (final allergy in summary.allergies)
          pw.Text(
            allergy.reaction == null
                ? allergy.allergen
                : '${allergy.allergen} \u2014 ${allergy.reaction}',
            style: const pw.TextStyle(fontSize: 11, color: _ink),
          ),
      ],
    ),
  );

  pw.Widget _conditions(VetSummary summary) {
    if (summary.conditions.isEmpty) {
      return _empty('None recorded.');
    }
    return _table(
      ['Condition', 'Status', 'Diagnosed', 'Notes'],
      [
        for (final condition in [
          ...summary.ongoingConditions,
          ...summary.pastConditions,
        ])
          [
            condition.name,
            condition.status.label,
            condition.date == null ? '\u2014' : _date.format(condition.date!),
            condition.notes ?? '\u2014',
          ],
      ],
    );
  }

  pw.Widget _vaccinations(VetSummary summary) {
    if (summary.vaccinations.isEmpty) {
      return _empty('None recorded.');
    }
    return _table(
      ['Vaccine', 'Given', 'Next due'],
      [
        for (final record in summary.vaccinations)
          [
            record.name,
            _date.format(record.administeredOn),
            record.nextDueOn == null ? '—' : _date.format(record.nextDueOn!),
          ],
      ],
    );
  }

  pw.Widget _medicines(VetSummary summary) {
    if (summary.medicines.isEmpty) {
      return _empty('None.');
    }
    return _table(
      ['Medicine', 'Dose', 'When', 'Course'],
      [
        for (final medicine in summary.medicines)
          [
            medicine.name,
            medicine.dosage ?? '—',
            _times(medicine),
            medicine.schedule.isOpenEnded
                ? 'From ${_date.format(medicine.schedule.startDate)}, ongoing'
                : '${_date.format(medicine.schedule.startDate)} – '
                      '${_date.format(medicine.schedule.endDate!)}',
          ],
      ],
    );
  }

  String _times(Medicine medicine) {
    final schedule = medicine.schedule;
    final times = schedule.timesOfDayMinutes
        .map(
          (minutes) =>
              '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
              '${(minutes % 60).toString().padLeft(2, '0')}',
        )
        .join(', ');
    return schedule.intervalDays == 1
        ? times
        : '$times, every ${schedule.intervalDays} days';
  }

  pw.Widget _weight(VetSummary summary) {
    final latest = summary.latestWeight;
    if (latest == null) {
      return _empty('None recorded.');
    }
    final unit = summary.unit;
    final change = summary.weightChange;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              '${unit.format(latest.grams)} ${unit.label}',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: _ink,
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Text(
              change == null
                  ? 'on ${_date.format(latest.measuredOn)}'
                  : '${_signed(change, unit)} across '
                        '${summary.weights.length} weighings '
                        'since ${_date.format(summary.weights.first.measuredOn)}',
              style: const pw.TextStyle(fontSize: 10, color: _muted),
            ),
          ],
        ),
        if (summary.weights.length >= 2) ...[
          pw.SizedBox(height: 10),
          pw.SizedBox(height: 110, child: _weightChart(summary)),
        ],
      ],
    );
  }

  pw.Widget _weightChart(VetSummary summary) {
    final unit = summary.unit;
    final values = [
      for (final entry in summary.weights) unit.fromGrams(entry.grams),
    ];
    final lowest = values.reduce((a, b) => a < b ? a : b);
    final highest = values.reduce((a, b) => a > b ? a : b);
    final padding = highest == lowest ? 0.5 : (highest - lowest) * 0.25;

    return pw.Chart(
      grid: pw.CartesianGrid(
        xAxis: pw.FixedAxis(
          [for (var i = 0; i < values.length; i++) i],
          format: (value) => _date.format(
            summary.weights[value.toInt()].measuredOn,
          ),
          // Only the ends are labelled; a vet reads the shape, not every date.
          divisions: false,
          textStyle: const pw.TextStyle(fontSize: 7, color: _muted),
          marginStart: 4,
        ),
        yAxis: pw.FixedAxis(
          [
            (lowest - padding).toFloor(),
            ((lowest + highest) / 2).toRounded(),
            (highest + padding).toCeil(),
          ],
          format: (value) => value.toStringAsFixed(1),
          divisions: true,
          divisionsColor: _rule,
          textStyle: const pw.TextStyle(fontSize: 7, color: _muted),
        ),
      ),
      datasets: [
        pw.LineDataSet(
          drawSurface: true,
          isCurved: false,
          color: PdfColors.teal700,
          pointSize: 2.5,
          lineWidth: 1.5,
          data: [
            for (var i = 0; i < values.length; i++)
              pw.PointChartValue(i.toDouble(), values[i]),
          ],
        ),
      ],
    );
  }

  pw.Widget _visits(VetSummary summary) {
    if (summary.visits.isEmpty) {
      return _empty('None recorded.');
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final visit in summary.visits) ...[
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 80,
                child: pw.Text(
                  _date.format(visit.visitedOn),
                  style: const pw.TextStyle(fontSize: 10, color: _muted),
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      visit.reason,
                      style: pw.TextStyle(
                        fontSize: 11,
                        color: _ink,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (visit.clinic != null ||
                        visit.vetName != null ||
                        visit.cost != null)
                      pw.Text(
                        [
                          if (visit.clinic != null) visit.clinic!,
                          if (visit.vetName != null) visit.vetName!,
                          if (visit.cost != null) Money.format(visit.cost!),
                        ].join(' · '),
                        style: const pw.TextStyle(fontSize: 9, color: _muted),
                      ),
                    if (visit.notes != null)
                      pw.Text(
                        visit.notes!,
                        style: const pw.TextStyle(fontSize: 10, color: _ink),
                      ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
        ],
      ],
    );
  }

  pw.Widget _table(List<String> headings, List<List<String>> rows) =>
      pw.TableHelper.fromTextArray(
        headers: headings,
        data: rows,
        border: null,
        headerStyle: const pw.TextStyle(fontSize: 8, color: _muted),
        headerDecoration: const pw.BoxDecoration(),
        cellStyle: const pw.TextStyle(fontSize: 10, color: _ink),
        cellAlignment: pw.Alignment.centerLeft,
        cellPadding: const pw.EdgeInsets.symmetric(vertical: 3),
        headerAlignment: pw.Alignment.centerLeft,
      );

  pw.Widget _footer(pw.Context context, VetSummary summary) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Divider(color: _rule, thickness: 0.5),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              // The same standing note the app carries: this is a record of
              // what the owner entered, not a clinical document.
              'Recorded by the owner in Paws Log. '
              '${AppConstants.vetDisclaimer}',
              style: const pw.TextStyle(fontSize: 8, color: _muted),
            ),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ],
      ),
    ],
  );

  String _signed(double change, WeightUnit unit) {
    if (change.abs() < 0.005) {
      return 'no change';
    }
    final size = change.abs().toStringAsFixed(
      unit == WeightUnit.kilograms ? 2 : 1,
    );
    return '${change > 0 ? '+' : '-'}$size ${unit.label}';
  }
}

extension on double {
  double toFloor() => (this * 10).floorToDouble() / 10;
  double toCeil() => (this * 10).ceilToDouble() / 10;
  double toRounded() => (this * 10).roundToDouble() / 10;
}
