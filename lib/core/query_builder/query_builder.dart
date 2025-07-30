import 'dart:async';

import 'package:ripple/core/driver/driver.dart';
import 'package:ripple/core/driver/sqlite_driver_impl.dart';
import 'package:ripple/core/utils.dart';

import '../types/table.dart';
import 'condition.dart';

// Alterações feitas para manter o nome original da tabela para lookup em _schemas.
// Será criado um atributo _tableName para armazenar o nome original, e _table escapado será utilizado somente na geração da SQL.
class QueryBuilder implements Future<dynamic> {
  final DatabaseDriver _driver;
  String _tableName = '';
  List<String> _columns = ['*'];
  final List<String> _whereClauses = [];
  final List<dynamic> _whereParameters = []; // <-- NOVA PROPRIEDADE
  final List<dynamic> _parameters = []; // Esta será usada para INSERT
  final List<String> _orderByClauses = [];
  final List<String> _joinClauses = [];
  final List<String> _unionQueries = [];
  int? _limit;
  int? _offset;
  Map<String, dynamic> _insertData = {};
  Map<String, dynamic> _updateData = {};
  String? _queryType;

  String? _createTableSQL;
  final List<String> _alterTableCommands = [];
  final Map<String, TableSchema> _schemas;
  final List<String> _groupByClauses = [];
  final List<String> _havingClauses = [];

  String? _returningClause;

  final SqliteDriverImpl _reactiveDriver;
  final Set<String> _involvedTables = {};
  QueryBuilder(DatabaseDriver driver, this._schemas)
    : _driver = driver,
      _reactiveDriver = driver as SqliteDriverImpl;
  Set<String> get involvedTables => Set.unmodifiable(_involvedTables);
  QueryBuilder addColumn(String columnName, String columnType) {
    _alterTableCommands.add(
      "ADD COLUMN ${_escapeIdentifier(columnName)} $columnType",
    );
    return this;
  }

  @override
  Stream<dynamic> asStream() => Stream.fromFuture(_internalExecute());

