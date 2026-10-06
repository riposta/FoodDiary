import 'dart:async';
import 'dart:math';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'db.dart';
import 'energy.dart';
import 'models.dart';
import 'prefs.dart';

/// Typy powiadomień; kolejność = priorytet przy limicie 3 dziennie.
enum NotifKind {
  weigh('Ważenie', 'Rano, jeśli jeszcze się nie zważyłeś (po 5 dniach przerwy mocniejsze przypomnienie)'),
  meal('Brak posiłku', 'Gdy o zwykłej porze nie ma śniadania, obiadu lub kolacji'),
  evening('Wieczorny bilans', 'Ok. 19:00: ile zostało do celu albo ile ruchu wyrówna nadwyżkę'),
  noActivity('Brak ruchu', 'Po 2 dniach bez treningu'),
  gaps('Luki w dzienniczku', 'Rano, gdy wczoraj zapisano mniej niż 2 posiłki'),
  tdee('Zmiana zapotrzebowania', 'W poniedziałek, gdy zapotrzebowanie zmieniło się o 50+ kcal'),
  milestone('Kamienie milowe', 'Pierwszy kilogram, każde −5 kg, osiągnięty cel');

  const NotifKind(this.label, this.description);
  final String label;
  final String description;
}

class PlannedNotif {
  const PlannedNotif(this.kind, this.at, this.title, this.body, {this.payload = 'today', this.sub = 0});
  final NotifKind kind;
  final DateTime at;
  final String title;
  final String body;
  final String payload; // ekran do otwarcia: today / weight / add_meal
  final int sub; // rozróżnia kilka powiadomień tego samego typu w dniu (posiłki)

  int get id => kind.index * 100 + at.weekday * 10 + sub; // dziś i jutro to zawsze różne dni tygodnia
  @override
  String toString() => '${kind.name} ${at.toIso8601String()} $title';
}

/// Dane potrzebne do zaplanowania powiadomień (zbierane z bazy przez [collectState]).
class NotifState {
  NotifState({
    required this.now,
    required this.meals,
    required this.complete,
    required this.lastWeigh,
    required this.lastActivity,
    required this.firstUse,
    required this.eatenToday,
    required this.goalToday,
    required this.weightKg,
    required this.base,
    this.lastNotifiedBase,
  });

  final DateTime now;
  final Map<DateTime, List<Entry>> meals; // ostatnie 14 dni, bez napojów
  final Set<DateTime> complete; // dni zatwierdzone jako pełne
  final DateTime? lastWeigh;
  final DateTime? lastActivity;
  final DateTime? firstUse; // pierwszy wpis w aplikacji
  final double eatenToday;
  final double goalToday;
  final double weightKg;
  final double base; // zapotrzebowanie bez treningów
  final double? lastNotifiedBase;
}

const _defaultMealMinutes = {MealType.breakfast: 11 * 60, MealType.lunch: 15 * 60, MealType.dinner: 20 * 60 + 30};
const _mealName = {MealType.breakfast: 'śniadania', MealType.lunch: 'obiadu', MealType.dinner: 'kolacji'};

bool _mealSatisfied(List<Entry> day, MealType m) =>
    day.any((e) => e.mealType == m || (m == MealType.breakfast && e.mealType == MealType.secondBreakfast));

/// Pora przypomnienia o posiłku: mediana Twoich godzin z 14 dni + 90 min (gdy jest ≥ 5 wpisów), inaczej domyślna.
int mealReminderMinutes(Map<DateTime, List<Entry>> meals, MealType m) {
  final times = [
    for (final day in meals.values)
      for (final e in day)
        if (e.mealType == m) e.eatenAt.hour * 60 + e.eatenAt.minute,
  ]..sort();
  if (times.length < 5) return _defaultMealMinutes[m]!;
  return (times[times.length ~/ 2] + 90).clamp(8 * 60, 21 * 60 + 30);
}

DateTime _at(DateTime day, int minutes) => DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);

