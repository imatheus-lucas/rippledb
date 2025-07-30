import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:rippledb/core/driver/driver.dart';
import 'package:rippledb/core/types/column.dart';
import 'package:rippledb/core/types/table.dart';
import 'package:sqlite3/sqlite3.dart';

class SqliteDriverImpl extends DatabaseDriver {
  final String uri;
  final Map<String, TableSchema> schemas;
  late Database _connection;

  final _changeFeedController = StreamController<Set<String>>.broadcast();
  SqliteDriverImpl(this.uri, this.schemas);
  @override // Adicione o override
  Stream<Set<String>> get changeFeed => _changeFeedController.stream;
  @override
  Future<void> connect() async {
    if (uri == ':memory:') {
      _connection = sqlite3.openInMemory();
    } else if (uri.startsWith("sqlite:")) {
      final filePath = uri.replaceFirst("sqlite:", "");

      final dir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(dir.path, filePath);
      final file = File(dbPath);
      final directory = file.parent;

      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }

      _connection = sqlite3.open(dbPath);
    } else {
      throw Exception("Unsupported URI scheme");
    }

    _connection.execute('PRAGMA foreign_keys = ON;');
  }

  @override
  Future<void> createTable(String table, Map<String, String> columns) async {
    final schema = schemas[table];
    final columnDefinitions = columns.entries
        .map((e) => "${e.key} ${e.value}")
        .toList();

    if (schema?.foreignKeys != null && schema!.foreignKeys.isNotEmpty) {
      for (final fk in schema.foreignKeys) {
        final foreignKeyDef = _buildForeignKeyConstraint(fk);
        columnDefinitions.add(foreignKeyDef);
      }
    }

    final sql =
        """
      CREATE TABLE IF NOT EXISTS $table (
        ${columnDefinitions.join(',\n        ')}
      );
    """;

    try {
      _connection.execute(sql);
    } catch (e) {
      rethrow;
    }
  }

  @override // Adicione o override
  void dispose() {
    _changeFeedController.close();
    _connection.dispose();
  }

  @override
  Future<List<Map<String, dynamic>>> execute(
    String query, [
    List? parameters,
  ]) async {
    try {
      final result = parameters == null
          ? _connection.select(query)
          : _connection.select(query, parameters);

      final rows = result.map((row) {
        final nestedMap = row.toTableColumnMap();
        if (nestedMap == null) {
          return Map<String, dynamic>.from(row);
        }
        final flattened = <String, dynamic>{};
        nestedMap.forEach((_, colMap) {
          flattened.addAll(colMap);
        });
        return flattened;
      }).toList();

      return Future.value(rows);
    } catch (e) {
      rethrow;
    }
  }

  @override // Adicione o override
  void notifyTableChanged(Set<String> tableNames) {
    if (!_changeFeedController.isClosed) {
      _changeFeedController.add(tableNames);
    }
  }

  @override
  Future<dynamic> raw(String query, [List<dynamic>? parameters]) async {
    final stmt = _connection.prepare(query);

    try {
      if (parameters == null) {
        return stmt.execute();
      } else {
        return stmt.execute(parameters);
      }
    } finally {
      stmt.dispose();
    }
  }

  Future<void> runAutoMigration(
    int desiredVersion,
    Map<String, TableSchema> desiredSchema,
  ) async {
    await _initializeMigrationsTable();
    final currentVersion = await _getSchemaVersion();

    if (desiredVersion > currentVersion) {
      print(
        "Iniciando migração automática da versão $currentVersion para $desiredVersion...",
      );

      final currentSchema = await _introspectDatabaseSchema();
      final sqlCommands = _compareSchemasAndGenerateSql(
        currentSchema,
        desiredSchema,
      );

      if (sqlCommands.isEmpty) {
        print("Esquema já está atualizado. Apenas atualizando a versão.");
      } else {
        // Executar tudo em uma transação
        _connection.execute('BEGIN TRANSACTION;');
        try {
          for (final sql in sqlCommands) {
            print("Executando: $sql");
            _connection.execute(sql);
          }
        } catch (e) {
          print("ERRO DURANTE A MIGRAÇÃO: $e. Revertendo alterações...");
          _connection.execute('ROLLBACK;');
          rethrow; // Propaga o erro para que o aplicativo saiba que falhou.
        }
      }

      // Se tudo correu bem (ou não havia nada a fazer), confirme e atualize a versão.
      await _setSchemaVersion(desiredVersion);
      if (sqlCommands.isNotEmpty) _connection.execute('COMMIT;');
      print("Migração para a versão $desiredVersion concluída com sucesso.");
    } else if (desiredVersion < currentVersion) {
      print(
        "AVISO: A versão do banco de dados ($currentVersion) é mais recente que a versão do esquema no código ($desiredVersion). Nenhuma ação será tomada.",
      );
    } else {
      print(
        "Banco de dados já está na versão $desiredVersion. Nenhuma migração necessária.",
      );
    }
  }

  String _buildForeignKeyConstraint(ForeignKey fk) {
    final constraints = [
      'FOREIGN KEY (${fk.column})',
      'REFERENCES ${fk.references}(${fk.referencesColumn})',
    ];

    if (fk.onDelete != null) {
      constraints.add('ON DELETE ${_getSqliteAction(fk.onDelete!)}');
    }

    if (fk.onUpdate != null) {
      constraints.add('ON UPDATE ${_getSqliteAction(fk.onUpdate!)}');
    }

    return constraints.join(' ');
  }

  /// Compara o esquema atual com o desejado e gera os comandos SQL.
  List<String> _compareSchemasAndGenerateSql(
    Map<String, TableSchema> currentSchema,
    Map<String, TableSchema> desiredSchema,
  ) {
    final commands = <String>[];
    final currentTableNames = currentSchema.keys.toSet();
    final desiredTableNames = desiredSchema.keys.toSet();

    // 1. Tabelas a serem criadas
    final tablesToCreate = desiredTableNames.difference(currentTableNames);
    for (final tableName in tablesToCreate) {
      final schema = desiredSchema[tableName]!;
      final columnDefs = schema.columns.entries
          .map((e) => '"${e.key}" ${e.value.toString()}')
          .join(', ');
      commands.add('CREATE TABLE "$tableName" ($columnDefs);');
    }

    // 2. Tabelas a serem removidas (seja cuidadoso com isso em produção!)
    final tablesToDrop = currentTableNames.difference(desiredTableNames);
    for (final tableName in tablesToDrop) {
      commands.add('DROP TABLE "$tableName";');
    }

    // 3. Tabelas a serem modificadas
    final commonTables = currentTableNames.intersection(desiredTableNames);
    for (final tableName in commonTables) {
      final currentTable = currentSchema[tableName]!;
      final desiredTable = desiredSchema[tableName]!;

      final currentColumns = currentTable.columns.keys.toSet();
      final desiredColumns = desiredTable.columns.keys.toSet();

      final columnsToAdd = desiredColumns.difference(currentColumns);
      final columnsToDrop = currentColumns.difference(desiredColumns);

      // O SQLite tem suporte limitado para ALTER TABLE.
      // Adicionar colunas é fácil. Remover ou modificar requer uma recriação da tabela.

      for (final colName in columnsToAdd) {
        final colDef = desiredTable.columns[colName]!;
        commands.add(
          'ALTER TABLE "$tableName" ADD COLUMN "$colName" ${colDef.toString()};',
        );
      }

      if (columnsToDrop.isNotEmpty) {
        // Se alguma coluna for removida, temos que fazer a "dança" de recriação do SQLite.
        commands.addAll(_generateRecreateTableSql(currentTable, desiredTable));
      }
    }

    return commands;
  }

  /// Gera o SQL para recriar uma tabela no SQLite, preservando os dados.
  /// Isso é necessário para remover ou modificar colunas.
  List<String> _generateRecreateTableSql(
    TableSchema currentTable,
    TableSchema desiredTable,
  ) {
    final tableName = desiredTable.name;
    final tempTableName = "_${tableName}_new";

    final desiredColumns = desiredTable.columns;
    final commonColumnNames = currentTable.columns.keys.toSet().intersection(
      desiredTable.columns.keys.toSet(),
    );
    final commonColumnsString = commonColumnNames
        .map((name) => '"$name"')
        .join(', ');

    final newTableDefs = desiredColumns.entries
        .map((e) => '"${e.key}" ${e.value.toString()}')
        .join(', ');

    return [
      // 1. Crie a nova tabela com o esquema correto
      'CREATE TABLE "$tempTableName" ($newTableDefs);',
      // 2. Copie os dados da tabela antiga para a nova (apenas colunas comuns)
      'INSERT INTO "$tempTableName" ($commonColumnsString) SELECT $commonColumnsString FROM "$tableName";',
      // 3. Remova a tabela antiga
      'DROP TABLE "$tableName";',
      // 4. Renomeie a nova tabela para o nome original
      'ALTER TABLE "$tempTableName" RENAME TO "$tableName";',
    ];
  }

  Future<int> _getSchemaVersion() async {
    final result = _connection.select(
      "SELECT value FROM __ripple_meta WHERE key = 'schema_version'",
    );
    if (result.isNotEmpty) {
      return int.tryParse(result.first['value'].toString()) ?? 0;
    }
    return 0; // Se não houver versão definida, assume-se 0.
  }

  String _getSqliteAction(ReferentialAction action) {
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

  /// Inicializa a tabela que controla a versão do esquema.
  Future<void> _initializeMigrationsTable() async {
    _connection.execute('''
      CREATE TABLE IF NOT EXISTS __ripple_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');

    /// Obtém a versão atual do esquema do banco de dados.
  }

  /// Lê a estrutura atual das tabelas e colunas do banco de dados SQLite.
  Future<Map<String, TableSchema>> _introspectDatabaseSchema() async {
    final schema = <String, TableSchema>{};
    final tablesResult = _connection.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '__ripple_%';",
    );

    for (final row in tablesResult) {
      final tableName = row['name'] as String;
      final columns = <String, ColumnType>{};

      final columnsResult = _connection.select(
        'PRAGMA table_info("$tableName")',
      );
      for (final colRow in columnsResult) {
        // Simplificação: aqui estamos apenas pegando o nome e o tipo básicos.
        // Uma implementação completa precisaria analisar 'pk', 'notnull', 'dflt_value'.
        columns[colRow['name']] = ColumnType(colRow['type']);
      }
      schema[tableName] = TableSchema(tableName, columns);
    }
    return schema;
  }

  /// Define a versão do esquema no banco de dados.
  Future<void> _setSchemaVersion(int version) async {
    final stmt = _connection.prepare(
      "INSERT OR REPLACE INTO __ripple_meta (key, value) VALUES ('schema_version', ?)",
    );
    stmt.execute([version.toString()]);
    stmt.dispose();
  }
}
