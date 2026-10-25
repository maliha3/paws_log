import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../services/backup/backup_service.dart';

/// Export and import the whole record.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  bool _includeAlbum = true;
  BackupSizes? _sizes;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  /// Reads the sizes off disk so the toggle can say what it costs.
  Future<void> _measure() async {
    final sizes = await ref.read(backupSharingProvider).estimateSize();
    if (mounted) {
      setState(() => _sizes = sizes);
    }
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await action();
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } on BackupFormatException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Something went wrong: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _export() => _run(() async {
    await ref
        .read(backupSharingProvider)
        .exportAndShare(includeAlbum: _includeAlbum);
    return null;
  });

  Future<void> _import() async {
    // Restoring is destructive and cannot be undone, so it is confirmed in
    // the app rather than relying on the file picker as a speed bump.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from a backup?'),
        content: const Text(
          'Everything currently in Paws Log will be replaced by what is in '
          'the backup file. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Replace everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _run(() async {
      final summary = await ref.read(backupSharingProvider).pickAndImport();
      return summary == null ? null : 'Restored ${summary.describe()}.';
    });
  }

  /// What leaving the album out would save.
  String get _albumNote {
    final sizes = _sizes;
    if (sizes == null) {
      return 'Album photos make a backup much larger.';
    }
    if (sizes.album == 0) {
      return 'There are no album photos yet.';
    }
    return 'The albums add about '
        '${BackupSizes.describeBytes(sizes.album)}. Leave this off for a '
        'small file that still holds every record.';
  }

  /// Roughly how big the file will be with the current choice.
  String get _sizeNote {
    final sizes = _sizes;
    if (sizes == null) {
      return 'Working out the size\u2026';
    }
    final bytes = _includeAlbum ? sizes.total : sizes.records;
    return 'About ${BackupSizes.describeBytes(bytes)} of photos, plus the '
        'records themselves.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            Text(
              'A backup holds every pet, reminder, medicine, visit, weighing '
              'and photo, in one file you can keep wherever you like.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Paws Log keeps everything on this device and nowhere else, so a '
              'backup is the only way to move to a new phone.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Card(
              margin: EdgeInsets.zero,
              child: SwitchListTile(
                value: _includeAlbum,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _includeAlbum = value),
                title: const Text('Include photo vault'),
                subtitle: Text(_albumNote),
                isThreeLine: true,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _sizeNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.ios_share),
              label: const Text('Export a backup'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Restore from a backup'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Restoring replaces everything currently in the app.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 32),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
