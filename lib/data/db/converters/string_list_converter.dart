import 'dart:convert';

import 'package:drift/drift.dart';

/// Stores an ordered list of strings as a JSON array.
///
/// Used for a prescription's page images, where the order *is* data: page 2
/// of a prescription is not interchangeable with page 1.
class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) {
    if (fromDb.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(fromDb);
    return decoded is List ? decoded.cast<String>() : const [];
  }

  @override
  String toSql(List<String> value) => jsonEncode(value);
}
