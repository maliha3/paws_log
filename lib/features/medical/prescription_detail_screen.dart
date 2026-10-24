import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/image_viewer_screen.dart';
import '../../data/providers.dart';
import '../../domain/models/medicine.dart';
import '../../domain/models/prescription.dart';
import '../medicines/medicine_edit_screen.dart';
import 'prescription_flow.dart';

/// Everything kept about one prescription.
///
/// Before this, a saved prescription was a dead end: tapping it opened the
/// page images and nothing else. The text that was read off it, the vet
/// details typed on review, and the courses it produced were all in the row
/// and unreachable — and an owner who chose "Save photos only" had no way
/// back to the fields short of scanning the page again.
class PrescriptionDetailScreen extends ConsumerWidget {
  const PrescriptionDetailScreen({
    required this.petId,
    required this.prescriptionId,
    super.key,
  });

  final String petId;
  final String prescriptionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final all = ref.watch(prescriptionsForPetProvider(petId));
    final prescription = all.hasValue
        ? all.requireValue
              .where((entry) => entry.id == prescriptionId)
              .firstOrNull
        : null;

    if (prescription == null) {
      // Deleted from here, or never there. Either way there is nothing to
      // show, and the owner should not be left staring at a blank page.
      if (all.hasValue) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            Navigator.of(context).maybePop();
          }
        });
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final medicines = ref.watch(
      medicinesFromPrescriptionProvider(prescription.id),
    );
    final courses = medicines.hasValue
        ? medicines.requireValue
        : const <Medicine>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat.yMMMd().format(prescription.date)),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Prescription options',
            onSelected: (action) async {
              if (action == 'delete') {
                await _confirmDelete(context, ref, prescription);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (prescription.imagePaths.isNotEmpty)
            _Pages(paths: prescription.imagePaths),
          const SizedBox(height: 20),
          _Details(prescription: prescription),
          const SizedBox(height: 24),
          Text('Medicines from this page', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (courses.isEmpty)
            Text(
              'None yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final medicine in courses)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.medication_outlined),
                  title: Text(medicine.name),
                  subtitle: Text(medicine.dosage ?? 'No dose recorded'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => MedicineEditScreen(
                        petId: petId,
                        medicine: medicine,
                      ),
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 20),
          FilledButton.tonalIcon(
            onPressed: () =>
                reviewAgain(context, ref, prescription: prescription),
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(
              prescription.wasRead
                  ? 'Check the details again'
                  : 'Read this page',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            prescription.wasRead
                ? 'Opens the review screen, where the vet details can be '
                      'changed and more medicines added. Nothing already on '
                      'the schedule is touched.'
                : 'Nothing has been read off these pages yet. This looks for '
                      'medicines on them; the pages are kept either way.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (prescription.wasRead) ...[
            const SizedBox(height: 24),
            _ExtractedText(text: prescription.extractedText!),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Prescription prescription,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this prescription?'),
        content: const Text(
          'The pages go with it. Any medicines it produced stay — your cat is '
          'still on them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(prescriptionRepositoryProvider).delete(prescription.id);
    }
  }
}

/// The pages, side by side, each opening the full-screen viewer.
class _Pages extends StatelessWidget {
  const _Pages({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (context, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) =>
                  ImageViewerScreen(paths: paths, initialPage: index),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: theme.colorScheme.surfaceContainerHigh,
              child: SizedBox(
                width: 120,
                child: Image.file(
                  File(paths[index]),
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, _) => Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
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

class _Details extends StatelessWidget {
  const _Details({required this.prescription});

  final Prescription prescription;

  @override
  Widget build(BuildContext context) {
    final pages = prescription.pageCount;
    final facts = <(String, String)>[
      ('Date', DateFormat.yMMMd().format(prescription.date)),
      if (prescription.vetName != null) ('Vet', prescription.vetName!),
      if (prescription.clinic != null) ('Clinic', prescription.clinic!),
      ('Pages', pages == 1 ? '1 page' : '$pages pages'),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final fact in facts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 12,
                  children: [
                    Text(
                      fact.$1,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(fact.$2),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What was read off the page, exactly as recognised.
///
/// Collapsed, because it is long, often wrong in places, and there only for
/// the moment someone wants to check what the app thought it saw.
class _ExtractedText extends StatelessWidget {
  const _ExtractedText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      leading: const Icon(Icons.text_snippet_outlined),
      title: const Text('What was read off the page'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            text,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}
