import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_diary/db.dart';
import 'package:food_diary/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('migracja v1 -> v2 zachowuje wpisy i dodaje nowe tabele', () async {
    final dir = Directory.systemTemp.createTempSync('db');
    Db.dbPath = '${dir.path}/food_diary.db';
    // baza z pierwszej wersji aplikacji
    final v1 = await openDatabase(Db.dbPath, version: 1, onCreate: (db, _) async {
      final cols = nutrients.map((n) => '${n.key} REAL NOT NULL DEFAULT 0').join(', ');
      await db.execute('CREATE TABLE entries (id INTEGER PRIMARY KEY AUTOINCREMENT, eaten_at TEXT NOT NULL, '
          'meal_type TEXT NOT NULL, name TEXT NOT NULL, portion TEXT NOT NULL DEFAULT \'\', description TEXT, '
          'photo_path TEXT, ai_notes TEXT, $cols)');
    });
    await v1.insert('entries', {'eaten_at': '2026-10-01T08:00:00.000', 'meal_type': 'breakfast', 'name': 'Owsianka', 'kcal': 400});
    await v1.close();

    await Db.open();
    expect((await Db.day(DateTime(2026, 10, 1))).single.name, 'Owsianka');

    await Db.saveWeight(WeightEntry(day: DateTime(2026, 10, 1), kg: 90.4));
    await Db.saveWeight(WeightEntry(day: DateTime(2026, 10, 1), kg: 90.1)); // ten sam dzień -> zastępuje
    await Db.saveWeight(WeightEntry(day: DateTime(2026, 10, 3), kg: 89.8));
    expect((await Db.weights()).map((w) => w.kg), [90.1, 89.8]);

    await Db.saveActivity(Activity(startedAt: DateTime(2026, 10, 1, 18), type: 'run', minutes: 120, kcal: 1400));
    expect((await Db.activities(DateTime(2026, 10, 1), DateTime(2026, 10, 1))).single.kcal, 1400);
    expect(await Db.activities(DateTime(2026, 10, 2), DateTime(2026, 10, 2)), isEmpty);

    await Db.setDayComplete(DateTime(2026, 10, 1), true);
    expect(await Db.completeDays(DateTime(2026, 9, 1), DateTime(2026, 10, 31)), {DateTime(2026, 10, 1)});
    await Db.setDayComplete(DateTime(2026, 10, 1), false);
    expect(await Db.completeDays(DateTime(2026, 9, 1), DateTime(2026, 10, 31)), isEmpty);
    await Db.close();
  });
}
