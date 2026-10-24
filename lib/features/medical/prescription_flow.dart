import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/dose_schedule.dart';
import '../../domain/models/prescription.dart';
import '../../domain/prescriptions/prescription_parser.dart';
import 'prescription_review_screen.dart';

/// Where a prescription's pages come from.
enum PageSource { camera, photos }

/// Offers the two ways in. A sheet rather than two buttons: scanning is the
/// common case, but a page already photographed should not have to be
/// photographed again.
Future<void> showAddPrescriptionSheet(
  BuildContext context,
  WidgetRef ref, {
  required String petId,
}) => showModalBottomSheet<void>(
  context: context,
  builder: (sheet) => SafeArea(
    // Scrollable: at the largest text sizes two tiles and their subtitles are
    // taller than a sheet is allowed to be.
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (source, icon, title, subtitle) in [
            (
              PageSource.camera,
              Icons.document_scanner_outlined,
              'Scan the pages',
              'Uses the camera and crops the page for you',
            ),
            (
              PageSource.photos,
              Icons.photo_library_outlined,
              'Choose from Photos',
              'For a page you have already photographed',
            ),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(subtitle),
              onTap: () {
                Navigator.of(sheet).pop();
                addPrescription(context, ref, petId: petId, source: source);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  ),
);

/// Pages in, text read, review shown.
///
/// The prescription row is written as soon as the pages are on the device,
/// before anything is read and long before anything is confirmed. Backing out
/// of the review screen therefore keeps the page — which is the point. What
/// it never does is touch the schedule.
Future<void> addPrescription(
  BuildContext context,
  WidgetRef ref, {
  required String petId,
  required PageSource source,
}) async {
  final scanner = ref.read(scanServiceProvider);
  final pages = source == PageSource.camera
      ? await scanner.scanPages()
      : await scanner.pickPages();

  // Empty means the owner backed out of the camera or the picker.
  if (pages.isEmpty || !context.mounted) {
    return;
  }

  // Reading pages takes a moment, and a screen that does nothing for a
  // second reads as broken. The dialog owns the work and closes itself with
  // the result, so there is no guessing about which route to pop.
  final prescription = await showDialog<Prescription>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ReadingDialog(
      work: () async {
        final text = await _read(ref, pages);
        return ref
            .read(prescriptionRepositoryProvider)
            .create(
              petId: petId,
              date: localDateOnly(DateTime.now()),
              imagePaths: pages,
              extractedText: text.isEmpty ? null : text,
            );
      },
    ),
  );

  if (prescription == null || !context.mounted) {
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => PrescriptionReviewScreen(
        prescription: prescription,
        parsed: PrescriptionParser.parse(prescription.extractedText ?? ''),
      ),
    ),
  );
}

/// Reads a prescription that is already saved, and opens the review screen.
///
/// The way back from "Save photos only": an owner who kept the page and then
/// changed their mind has no other route to the fields, and re-scanning a
/// page they already have would be absurd.
///
/// Pages that were never read are read now; pages that were are parsed from
/// the text already stored, so this costs nothing the second time.
Future<void> reviewAgain(
  BuildContext context,
  WidgetRef ref, {
  required Prescription prescription,
}) async {
  var current = prescription;

  if (!current.wasRead && current.imagePaths.isNotEmpty) {
    final read = await showDialog<Prescription>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ReadingDialog(
        work: () async {
          final text = await _read(ref, current.imagePaths);
          final updated = current.copyWith(
            extractedText: text.isEmpty ? null : text,
          );
          await ref.read(prescriptionRepositoryProvider).update(updated);
          return updated;
        },
      ),
    );
    if (read == null || !context.mounted) {
      return;
    }
    current = read;
  }

  if (!context.mounted) {
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => PrescriptionReviewScreen(
        prescription: current,
        parsed: PrescriptionParser.parse(current.extractedText ?? ''),
      ),
    ),
  );
}

/// Every page's text, in page order, as one document.
Future<String> _read(WidgetRef ref, List<String> pages) async {
  final ocr = ref.read(ocrServiceProvider);
  final read = <String>[];
  for (final page in pages) {
    read.add(await ocr.recognise(page));
  }
  return read.where((text) => text.trim().isNotEmpty).join('\n');
}

/// Runs one piece of work and pops itself with the answer.
class _ReadingDialog<T> extends StatefulWidget {
  const _ReadingDialog({required this.work});

  final Future<T> Function() work;

  @override
  State<_ReadingDialog<T>> createState() => _ReadingDialogState<T>();
}

class _ReadingDialogState<T> extends State<_ReadingDialog<T>> {
  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final result = await widget.work();
    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) => const AlertDialog(
    content: Row(
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 16),
        Expanded(child: Text('Reading the page…')),
      ],
    ),
  );
}
