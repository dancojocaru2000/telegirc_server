import 'package:sqlite3/sqlite3.dart';

extension SqliteDbExt on Database {
  int checkMaster({required String type, required String name}) {
    final result = select('select count(*) as cnt from sqlite_master where type=? and name=?', [type, name]);
    return result.first['cnt'];
  }
}