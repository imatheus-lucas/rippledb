import 'package:rippledb/core/driver/driver.dart';
import 'package:rippledb/core/driver/drivers.dart';
import 'package:rippledb/core/types/types.dart';

class SqlDriverFactory {
  static Future<DatabaseDriver> getDriver(
    String uri,
    final Map<String, TableSchema> schemas,
  ) async {
    if (uri.startsWith('sqlite') || uri.startsWith(':memory')) {
      final driver = SqliteDriverImpl(uri, schemas);
      await driver.connect();

      return driver;
    }

    throw Exception("Driver don't support");
  }
}
