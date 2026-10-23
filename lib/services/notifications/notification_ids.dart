/// Notification ids are derived from the payload rather than handed out in
/// sequence, so cancelling and rescheduling the same occurrence is
/// idempotent across launches.
library;

/// A stable, positive 31-bit id for [payload].
///
/// Both platforms take a 32-bit signed int, so the hash is masked rather than
/// allowed to wrap negative. The payload is hashed rather than the bare row
/// id so a reminder occurrence and a dose can never collide.
int notificationIdFor(String payload) {
  var hash = 0;
  for (final unit in payload.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash;
}