  @override
  Future<dynamic> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) {
    return _internalExecute().catchError(onError, test: test);
  }

  QueryBuilder count([Condition? condition]) {
    _columns = ["COUNT(*)"];
    if (condition != null) {
      _whereClauses.add(condition.clause);
      _parameters.addAll(condition.values);
    }
    return this;
  }

  QueryBuilder createTable(String table, Map<String, String> columns) {
    _queryType = 'CREATE_TABLE';
    _createTableSQL =
        "CREATE TABLE IF NOT EXISTS ${_escapeIdentifier(table)} (${columns.entries.map((e) => "${e.key} ${e.value}").join(', ')})";
    return this;
  }

  QueryBuilder delete(Table table) {
    _tableName = table.name;
    _queryType = 'DELETE';
    return this;
  }

  QueryBuilder dropColumn(String columnName) {
    _alterTableCommands.add("DROP COLUMN ${_escapeIdentifier(columnName)}");
    return this;
  }

  QueryBuilder dropTable(String table) {
    _queryType = 'DROP_TABLE';
    _tableName = table;
    return this;
  }

  // Armazena o nome original da tabela para lookup do schema.
  QueryBuilder from(String table) {
    _tableName = table;
    _involvedTables.add(table);
    return this;
  }

  QueryBuilder fullJoin(String table, Condition condition) {
    _joinClauses.add(
      "FULL JOIN ${_escapeIdentifier(table)} ON ${condition.clause}",
    );
    _involvedTables.add(table);
    _parameters.addAll(condition.values);
    return this;
  }

  QueryBuilder function(String function, String column, String alias) {
    _columns = [
      "$function(${_escapeIdentifier(column)}) AS ${_escapeIdentifier(alias)}",
    ];
    return this;
  }

  List<dynamic> getParameters() => _parameters;

  QueryBuilder groupBy(List<String> columns) {
    _groupByClauses.addAll(columns.map(_escapeIdentifier));
    return this;
  }

  QueryBuilder having(
    dynamic columnOrCondition, [
    String? operator,
    dynamic value,
  ]) {
    if (columnOrCondition is Condition) {
      _havingClauses.add(columnOrCondition.clause);
      _parameters.addAll(columnOrCondition.values);
    } else {
      _havingClauses.add("$columnOrCondition $operator ?");
      _parameters.add(value);
    }
    return this;
  }

  QueryBuilder innerJoin(String table, Condition condition) {
    _joinClauses.add(
      "INNER JOIN ${_escapeIdentifier(table)} ON ${condition.clause}",
    );
    _involvedTables.add(table);
    _parameters.addAll(condition.values);
    return this;
  }

  QueryBuilder insert(Table table) {
    _tableName = table.name;
    _queryType = 'INSERT';
    return this;
  }

  QueryBuilder leftJoin(String table, Condition condition) {
    _joinClauses.add(
      "LEFT JOIN ${_escapeIdentifier(table)} ON ${condition.clause}",
    );
    _involvedTables.add(table);
    _parameters.addAll(condition.values);
    return this;
  }

  QueryBuilder limit(int value) {
    _limit = value;
    return this;
  }

  QueryBuilder offset(int value) {
    _offset = value;
    return this;
  }

  QueryBuilder orderBy(String column, [String direction = 'ASC']) {
    _orderByClauses.add("${_escapeIdentifier(column)} $direction");
    return this;
  }

  QueryBuilder returning([List<String>? columns]) {
    if (columns == null || columns.isEmpty) {
      _returningClause = "RETURNING *";
    } else {
      if (columns.length == 1 && columns.first == '*') {
        _returningClause = "RETURNING *";
        return this;
      }
      final escapedColumns = columns
          .map((col) => _escapeIdentifier(col))
          .join(', ');
      _returningClause = "RETURNING $escapedColumns";
    }
    return this;
  }

  QueryBuilder returningId() {
    _returningClause = "RETURNING id";
    return this;
  }

  QueryBuilder rightJoin(String table, Condition condition) {
    _joinClauses.add(
      "RIGHT JOIN ${_escapeIdentifier(table)} ON ${condition.clause}",
    );
    _involvedTables.add(table);
    _parameters.addAll(condition.values);
    return this;
  }

  QueryBuilder select([Map<String, String>? columns]) {
    _queryType = 'SELECT';
    if (columns == null) {
      _columns = ['*'];
    } else {
      _columns = columns.entries
          .map(
            (e) =>
                "${_escapeIdentifier(e.value)} AS ${_escapeIdentifier(e.key)}",
          )
          .toList();
    }
    return this;
  }

  QueryBuilder set(Map<String, dynamic> data) {
    final tableSchema = _schemas[_tableName];
    _updateData = {};
    data.forEach((key, value) {
      if (tableSchema != null && tableSchema.columns.containsKey(key)) {
        final colType = tableSchema.columns[key]!;
        _updateData[key] = convertValueForInsert(value, colType);
      } else {
        _updateData[key] = value;
      }
    });
    // _parameters.addAll(_updateData.values);
    return this;
  }

  @override
  Future<S> then<S>(
    FutureOr<S> Function(dynamic value) onValue, {
    Function? onError,
  }) {
    return _internalExecute().then<S>(onValue, onError: onError);
  }

  @override
  Future<dynamic> timeout(
    Duration timeLimit, {
    FutureOr<dynamic> Function()? onTimeout,
  }) {
    return _internalExecute().timeout(timeLimit, onTimeout: onTimeout);
  }

  String toSql() {
    // Use _escapeIdentifier para obter o nome da tabela escapado.
    final tableEscaped = _escapeIdentifier(_tableName);
    if (_queryType == 'SELECT') {
      String sql = "SELECT ${_columns.join(', ')} FROM $tableEscaped";
      if (_joinClauses.isNotEmpty) {
        sql += " ${_joinClauses.join(" ")}";
      }
      if (_whereClauses.isNotEmpty) {
        sql += " WHERE ${_whereClauses.join(" AND ")}";
      }
      if (_groupByClauses.isNotEmpty) {
        sql += " GROUP BY ${_groupByClauses.join(", ")}";
      }
      if (_havingClauses.isNotEmpty) {
        sql += " HAVING ${_havingClauses.join(" AND ")}";
      }
      if (_orderByClauses.isNotEmpty) {
        sql += " ORDER BY ${_orderByClauses.join(", ")}";
      }
      if (_limit != null) {
        sql += " LIMIT $_limit";
      }
      if (_offset != null) {
        sql += " OFFSET $_offset";
      }
      if (_unionQueries.isNotEmpty) {
        sql += " UNION ${_unionQueries.join(" UNION ")}";
      }
      return "$sql;";
    }
    if (_queryType == 'INSERT') {
      final columns = _insertData.keys
          .map((col) => _escapeIdentifier(col))
          .join(', ');
      final placeholders = List.filled(_insertData.length, '?').join(', ');
      String sql =
          "INSERT INTO $tableEscaped ($columns) VALUES ($placeholders)";
      if (_returningClause != null) {
        sql += " $_returningClause";
      }
      return sql;
    }
    if (_queryType == 'UPDATE') {
      final setClause = _updateData.keys
          .map((key) => "${_escapeIdentifier(key)} = ?")
          .join(", ");
      String sql = "UPDATE $tableEscaped SET $setClause";
      if (_whereClauses.isNotEmpty) {
        sql += " WHERE ${_whereClauses.join(" AND ")}";
      }
      if (_returningClause != null) {
        sql += " $_returningClause";
      }
      return "$sql;";
    }
    if (_queryType == 'DELETE') {
      String sql = "DELETE FROM $tableEscaped";
      if (_whereClauses.isNotEmpty) {
        sql += " WHERE ${_whereClauses.join(" AND ")}";
      }
      if (_returningClause != null) {
        sql += " $_returningClause";
      }
      return "$sql;";
    }
    if (_queryType == 'CREATE_TABLE') {
      return "${_createTableSQL!};";
    }
    if (_queryType == 'DROP_TABLE') {
      return "DROP TABLE IF EXISTS $tableEscaped;";
    }
    if (_alterTableCommands.isNotEmpty) {
      return "ALTER TABLE $tableEscaped ${_alterTableCommands.join(", ")};";
    }
    throw Exception('Nenhuma operação definida!');
  }

  QueryBuilder union(QueryBuilder otherQuery) {
    _unionQueries.add(otherQuery.toSql());
    return this;
  }

  QueryBuilder update(Table table) {
    _tableName = table.name;
    _queryType = 'UPDATE';
    return this;
  }

  QueryBuilder values(Map<String, dynamic> data) {
    _parameters.clear();
    final tableSchema = _schemas[_tableName];
    _insertData = {};
    data.forEach((key, value) {
      if (tableSchema != null && tableSchema.columns.containsKey(key)) {
        final colType = tableSchema.columns[key]!;
        _insertData[key] = convertValueForInsert(value, colType);
      } else {
        _insertData[key] = value;
      }
    });
    _parameters.addAll(_insertData.values);
    return this;
  }

  @override
  Future<dynamic> whenComplete(FutureOr<void> Function() action) {
    return _internalExecute().whenComplete(action);
  }

  QueryBuilder where(
    dynamic columnOrCondition, [
    String? operator,
    dynamic value,
  ]) {
    if (columnOrCondition is Condition) {
      _whereClauses.add(columnOrCondition.clause);
      _whereParameters.addAll(columnOrCondition.values); // <-- ADICIONE AQUI
    } else {
      _whereClauses.add("$columnOrCondition $operator ?");
      _whereParameters.add(value); // <-- E AQUI
    }
    return this;
  }

  String _escapeIdentifier(String identifier) {
    if (identifier.toLowerCase().contains('count')) {
      return identifier;
    }
    if (identifier.contains('.')) {
      return identifier.split('.').map((part) => '"$part"').join('.');
    }
    return '"$identifier"';
  }

  Future<dynamic> _internalExecute() async {
    final sql = toSql();
    List<dynamic> params = [];

    switch (_queryType) {
      case 'INSERT':
        params = _parameters;
        break;
      case 'UPDATE':
        // A ordem é crucial: primeiro os valores do SET, depois os do WHERE.
        params = [..._updateData.values, ..._whereParameters];
        break;
      case 'DELETE':
      case 'SELECT':
        params = _whereParameters;
        break;
    }
    dynamic result;

    if (_queryType == 'SELECT' || _returningClause != null) {
      result = await _driver.execute(sql, params);

      if (_queryType == 'SELECT' &&
          _columns.length == 1 &&
          _columns[0].toLowerCase().startsWith("count(") &&
          result is List &&
          result.isNotEmpty &&
          result[0] is Map) {
        final row = result[0] as Map;
        if (row.length == 1) {
          result = row.values.first;
        }
      } else if (result is List) {
        final mappedResult = result.map((row) {
          if (row is Map<String, dynamic>) {
            row.forEach((key, value) {
              final colType = _schemas[_tableName]?.columns[key];
              if (colType != null) {
                row[key] = convertValueForSelect(value, colType);
              }
            });
          }
          return row;
        });

        result = List<Map<String, dynamic>>.from(mappedResult);
      }
    } else {
      await _driver.raw(sql, params); // Usa a lista `params` local
      result = null;
    }

    switch (_queryType) {
      case 'UPDATE':
      case 'INSERT':
      case 'DELETE':
        if (_tableName.isNotEmpty) {
          _reactiveDriver.notifyTableChanged({_tableName});
        }
        break;
    }

    _reset();
    return result;
  }

  void _reset() {
    _tableName = '';
    _columns = ['*'];
    _whereClauses.clear();
    _whereParameters.clear();
    _orderByClauses.clear();
    _joinClauses.clear();
    _unionQueries.clear();
    _limit = null;
    _offset = null;
    _insertData.clear();
    _updateData.clear();
    _queryType = null;
    _parameters.clear();
    _createTableSQL = null;
    _alterTableCommands.clear();
    _returningClause = null;
    _groupByClauses.clear();
    _havingClauses.clear();
    _involvedTables.clear();
  }
}
