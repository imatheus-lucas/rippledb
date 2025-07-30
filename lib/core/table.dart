import 'package:ripple/core/columns.dart';
import 'package:sqlite3/sqlite3.dart';

class RippleTable<T> {
  final String tableName;
  final Map<String, ColumnBuilder> columns;
  final T Function(Map<String, Object?>) fromMap;
  final Map<String, Object?> Function(T) toMap;
  final Database _db;

  RippleTable({
    required this.tableName,
    required this.columns,
    required this.fromMap,
    required this.toMap,
    required Database db,
  }) : _db = db {
    _createTable();
  }

  void insert(T row) {
    final map = toMap(row);
    final keys = map.keys.join(', ');
    final placeholders = List.filled(map.length, '?').join(', ');

    final stmt = _db.prepare(
      'INSERT INTO $tableName ($keys) VALUES ($placeholders);',
    );
    stmt.execute(map.values.toList());
    stmt.dispose();
  }

  List<T> select({String? where}) {
    final sql = where != null
        ? 'SELECT * FROM $tableName WHERE $where'
        : 'SELECT * FROM $tableName';

    final result = _db.select(sql);
    return result.map((row) {
      final rowMap = {for (final column in row.keys) column: row[column]};
      return fromMap(rowMap);
    }).toList();
  }

  void _createTable() {
    final columnDefs = columns.entries
        .map((e) {
          return '${e.key} ${e.value.buildType()}';
        })
        .join(', ');

    final sql = 'CREATE TABLE IF NOT EXISTS $tableName ($columnDefs);';
    _db.execute(sql);
  }
}
