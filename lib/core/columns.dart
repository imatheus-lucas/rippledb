// DSL helpers:
IntColumn integer() => IntColumn();

TextColumn text() => TextColumn();

abstract class ColumnBuilder {
  String buildType();
}

class IntColumn extends ColumnBuilder {
  bool isPrimaryKey = false;
  bool isAutoIncrement = false;

  @override
  String buildType() {
    String type = 'INTEGER';
    if (isPrimaryKey) type += ' PRIMARY KEY';
    if (isAutoIncrement) type += ' AUTOINCREMENT';
    return type;
  }

  IntColumn primaryKey({bool autoIncrement = false}) {
    isPrimaryKey = true;
    isAutoIncrement = autoIncrement;
    return this;
  }
}

class TextColumn extends ColumnBuilder {
  bool isNotNull = false;

  @override
  String buildType() {
    return isNotNull ? 'TEXT NOT NULL' : 'TEXT';
  }

  TextColumn notNull() {
    isNotNull = true;
    return this;
  }
}
