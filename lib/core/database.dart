import 'package:rippledb/core/driver/driver.dart';
import 'package:rippledb/core/driver/sql_driver_factory.dart';
import 'package:rippledb/core/driver/sqlite_driver_impl.dart';
import 'package:rippledb/core/orm/orm_table.dart';
import 'package:rippledb/core/query_builder/database_facade.dart';
import 'package:rippledb/core/types/table.dart';

class Ripple {
  static Ripple? _instance;
  final Map<String, TableSchema> _schemas;
  late final DatabaseDriver _driver;
  final String uri;
  final int version;
  factory Ripple(
    String uri, {
    required List<TableSchema> schemas,
    required int version,
  }) {
    _instance ??= Ripple._internal(uri, schemas, version);
    return _instance!;
  }
  Ripple._internal(this.uri, List<TableSchema> schemas, this.version)
    : _schemas = {for (var schema in schemas) schema.name: schema};
  DatabaseDriver get driver => _driver;
  DatabaseFacade get instance => DatabaseFacade(_driver, _schemas);
  Future<DatabaseFacade> connect() async {
    _driver = await SqlDriverFactory.getDriver(uri, _schemas);
    if (_driver is SqliteDriverImpl) {
      await _driver.runAutoMigration(version, _schemas);
    } else {
      for (final schema in _schemas.values) {
        await _driver.createTable(
          schema.name,
          schema.columns.map(
            (field, col) => MapEntry(col.columnName ?? field, col.toString()),
          ),
        );
      }
    }

    return DatabaseFacade(_driver, _schemas);
  }

  void dispose() {
    driver.dispose();
    _instance = null;
  }

  OrmTable table(String tableName) {
    return OrmTable(tableName, DatabaseFacade(_driver, _schemas));
  }
}
