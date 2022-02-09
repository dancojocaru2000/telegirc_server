import 'dart:convert';

import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:uuid/uuid.dart';

import 'logging.dart';
import 'sqlite_utils.dart';

const _CURRENT_DB_VERSION = 3;

class Database {
  sqlite.Database? _db;

  Database._();

  static void initialize([String? path]) {
    final i = Database.instance;
    i._db?.dispose();
    if (path == null) {
      lDebug(function: 'Database::initialize', message: 'Opening in memory');
      i._db = sqlite.sqlite3.openInMemory();
    } else {
      lDebug(function: 'Database::initialize', message: 'Opening file: $path');
      i._db = sqlite.sqlite3.open(path);
    }

    if (i._db!.checkMaster(
          type: 'table',
          name: 'telegirc_server',
        ) >
        0) {
          final dbVersion = i._db!.select('select version from telegirc_server').first['version'];
          lDebug(function: 'Database::initialize', message: 'Current DB version: $dbVersion');

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

      i._db!.execute('''
      create table users(
        id integer primary key autoincrement,
        dbId text not null unique,
        baseNick text not null unique,
        password text not null,
        settings text
      )
        ''');

      lInfo(function: 'Database::initialize', message: 'Created DB with version $_CURRENT_DB_VERSION');
    }
  }

  static void migrate(int currentVersion) {
    if (currentVersion == 1) {
      final db = Database._instance._db!;
      lDebug(function: 'Database::migrate', message: 'Creating new_users');
      db.execute('create table new_users(id integer primary key autoincrement, dbId text not null unique, baseNick text not null unique, password text not null)');
      for (final row in db.select('select * from users')) {
        db.execute('insert into new_users(dbId, baseNick, password) values (?, ?, ?)', [row['dbId'], row['baseNick'], '']);
      }
      lDebug(function: 'Database::migrate', message: 'Dropping users');
      db.execute('drop table users');
      lDebug(function: 'Database::migrate', message: 'Renaming new_users to users');
      db.execute('alter table new_users rename to users');

      db.execute('update telegirc_server set version = 2');
    }
    else if (currentVersion == 2) {
      final db = Database._instance._db!;
      lDebug(function: 'Database::migrate', message: 'Creating new_users');
      db.execute('create table new_users(id integer primary key autoincrement, dbId text not null unique, baseNick text not null unique, password text not null, settings text)');
      for (final row in db.select('select * from users')) {
        db.execute('insert into new_users(dbId, baseNick, password, settings) values (?, ?, ?, ?)', [row['dbId'], row['baseNick'], row['password'], null]);
      }
      lDebug(function: 'Database::migrate', message: 'Dropping users');
      db.execute('drop table users');
      lDebug(function: 'Database::migrate', message: 'Renaming new_users to users');
      db.execute('alter table new_users rename to users');

      db.execute('update telegirc_server set version = 3');
    }
  }

  static final Database _instance = Database._();
  static Database get instance => _instance;

  void _ensureInit() {
    if (_db == null) {
      throw DatabaseException(message: 'Database is not initialized');
    }
  }

  List<UserEntry> getUsers() {
    _ensureInit();
    final result = _db!.select('select * from users');
    return result
        .map((row) => UserEntry(
              id: row['id'],
              dbId: row['dbId'],
              baseNick: row['baseNick'],
              loginPassword: row['password'], 
            ))
        .toList(growable: false);
  }

  UserEntry? getUser({int? id, String? baseNick}) {
    _ensureInit();
    assert(id != null || baseNick != null);
    sqlite.ResultSet result;
    if (id != null && baseNick != null) {
      result = _db!.select('select * from users where id = ? and baseNick = ?', [id, baseNick]);
    }
    else if (id != null) {
      result = _db!.select('select * from users where id = ?', [id]);
    }
    else {
      result = _db!.select('select * from users where baseNick = ?', [baseNick]);
    }
    if (result.rows.isEmpty) {
      return null;
    }
    final row = result.single;
    return UserEntry(
      id: row['id'],
      dbId: row['dbId'], 
      baseNick: row['baseNick'],
      loginPassword: row['password'],
      settings: row['settings'] == null ? null : jsonDecode(row['settings']),
    );
  }

  UserEntry addUser(UserEntry entry) {
    _ensureInit();
    final db = _db!;
    db.execute(
      'insert into users(dbId, baseNick, password, settings) values (?, ?, ?, ?)',
      [
        entry.dbId,
        entry.baseNick,
        entry.loginPassword,
        jsonEncode(entry.settings),
      ],
    );
    return getUser(baseNick: entry.baseNick)!;
  }

  String newUserDbId() {
    final dbIds = getUsers().map((u) => u.dbId).toList(growable: false);
    String newDbId;
    do {
      newDbId = Uuid().v4();
    } while (dbIds.contains(newDbId));
    return newDbId;
  }

  void logout(UserEntry entry) {
    _ensureInit();
    final db = _db!;
    db.execute('delete from users where id = ?', [entry.id]);
  }

  void updateUser(UserEntry entry) {
    _ensureInit();
    _db!.execute(
      'update users set dbId = ?, baseNick = ?, password = ?, settings = ? where id = ?',
      [
        entry.dbId,
        entry.baseNick,
        entry.loginPassword,
        jsonEncode(entry.settings),
        entry.id,
      ],
    );
  }
}

class UserEntry {
  final int id;
  final String dbId;
  final String baseNick;
  final String loginPassword;
  late final Map<String, dynamic> settings;

  UserEntry({
    this.id = -1,
    required this.dbId,
    required this.baseNick,
    required this.loginPassword,
    Map<String, dynamic>? settings,
  }) {
    this.settings = settings ?? {};
  }

  UserEntry copyWith({String? baseNick, String? loginPassword}) {
    return UserEntry(
      id: id,
      dbId: dbId, 
      baseNick: baseNick ?? this.baseNick, 
      loginPassword: loginPassword ?? this.loginPassword,
      settings: Map.of(settings),
    );
  }
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