/// Plan powiadomień na dziś (pozostała część) i jutro. Czysta funkcja: treść liczona z bieżących danych,
/// bo każda zmiana danych planuje wszystko od nowa.
List<PlannedNotif> plan(NotifState s, {Set<String> off = const {}, int weighMinutes = 7 * 60 + 30}) {
  final today = dayOf(s.now);
  final out = <PlannedNotif>[];
  for (var offset = 0; offset <= 1; offset++) {
    final day = DateTime(today.year, today.month, today.day + offset);
    final dayMeals = s.meals[day] ?? const [];
    final confirmed = s.complete.contains(day);

    // B4/B5 ważenie
    if (s.lastWeigh != day) {
      final since = s.lastWeigh == null ? null : daysBetween(s.lastWeigh!, day);
      out.add(since != null && since >= 5
          ? PlannedNotif(NotifKind.weigh, _at(day, weighMinutes), '$since dni bez ważenia',
              'Bez ważenia zapotrzebowanie przestaje się aktualizować. Zważ się przed śniadaniem.', payload: 'weight')
          : PlannedNotif(
              NotifKind.weigh, _at(day, weighMinutes), 'Czas na ważenie', 'Zważ się przed śniadaniem i zapisz wynik.',
              payload: 'weight'));
    }

    // A1 brak posiłku (nie przy zatwierdzonym dniu)
    if (!confirmed) {
      for (final (i, m) in [MealType.breakfast, MealType.lunch, MealType.dinner].indexed) {
        if (_mealSatisfied(dayMeals, m)) continue;
        out.add(PlannedNotif(NotifKind.meal, _at(day, mealReminderMinutes(s.meals, m)), 'Nie widzę ${_mealName[m]}',
            'Zrób zdjęcie, zanim zapomnisz. Jeśli dziś nie jesz więcej, zatwierdź dzień jako pełny.',
            payload: 'add_meal', sub: i));
      }
    }

    // A2 wieczorny bilans: tylko dziś, gdy coś już zjedzono
    if (offset == 0 && s.eatenToday > 0) {
      final diff = s.goalToday - s.eatenToday;
      final walkPerMin = max(0.1, metKcal('walk', Intensity.moderate, 1, s.weightKg));
      out.add(diff >= 0
          ? PlannedNotif(NotifKind.evening, _at(day, 19 * 60), 'Zostało ${fmtNum(diff)} kcal',
              'Cel na dziś: ${fmtNum(s.goalToday)} kcal, zjedzone ${fmtNum(s.eatenToday)} kcal.')
          : PlannedNotif(NotifKind.evening, _at(day, 19 * 60), '${fmtNum(-diff)} kcal ponad celem',
              'Ok. ${(-diff / walkPerMin / 5).ceil() * 5} min spaceru to wyrówna.'));
    }

    // A3 luki: rano o wczorajszym dniu
    final yesterday = DateTime(day.year, day.month, day.day - 1);
    final yMeals = (s.meals[yesterday] ?? const []).length;
    final usedBefore = s.firstUse != null && !s.firstUse!.isAfter(yesterday);
    if (usedBefore && yMeals < 2 && !s.complete.contains(yesterday)) {
      out.add(PlannedNotif(
          NotifKind.gaps,
          _at(day, 9 * 60),
          yMeals == 0 ? 'Wczoraj brak wpisów' : 'Wczoraj masz 1 posiłek',
          'Uzupełnij dzienniczek albo zatwierdź dzień jako pełny, żeby zapotrzebowanie liczyło się dobrze.'));
    }

    // C8 brak ruchu
    final lastMove = s.lastActivity ?? s.firstUse;
    if (lastMove != null && lastMove != day && daysBetween(lastMove, day) >= 2) {
      final kcal30 = metKcal('walk', Intensity.moderate, 30, s.weightKg);
      out.add(PlannedNotif(
          NotifKind.noActivity,
          _at(day, 17 * 60 + 30),
          '${daysBetween(lastMove, day)} dni bez treningu',
          '30 min spaceru to ok. +${fmtNum(kcal30)} kcal do dzisiejszego limitu.'));
    }

    // B7 zmiana zapotrzebowania: poniedziałek
    final last = s.lastNotifiedBase;
    if (day.weekday == DateTime.monday && last != null && (s.base - last).abs() >= 50) {
      out.add(PlannedNotif(
          NotifKind.tdee,
          _at(day, 9 * 60),
          'Zapotrzebowanie: ${fmtNum(last)} → ${fmtNum(s.base)} kcal',
          'Tyle wynosi teraz utrzymanie bez treningów, wyliczone z Twojej wagi i jedzenia.',
          payload: 'weight'));
    }
  }

  // wyłączone typy, przeszłość, cisza nocna 22–7, maks. 3 dziennie wg priorytetu
  final kept = out
      .where((n) => !off.contains(n.kind.name))
      .where((n) => n.at.isAfter(s.now.add(const Duration(minutes: 1))))
      .where((n) => n.at.hour >= 7 && (n.at.hour < 22))
      .toList()
    ..sort((a, b) => a.kind.index != b.kind.index ? a.kind.index - b.kind.index : a.at.compareTo(b.at));
  final perDay = <DateTime, int>{};
  return [
    for (final n in kept)
      if ((perDay[dayOf(n.at)] = (perDay[dayOf(n.at)] ?? 0) + 1) <= 3) n,
  ]..sort((a, b) => a.at.compareTo(b.at));
}

