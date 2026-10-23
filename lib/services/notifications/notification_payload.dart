/// What a scheduled notification refers to.
enum NotificationKind {
  reminder,
  dose;

  static const String _separator = ':';

  /// Encodes [id] so the handler knows which table to act on.
  String payloadFor(String id) => '$name$_separator$id';

  /// Reads a payload written by [payloadFor].
  ///
  /// A payload with no prefix is treated as a reminder event: notifications
  /// scheduled by a build from before doses existed are still out there, and
  /// acting on one must not silently do nothing. (They are cancelled on the
  /// first sync after upgrading, so this only covers the gap.)
  static ({NotificationKind kind, String id})? decode(String? payload) {
    if (payload == null || payload.isEmpty) {
      return null;
    }
    final separator = payload.indexOf(_separator);
    if (separator < 0) {
      return (kind: NotificationKind.reminder, id: payload);
    }
    final prefix = payload.substring(0, separator);
    final id = payload.substring(separator + 1);
    if (id.isEmpty) {
      return null;
    }
    for (final kind in NotificationKind.values) {
      if (kind.name == prefix) {
        return (kind: kind, id: id);
      }
    }
    return null;
  }
}

/// One thing the scheduler may hand to the OS.
///
/// Reminder occurrences and medicine doses both reduce to this, which is what
/// lets them compete for the same 64 slots in one time-ordered window.
class PendingNotification {
  const PendingNotification({
    required this.id,
    required this.kind,
    required this.fireAt,
    required this.title,
    required this.body,
  });

  final String id;
  final NotificationKind kind;

  /// UTC.
  final DateTime fireAt;

  final String title;
  final String body;

  String get payload => kind.payloadFor(id);
}
