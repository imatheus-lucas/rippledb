abstract class DatabaseDriver {
  Stream<Set<String>> get changeFeed;
  Future<void> connect();
  Future<void> createTable(String table, Map<String, String> columns);

  void dispose();
  Future<List<Map<String, dynamic>>> execute(
    String query, [
    List<dynamic>? parameters,
  ]);

  void notifyTableChanged(Set<String> tableNames);

  Future<void> raw(String query, [List<dynamic>? parameters]);
}
