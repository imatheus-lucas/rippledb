import 'dart:core';

ColumnType blob({String? columnName}) => ColumnType("BLOB", columnName);

ColumnType datetime({String? columnName, int? fsp}) {
  String typeStr = "DATETIME";

  if (fsp != null) {
    typeStr += "($fsp)";
  }
  return ColumnType(typeStr, columnName);
}

// For INTEGER, mode defaults to 'number', but supports 'boolean' and 'timestamp'.
ColumnType integer({String? columnName, String mode = 'number'}) =>
    ColumnType("INTEGER", columnName, mode);

ColumnType real({String? columnName, int? precision, int? scale}) {
  String typeStr = "REAL";

  if (precision != null) {
    typeStr += "($precision${scale != null ? ",$scale" : ""})";
  }
  return ColumnType(typeStr, columnName);
}

// For TEXT, mode defaults to 'string', but 'json' is also supported.
ColumnType text({
  String? columnName,
  String mode = 'string',
  List<String>? enumerate,
}) => ColumnType("TEXT", columnName, mode);

class ColumnType {
  final String? columnName;
  final String baseType;
  // The mode property allows conversion for types:
  // For INTEGER: 'number' (default), 'boolean', 'timestamp'.
  // For TEXT: 'string' (default), 'json'.
  final String? mode;
  final List<String> modifiers = [];
  final bool isEnum;

  // Constructor accepts an optional mode.
  ColumnType(this.baseType, [this.columnName, this.mode, this.isEnum = false]);

  /// Define a default value using a raw SQL expression.
  ColumnType $default(dynamic value) {
    modifiers.add("DEFAULT $value");
    return this;
  }

  /// Define the default as the current timestamp.
  ColumnType defaultNow() {
    modifiers.add("DEFAULT CURRENT_TIMESTAMP");
    return this;
  }

  ColumnType notNull() {
    modifiers.add("NOT NULL");
    return this;
  }

  ColumnType primaryKey({bool autoIncrement = false}) {
    if (autoIncrement) {
      modifiers.add("PRIMARY KEY AUTOINCREMENT");
    } else {
      modifiers.add("PRIMARY KEY NOT NULL");
    }
    return this;
  }

  // Transforms "table.column" into "table(column)" for SQLite.
  ColumnType references(String Function() ref) {
    String rawRef = ref();
    if (rawRef.contains('.')) {
      final parts = rawRef.split('.');
      if (parts.length == 2) {
        rawRef = "${parts[0]}(${parts[1]})";
      }
    }
    modifiers.add("REFERENCES $rawRef");
    return this;
  }

  @override
  String toString() {
    return "$baseType ${modifiers.join(' ')}".trim();
  }

  ColumnType unique() {
    modifiers.add("UNIQUE");
    return this;
  }
}

enum PrimaryColumnType { autoIncrement, uuid }
