/// Notification ids are derived from the event id rather than handed out in
/// sequence, so cancelling and rescheduling the same occurrence is
/// idempotent across launches.
library;

/// A stable, positive 31-bit id for [eventId].
///
/// Both platforms take a 32-bit signed int, so the hash is masked rather than
/// allowed to wrap negative.
int notificationIdFor(String eventId) {
  var hash = 0;
  for (final unit in eventId.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash;
}
