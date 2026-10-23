import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/providers.dart';
import '../../domain/models/vet_visit.dart';
import '../../services/photo_store.dart';

/// Records a vet visit, and doubles as its detail view.
class VisitEditScreen extends ConsumerStatefulWidget {
  const VisitEditScreen({required this.petId, this.visit, super.key});

  final String petId;
  final VetVisit? visit;

  @override
  ConsumerState<VisitEditScreen> createState() => _VisitEditScreenState();
}

class _VisitEditScreenState extends ConsumerState<VisitEditScreen> {
  late final TextEditingController _reason;
  late final TextEditingController _clinic;
  late final TextEditingController _vet;
  late final TextEditingController _notes;
  late DateTime _visitedOn;

  /// Photos chosen before the visit exists to attach them to.
  final List<String> _pendingAttachments = [];
  bool _showReasonError = false;

  bool get _isEditing => widget.visit != null;

  @override
  void initState() {
    super.initState();
    final visit = widget.visit;
    final today = DateTime.now();

    _reason = TextEditingController(text: visit?.reason ?? '');
    _clinic = TextEditingController(text: visit?.clinic ?? '');
    _vet = TextEditingController(text: visit?.vetName ?? '');
    _notes = TextEditingController(text: visit?.notes ?? '');
    _visitedOn =
        visit?.visitedOn ?? DateTime.utc(today.year, today.month, today.day);
  }

  @override
  void dispose() {
    _reason.dispose();
    _clinic.dispose();
    _vet.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_visitedOn.year, _visitedOn.month, _visitedOn.day),
      firstDate: DateTime(DateTime.now().year - 20),
      lastDate: DateTime.now(),
      helpText: 'Date of visit',
    );
    if (picked != null) {
      setState(
        () => _visitedOn = DateTime.utc(picked.year, picked.month, picked.day),
      );
    }
  }

  Future<void> _addPhotos() async {
    final paths = await ref
        .read(photoStoreProvider)
        .pickMany(folder: PhotoStore.visitAttachments);
    if (paths.isEmpty || !mounted) {
      return;
    }
    final visit = widget.visit;
    if (visit == null) {
      setState(() => _pendingAttachments.addAll(paths));
      return;
    }
    final repository = ref.read(vetVisitRepositoryProvider);
    for (final path in paths) {
      await repository.addAttachment(visit.id, path);
    }
  }

  Future<void> _save() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _showReasonError = true);
      return;
    }
    final repository = ref.read(vetVisitRepositoryProvider);

    if (_isEditing) {
      await repository.update(
        widget.visit!.copyWith(
          visitedOn: _visitedOn,
          reason: _reason.text.trim(),
          clinic: _clinic.text.trim(),
          vetName: _vet.text.trim(),
          notes: _notes.text.trim(),
        ),
      );
    } else {
      await repository.create(
        petId: widget.petId,
        visitedOn: _visitedOn,
        reason: _reason.text,
        clinic: _clinic.text,
        vetName: _vet.text,
        notes: _notes.text,
        attachmentPaths: _pendingAttachments,
      );
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visit = widget.visit;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Visit' : 'Add a visit'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Delete visit',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref.read(vetVisitRepositoryProvider).delete(visit!.id);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(DateFormat.yMMMMd().format(_visitedOn)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'What was it for',
                errorText: _showReasonError ? 'A reason is needed' : null,
              ),
              onChanged: (value) {
                if (_showReasonError && value.trim().isNotEmpty) {
                  setState(() => _showReasonError = false);
                }
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _clinic,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Clinic',
                hintText: 'Optional',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _vet,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Vet',
                hintText: 'Optional',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            _Attachments(
              visitId: visit?.id,
              pending: _pendingAttachments,
              onAdd: _addPhotos,
              onRemovePending: (path) =>
                  setState(() => _pendingAttachments.remove(path)),
            ),
            const SizedBox(height: 36),
            FilledButton(
              onPressed: _save,
              child: Text(_isEditing ? 'Save' : 'Add visit'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Attachments extends ConsumerWidget {
  const _Attachments({
    required this.visitId,
    required this.pending,
    required this.onAdd,
    required this.onRemovePending,
  });

  /// Null while the visit is still being written.
  final String? visitId;

  final List<String> pending;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemovePending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final id = visitId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Photos', style: theme.textTheme.titleMedium)),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (id == null)
          _Thumbnails(
            paths: pending,
            onRemove: onRemovePending,
          )
        else
          ref
              .watch(attachmentsForVisitProvider(id))
              .when(
                loading: () => const SizedBox.shrink(),
                error: (error, _) => Text('$error'),
                data: (attachments) => _Thumbnails(
                  paths: [for (final a in attachments) a.filePath],
                  onRemove: (path) async {
                    final match = attachments.firstWhere(
                      (a) => a.filePath == path,
                    );
                    await ref
                        .read(vetVisitRepositoryProvider)
                        .deleteAttachment(match.id);
                  },
                ),
              ),
      ],
    );
  }
}

class _Thumbnails extends StatelessWidget {
  const _Thumbnails({required this.paths, required this.onRemove});

  final List<String> paths;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) {
      return Text(
        'No photos attached.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final path in paths)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _Thumbnail(path: path),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: IconButton(
                  tooltip: 'Remove photo',
                  icon: const Icon(Icons.cancel, size: 20),
                  onPressed: () => onRemove(path),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    // A stored photo can go missing if the owner cleared app data, so a
    // placeholder has to work rather than an exception.
    if (!file.existsSync()) {
      return Container(
        width: 88,
        height: 88,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.broken_image_outlined),
      );
    }
    return Image.file(file, width: 88, height: 88, fit: BoxFit.cover);
  }
}
