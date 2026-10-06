import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class Db {
  static late Database _db;
  static late String photosDir;
  static late String dbPath;

  static Future<void> init() async {
    photosDir = '${(await getApplicationDocumentsDirectory()).path}/photos';
    await Directory(photosDir).create(recursive: true);
    dbPath = '${await getDatabasesPath()}/food_diary.db';
    await open();
  }

  static Future<void> open() async {
    _db = await openDatabase(dbPath, version: 1, onCreate: (db, _) async {
      final cols = nutrients.map((n) => '${n.key} REAL NOT NULL DEFAULT 0').join(', ');
      await db.execute('''
        CREATE TABLE entries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          eaten_at TEXT NOT NULL,
          meal_type TEXT NOT NULL,
          name TEXT NOT NULL,
          portion TEXT NOT NULL DEFAULT '',
          description TEXT,
          photo_path TEXT,
          ai_notes TEXT,
          $cols
        )''');
      await db.execute('CREATE INDEX idx_eaten_at ON entries(eaten_at)');
    });
  }

  static Future<void> close() => _db.close();

  static File photoFile(String name) => File('$photosDir/$name');

  static Future<void> save(Entry e) async {
    if (e.id == null) {
      e.id = await _db.insert('entries', e.toMap()..remove('id'));
    } else {
      await _db.update('entries', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
    }
  }

  static Future<void> delete(Entry e) async {
    await _db.delete('entries', where: 'id = ?', whereArgs: [e.id]);
    if (e.photo != null) {
      final f = photoFile(e.photo!);
      if (await f.exists()) await f.delete();
    }
  }

  /// Wpisy z dni [from, to] włącznie.
  static Future<List<Entry>> range(DateTime from, DateTime to) async {
    final rows = await _db.query(
      'entries',
      where: 'eaten_at >= ? AND eaten_at < ?',
      whereArgs: [dayOf(from).toIso8601String(), DateTime(to.year, to.month, to.day + 1).toIso8601String()],
      orderBy: 'eaten_at',
    );
    return rows.map(Entry.fromMap).toList();
  }

  static Future<List<Entry>> day(DateTime d) => range(d, d);
}
