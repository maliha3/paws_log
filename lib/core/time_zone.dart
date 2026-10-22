import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Loads the timezone database and points `tz.local` at the device's zone.
///
/// Recurrence arithmetic and notification scheduling both run in `tz.local`,
/// so this has to happen before the first database read.
Future<void> initializeAppTimeZone() async {
  tz_data.initializeTimeZones();
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(info.identifier));
  } on Object catch (error) {
    // A device that reports a zone the database does not know would otherwise
    // take the app down on launch. UTC is wrong but harmless, and reminder
    // times stay self-consistent.
    debugPrint('Falling back to UTC: could not resolve the local zone ($error)');
  }
}
