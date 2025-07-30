import 'column.dart';

/// Tipos suportados para SQLite
const List<String> supportedSqliteTypes = [
  "INTEGER",
  "TEXT",
  "REAL",
  "BLOB",
  "DATETIME",
];

/// Funções para criar tabelas para diferentes bancos de dados

Table sqliteTable(
  String name,
  Map<String, ColumnType> columns, {
  List<ForeignKey> foreignKeys = const [],
}) {
  final cols = columns.map((key, value) {
    final colName = value.columnName ?? key;

    if (!supportedSqliteTypes.contains(value.baseType)) {
      throw Exception(
        "O tipo de coluna '${value.baseType}' não é suportado pelo SQLite.",
      );
    }

    return MapEntry(colName, value);
  });

  return Table(name, Map.from(cols), foreignKeys: foreignKeys);
}

/// Definição de uma foreign key
class ForeignKey {
  final String column;
  final String references;
  final String referencesColumn;
  final ReferentialAction? onDelete;
  final ReferentialAction? onUpdate;

  ForeignKey({
    required this.column,
    required this.references,
    required this.referencesColumn,
    this.onDelete,
    this.onUpdate,
  });

  String toSql() {
    final constraints = [
      'FOREIGN KEY ($column)',
      'REFERENCES $references($referencesColumn)',
    ];

    if (onDelete != null) {
      constraints.add('ON DELETE ${_actionToSql(onDelete!)}');
    }

    if (onUpdate != null) {
      constraints.add('ON UPDATE ${_actionToSql(onUpdate!)}');
    }

    return constraints.join(' ');
  }

  String _actionToSql(ReferentialAction action) {
    switch (action) {
      case ReferentialAction.cascade:
        return 'CASCADE';
      case ReferentialAction.restrict:
        return 'RESTRICT';
      case ReferentialAction.noAction:
        return 'NO ACTION';
      case ReferentialAction.setNull:
        return 'SET NULL';
      case ReferentialAction.setDefault:
        return 'SET DEFAULT';
    }
  }
}

/// Tipos de ações para foreign keys
enum ReferentialAction { cascade, restrict, noAction, setNull, setDefault }

/// A classe Table estende TableSchema para poder ser usada no lugar de um TableSchema
class Table extends TableSchema {
  Table(super.name, super.columns, {super.foreignKeys = const []});
}

/// Representa o schema de uma tabela
class TableSchema {
  final String name;
  final Map<String, ColumnType> columns;
  final List<ForeignKey> foreignKeys;

  TableSchema(this.name, this.columns, {this.foreignKeys = const []});
}
