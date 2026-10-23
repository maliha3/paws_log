import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/models/pet.dart';
import 'vet_summary_pdf.dart';
import 'vet_summary_service.dart';

/// Builds the summary and hands it to the share sheet.
///
/// Kept apart from the builder so the PDF itself stays testable without a
/// share sheet or a documents directory in the way.
class VetSummarySharing {
  const VetSummarySharing(this._service, {this.pdf = const VetSummaryPdf()});

  final VetSummaryService _service;
  final VetSummaryPdf pdf;

  Future<void> shareFor(Pet pet, {DateTime? now}) async {
    final summary = await _service.gather(pet, now: now);
    final bytes = await pdf.build(summary);

    final stamp = DateFormat('yyyy-MM-dd').format(summary.generatedAt);
    final safeName = pet.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');

    // A temporary file: this is a copy on its way out, and keeping one per
    // share would pile up in the owner's storage for no reason.
    final directory = await getTemporaryDirectory();
    final file = File(
      p.join(directory.path, 'pawslog-$safeName-$stamp.pdf'),
    );
    await file.writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: '${pet.name} — care summary',
        title: '${pet.name} — care summary',
      ),
    );
  }
}