/// Kamień milowy po zapisie wagi (na trendzie, żeby pojedynczy pomiar nie dawał fałszywych sukcesów).
String? milestone({required double start, required double before, required double after, double? goal}) {
  if (goal != null && before > goal && after <= goal) return 'Cel osiągnięty: ${fmtExact(goal)} kg 🎉';
  if (before > start - 1 && after <= start - 1) return 'Pierwszy kilogram mniej 🎉';
  final b = ((start - before) / 5).floor(), a = ((start - after) / 5).floor();
  if (a > b && a > 0) return 'Minus ${a * 5} kg od startu 🎉';
  return null;
}

// ---------- system ----------

final notifTap = ValueNotifier<String?>(null); // payload stukniętego powiadomienia (HomeShell nasłuchuje)
final _plugin = FlutterLocalNotificationsPlugin();
const _details = NotificationDetails(
  android: AndroidNotificationDetails('reminders', 'Przypomnienia',
      channelDescription: 'Posiłki, ważenie, aktywność', importance: Importance.defaultImportance, color: _accent),
);
const _accent = Color(0xFF7C6AAE);

class Notifications {
  static bool _ready = false;

  static Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher_monochrome')),
      onDidReceiveNotificationResponse: (r) => notifTap.value = r.payload,
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) notifTap.value = launch!.notificationResponse?.payload;
    _ready = true;
  }

  /// Zgoda na powiadomienia (Android 13+); pytamy raz.
  static Future<void> askPermissionOnce() async {
    if (prefs.notifAsked) return;
    prefs.notifAsked = true;
    await prefs.save();
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> show(NotifKind kind, String title, String body, {String payload = 'today'}) async {
    if (!_ready || prefs.notifOff.contains(kind.name)) return;
    await _plugin.show(
        id: kind.index * 1000 + 999, title: title, body: body, notificationDetails: _details, payload: payload);
  }

  static Future<void>? _running;

  /// Planuje wszystko od nowa (start, wznowienie, każda zmiana danych). Kolejne wywołania w trakcie są łączone.
  static Future<void> reschedule() => _running ??= _reschedule().whenComplete(() => _running = null);

  static Future<void> _reschedule() async {
    if (!_ready) return;
    try {
      final s = await collectState();
      final planned = plan(s, off: prefs.notifOff, weighMinutes: prefs.weighMinutes);
      await _plugin.cancelAllPendingNotifications(); // wyświetlonych (np. kamienia milowego) nie ruszamy
      for (final n in planned) {
        await _plugin.zonedSchedule(
          id: n.id,
          title: n.title,
          body: n.body,
          scheduledDate: tz.TZDateTime.from(n.at.toUtc(), tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: n.payload,
        );
      }
      if (prefs.lastNotifiedBase == null || DateTime.now().weekday == DateTime.monday && DateTime.now().hour >= 9) {
        prefs.lastNotifiedBase = s.base; // punkt odniesienia dla kolejnej zmiany
        await prefs.save();
      }
    } catch (e) {
      debugPrint('reschedule: $e');
    }
  }
}

/// Zbiera z bazy stan do [plan].
Future<NotifState> collectState([DateTime? now]) async {
  now ??= DateTime.now();
  final today = dayOf(now);
  final from = DateTime(today.year, today.month, today.day - 14);
  final entries = await Db.range(from, today);
  final meals = byDay(entries.where((e) => e.mealType != MealType.drink));
  final energy = await Db.estimate(now);
  final budget = await Db.budget(today, energy);
  final weights = await Db.weights();
  final acts = await Db.activities(DateTime(2020), today);
  return NotifState(
    now: now,
    meals: meals,
    complete: await Db.completeDays(from, today),
    lastWeigh: weights.lastOrNull?.day,
    lastActivity: acts.isEmpty ? null : dayOf(acts.last.startedAt),
    firstUse: await Db.firstEntryDay(),
    eatenToday: sumValues((byDay(entries)[today] ?? const []).map((e) => e.values))['kcal']!,
    goalToday: budget.goal,
    weightKg: energy.weight,
    base: energy.base,
    lastNotifiedBase: prefs.lastNotifiedBase,
  );
}
