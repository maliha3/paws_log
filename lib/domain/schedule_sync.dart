/// Something that can bring scheduled notifications back in step with the
/// database.
///
/// Repositories depend on this rather than on the notification service, so
/// the data layer keeps pointing downwards and tests can pass a no-op.
abstract interface class ScheduleSync {
  Future<void> syncAll();
}

/// Does nothing. Used in tests and before the scheduler is wired up.
class NoopScheduleSync implements ScheduleSync {
  const NoopScheduleSync();

  @override
  Future<void> syncAll() async {}
}
