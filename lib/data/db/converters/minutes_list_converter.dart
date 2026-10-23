import 'package:drift/drift.dart';

/// Stores a medicine's dosing times as a comma-separated list of minutes.
///
/// A handful of small ints per row; a child table would cost a join on every
/// read for no gain, and JSON would be heavier to read in a query.
class MinutesListConverter extends TypeConverter<List<int>, String> {
  const MinutesListConverter();

  @override
  List<int> fromSql(String fromDb) => fromDb.isEmpty
      ? const []
      : fromDb.split(',').map(int.parse).toList();

  @override
  String toSql(List<int> value) => value.join(',');
}
