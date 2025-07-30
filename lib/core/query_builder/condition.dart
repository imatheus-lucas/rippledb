import 'package:rippledb/core/query_builder/query_builder.dart';

Condition and(List<Condition> conditions) {
  final clauses = conditions.map((c) => c.clause).join(" AND ");
  final values = conditions.expand((c) => c.values).toList();
  return Condition("($clauses)", values);
}

Condition between(String column, dynamic start, dynamic end) {
  return Condition("$column BETWEEN ? AND ?", [start, end]);
}

String count(String columnName, {bool distinct = false}) {
  if (!distinct) {
    return "COUNT($columnName)";
  } else {
    return "COUNT(DISTINCT $columnName)";
  }
}

Condition eq(String left, dynamic right) {
  final isRightColumn =
      right is String && RegExp(r'^\w+\.\w+$').hasMatch(right);

  final leftExpr = _escapeIdentifier(left);
  final rightExpr = isRightColumn
      ? _escapeIdentifier(right)
      : _escapeValue(right);

  return Condition('$leftExpr = $rightExpr');
}

Condition exists(QueryBuilder subquery) {
  String sql = subquery.toSql().trim();
  if (sql.endsWith(';')) sql = sql.substring(0, sql.length - 1);
  return Condition("EXISTS ($sql)");
}

Condition gt(String column, dynamic value) {
  return Condition("$column > ?", [value]);
}

Condition gte(String column, dynamic value) {
  return Condition("$column >= ?", [value]);
}

Condition ilike(String column, String pattern) {
  return Condition("$column ILIKE ?", [pattern]);
}

Condition inArray(String column, List<dynamic> values) {
  final placeholders = List.filled(values.length, '?').join(', ');
  return Condition("$column IN ($placeholders)", values);
}

Condition isNotNull(String column) => Condition("$column IS NOT NULL");

Condition isNull(String column) => Condition("$column IS NULL");

Condition like(String column, String pattern) {
  return Condition("$column LIKE ?", [pattern]);
}

Condition lt(String column, dynamic value) {
  return Condition("$column < ?", [value]);
}

Condition lte(String column, dynamic value) {
  return Condition("$column <= ?", [value]);
}

Condition ne(String column, dynamic value) {
  if (value is String && value.contains('.')) {
    return Condition("$column <> $value");
  }
  return Condition("$column <> ?", [value]);
}

Condition not(Condition condition) {
  return Condition("NOT (${condition.clause})", condition.values);
}

Condition notBetween(String column, dynamic start, dynamic end) {
  return Condition("$column NOT BETWEEN ? AND ?", [start, end]);
}

Condition notExists(QueryBuilder subquery) {
  String sql = subquery.toSql().trim();
  if (sql.endsWith(';')) sql = sql.substring(0, sql.length - 1);
  return Condition("NOT EXISTS ($sql)");
}

Condition notIlike(String column, String pattern) {
  return Condition("$column NOT ILIKE ?", [pattern]);
}

Condition notInArray(String column, List<dynamic> values) {
  final placeholders = List.filled(values.length, '?').join(', ');
  return Condition("$column NOT IN ($placeholders)", values);
}

Condition or(List<Condition> conditions) {
  final clauses = conditions.map((c) => c.clause).join(" OR ");
  final values = conditions.expand((c) => c.values).toList();
  return Condition("($clauses)", values);
}

String _escapeIdentifier(String input) {
  return input.split('.').map((part) => '"$part"').join('.');
}

String _escapeValue(dynamic value) {
  if (value is String) {
    return "'${value.replaceAll("'", "''")}'";
  }
  return value.toString();
}

class Condition {
  final String clause;
  final List<dynamic> values;
  Condition(this.clause, [List<dynamic>? values]) : values = values ?? [];
}
