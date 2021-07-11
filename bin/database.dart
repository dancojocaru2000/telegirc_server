import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'sqlite_utils.dart';

const _CURRENT_DB_VERSION = 1;

class Database {
  sqlite.Database? _db;

  Database._();

  static void initialize([String? path]) {
    final i = Database.instance;
    i._db?.dispose();
    if (path == null) {
      i._db = sqlite.sqlite3.openInMemory();
    } else {
      i._db = sqlite.sqlite3.open(path);
    }

    if (i._db!.checkMaster(
          type: 'table',
          name: 'telegirc_server',
        ) >
        0) {
          final dbVersion = i._db!.select('select version from telegirc_server').first['version'];
          print('DB Version: $dbVersion');

          if (dbVersion > _CURRENT_DB_VERSION) {
            // Error
            throw NewerDatabaseException(actualVersion: dbVersion, expectedVersion: _CURRENT_DB_VERSION);
          }
          else if (dbVersion < _CURRENT_DB_VERSION) {
            // Migrate
            migrate(dbVersion);
            initialize(path);
          }
    } else {
      // Create db version table
      i._db!.execute('create table telegirc_server(version int)');
      i._db!.execute('insert into telegirc_server values (?)', [_CURRENT_DB_VERSION]);

      print('Created DB with version $_CURRENT_DB_VERSION');
    }
  }

  static void migrate(int currentVersion) {
    if (currentVersion == 1) {
      Database._instance._db!.execute('drop table telegirc_server');
    }
  }

  static final Database _instance = Database._();
  static Database get instance => _instance;
}

class DatabaseException implements Exception {
  final String? message;

  DatabaseException({this.message});

  @override
  String toString() {
    var result = 'DatabaseException';
    if (message != null) {
      result += ': $message';
    }
    return result;
  }
}

/// Thrown when the database opened is newer than the application expects
class NewerDatabaseException extends DatabaseException {
  final int actualVersion;
  final int expectedVersion;

  NewerDatabaseException({required this.actualVersion, required this.expectedVersion}) : super(message: 'Newer database');

  @override
  String toString() {
    return 'NewerDatabaseException: excepted $expectedVersion, actually $actualVersion';
  }
}