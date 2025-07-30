import 'package:ripple/core/driver/driver.dart';

import '../types/table.dart';
import 'query_builder.dart';

class DatabaseFacade {
  final DatabaseDriver _driver;
  final Map<String, TableSchema> _schemas;

  DatabaseFacade(this._driver, this._schemas);

  Query get query => Query();

  QueryBuilder delete(Table table) {
    return QueryBuilder(_driver, _schemas)..delete(table);
  }

  QueryBuilder insert(Table table) {
    return QueryBuilder(_driver, _schemas)..insert(table);
  }

  QueryBuilder select([Map<String, String>? columns]) {
    return QueryBuilder(_driver, _schemas)..select(columns);
  }

  QueryBuilder update(Table table) {
    return QueryBuilder(_driver, _schemas)..update(table);
  }
}

class Query {}
