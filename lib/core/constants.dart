/// App-wide constants.
///
/// Values that the product rules in CLAUDE.md pin down live here so there is
/// one place to change them.
abstract final class AppConstants {
  /// Name of the sqlite file, as passed to `driftDatabase`.
  static const String databaseName = 'paws_log';

  /// iOS silently drops pending local notifications past 64, so the scheduler
  /// keeps a rolling window well inside that cap.
  static const int iosPendingNotificationLimit = 64;

  /// How many of the 64 slots hold scheduled occurrences.
  static const int scheduledNotificationBudget = 56;

  /// Slots held back for snoozes fired at runtime.
  static const int snoozeNotificationReserve =
      iosPendingNotificationLimit - scheduledNotificationBudget;

  /// Default time of day for a new reminder: 09:00, in minutes past midnight.
  static const int defaultReminderTimeMinutes = 9 * 60;

  /// How far ahead doses are generated for an open-ended course. A course
  /// with an end date gets its whole run generated instead.
  static const int doseHorizonDays = 14;

  /// Shown on every screen that proposes a care schedule.
  static const String vetDisclaimer = 'Confirm the schedule with your vet.';
}
