import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'energy.dart';
import 'models.dart';
import 'prefs.dart';

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
    _db = await openDatabase(dbPath, version: 2, onUpgrade: (db, from, _) async {
      if (from < 2) await _createV2(db);
    }, onCreate: (db, _) async {
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
      await _createV2(db);
    });
  }

  /// v2: waga, aktywności, zatwierdzone dni. `source` + `external_id` pod import z Health Connect (Fitbit).
  static Future<void> _createV2(Database db) async {
    await db.execute('''
      CREATE TABLE weights (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day TEXT NOT NULL UNIQUE,
        kg REAL NOT NULL,
        source TEXT NOT NULL DEFAULT 'manual',
        external_id TEXT
      )''');
    await db.execute('''
      CREATE TABLE activities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at TEXT NOT NULL,
        type TEXT NOT NULL,
        minutes INTEGER NOT NULL,
        intensity TEXT NOT NULL,
        kcal REAL NOT NULL,
        kcal_source TEXT NOT NULL DEFAULT 'met',
        source TEXT NOT NULL DEFAULT 'manual',
        external_id TEXT,
        note TEXT
      )''');
    await db.execute('CREATE INDEX idx_activities_started ON activities(started_at)');
    await db.execute('CREATE UNIQUE INDEX idx_activities_ext ON activities(source, external_id)');
    await db.execute('CREATE TABLE day_status (day TEXT PRIMARY KEY, complete INTEGER NOT NULL)');
  }

  static Future<void> close() => _db.close();

  static File photoFile(String name) => File('$photosDir/$name');

  static Future<void> save(Entry e) async {
    if (e.id == null) {
      e.id = await _db.insert('entries', e.toMap()..remove('id'));
    } else {
      await _db.update('entries', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
    }
    _changed();
  }

  static Future<void> delete(Entry e) async {
    await _db.delete('entries', where: 'id = ?', whereArgs: [e.id]);
    if (e.photo != null) {
      final f = photoFile(e.photo!);
      if (await f.exists()) await f.delete();
    }
    _changed();
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

  static Future<DateTime?> firstEntryDay() async {
    final r = await _db.rawQuery('SELECT MIN(eaten_at) AS m FROM entries');
    final m = r.first['m'] as String?;
    return m == null ? null : dayOf(DateTime.parse(m));
  }

  /// Wywoływane po każdej zmianie danych (wpis, waga, aktywność, zatwierdzenie dnia, import).
  /// W aplikacji planuje od nowa powiadomienia; w testach puste.
  static Future<void> Function()? onChanged;
  static void _changed() => onChanged?.call();

  // ---------- waga ----------

  /// Jedno ważenie na dzień: nowy wpis z tego samego dnia zastępuje poprzedni.
  static Future<void> saveWeight(WeightEntry w) async {
    w.id = await _db.insert('weights', w.toMap()..remove('id'), conflictAlgorithm: ConflictAlgorithm.replace);
    _changed();
  }

  static Future<void> deleteWeight(WeightEntry w) async {
    await _db.delete('weights', where: 'id = ?', whereArgs: [w.id]);
    _changed();
  }

  static Future<List<WeightEntry>> weights() async =>
      (await _db.query('weights', orderBy: 'day')).map(WeightEntry.fromMap).toList();

  // ---------- aktywności ----------

  static Future<void> saveActivity(Activity a) async {
    if (a.id == null) {
      a.id = await _db.insert('activities', a.toMap()..remove('id'));
    } else {
      await _db.update('activities', a.toMap(), where: 'id = ?', whereArgs: [a.id]);
    }
    _changed();
  }

  static Future<void> deleteActivity(Activity a) async {
    await _db.delete('activities', where: 'id = ?', whereArgs: [a.id]);
    _changed();
  }

  /// Aktywności z dni [from, to] włącznie.
  static Future<List<Activity>> activities(DateTime from, DateTime to) async {
    final rows = await _db.query(
      'activities',
      where: 'started_at >= ? AND started_at < ?',
      whereArgs: [dayOf(from).toIso8601String(), DateTime(to.year, to.month, to.day + 1).toIso8601String()],
      orderBy: 'started_at',
    );
    return rows.map(Activity.fromMap).toList();
  }

  // ---------- zatwierdzone dni ----------

  static Future<void> setDayComplete(DateTime day, bool complete) async {
    complete
        ? await _db.insert('day_status', {'day': dayKey(day), 'complete': 1},
            conflictAlgorithm: ConflictAlgorithm.replace)
        : await _db.delete('day_status', where: 'day = ?', whereArgs: [dayKey(day)]);
    _changed();
  }

  static Future<Set<DateTime>> completeDays(DateTime from, DateTime to) async {
    final rows = await _db
        .query('day_status', where: 'day >= ? AND day <= ? AND complete = 1', whereArgs: [dayKey(from), dayKey(to)]);
    return {for (final r in rows) DateTime.parse(r['day'] as String)};
  }

  // ---------- energia ----------

  /// Zapotrzebowanie z ostatnich 60 dni danych (adaptacyjne, patrz energy.dart).
  static Future<EnergyEstimate> estimate([DateTime? now]) async {
    final today = dayOf(now ?? DateTime.now());
    final from = DateTime(today.year, today.month, today.day - 60);
    final entries = await range(from, today);
    final complete = await completeDays(from, today);
    final intake = <DateTime, DayIntake>{
      for (final d in complete) d: (kcal: 0, meals: 0, confirmed: true), // dzień bez jedzenia też może być pełny
      for (final MapEntry(key: d, value: list) in byDay(entries).entries)
        d: (
          kcal: sumValues(list.map((e) => e.values))['kcal']!,
          meals: list.where((e) => e.mealType != MealType.drink).length,
          confirmed: complete.contains(d),
        ),
    };
    final activity = <DateTime, double>{};
    for (final a in await activities(from, today)) {
      activity.update(dayOf(a.startedAt), (v) => v + a.kcal, ifAbsent: () => a.kcal);
    }
    return estimateEnergy(
      profile: prefs.profile,
      weighIns: [for (final w in await weights()) (day: w.day, kg: w.kg)],
      intake: intake,
      activityKcal: activity,
      today: today,
    );
  }

  /// Granice dnia: baza z [e] + aktywności z tego dnia − deficyt celu.
  static Future<DayBudget> budget(DateTime day, EnergyEstimate e) async {
    final kcal = (await activities(day, day)).fold(0.0, (s, a) => s + a.kcal);
    return dayBudget(e, kcal,
        rateKgWeek: prefs.rateKgWeek, goalWeight: prefs.goalWeight, kcalOverride: prefs.overrides['kcal']);
  }
}
