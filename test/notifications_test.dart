import 'package:flutter_test/flutter_test.dart';
import 'package:food_diary/models.dart';
import 'package:food_diary/notifications.dart';
import 'package:intl/intl.dart';

final today = DateTime(2026, 10, 7); // środa
Entry meal(DateTime day, MealType m, int hour) => Entry(eatenAt: DateTime(day.year, day.month, day.day, hour), mealType: m, name: 'x');

NotifState state({
  DateTime? now,
  Map<DateTime, List<Entry>> meals = const {},
  Set<DateTime> complete = const {},
  DateTime? lastWeigh,
  DateTime? lastActivity,
  DateTime? firstUse,
  double eaten = 0,
  double goal = 2000,
  double base = 2400,
  double? lastBase,
}) =>
    NotifState(
      now: now ?? DateTime(2026, 10, 7, 6, 0),
      meals: meals,
      complete: complete,
      lastWeigh: lastWeigh,
      lastActivity: lastActivity,
      firstUse: firstUse,
      eatenToday: eaten,
      goalToday: goal,
      weightKg: 90,
      base: base,
      lastNotifiedBase: lastBase,
    );

List<PlannedNotif> onDay(List<PlannedNotif> p, DateTime d) => p.where((n) => dayOf(n.at) == d).toList();

void main() {
  setUpAll(() => Intl.defaultLocale = 'pl_PL');

  test('maks. 3 dziennie wg priorytetu, cisza nocna, bez przeszłości', () {
    final p = plan(state(firstUse: DateTime(2026, 9, 1), lastActivity: DateTime(2026, 10, 1)));
    for (final d in [today, today.add(const Duration(days: 1))]) {
      final n = onDay(p, d);
      expect(n.length, lessThanOrEqualTo(3));
      // priorytet: ważenie, potem posiłki
      expect(n.map((x) => x.kind), [NotifKind.weigh, NotifKind.meal, NotifKind.meal]);
    }
    expect(p.every((n) => n.at.hour >= 7 && n.at.hour < 22), isTrue);
    expect(p.map((n) => n.id).toSet().length, p.length); // unikalne id
  });

  test('zapisany posiłek i zatwierdzony dzień wyłączają przypomnienia o posiłkach', () {
    final logged = plan(state(meals: {today: [meal(today, MealType.breakfast, 8)]}), off: {'weigh'});
    expect(onDay(logged, today).where((n) => n.kind == NotifKind.meal).map((n) => n.title),
        ['Nie widzę obiadu', 'Nie widzę kolacji']);

    final omad = plan(state(complete: {today}), off: {'weigh'});
    expect(onDay(omad, today).where((n) => n.kind == NotifKind.meal), isEmpty);
  });

  test('ważenie: pomijane, gdy już było; po 5 dniach mocniejsze', () {
    final done = plan(state(lastWeigh: today), off: {'meal'});
    expect(onDay(done, today).where((n) => n.kind == NotifKind.weigh), isEmpty);
    expect(onDay(done, DateTime(2026, 10, 8)).single.title, 'Czas na ważenie');

    final stale = plan(state(lastWeigh: DateTime(2026, 10, 1)), off: {'meal'});
    expect(onDay(stale, today).first.title, '6 dni bez ważenia');
  });

  test('wieczorny bilans: zostało albo nadwyżka z podpowiedzią spaceru', () {
    final under = plan(state(now: DateTime(2026, 10, 7, 15), eaten: 1500, goal: 2000), off: {'weigh', 'meal'});
    expect(under.firstWhere((n) => n.kind == NotifKind.evening).title, 'Zostało 500 kcal');

    final over = plan(state(now: DateTime(2026, 10, 7, 15), eaten: 2300, goal: 2000), off: {'weigh', 'meal'});
    final e = over.firstWhere((n) => n.kind == NotifKind.evening);
    expect(e.title, '300 kcal ponad celem');
    expect(e.body, contains('min spaceru'));
  });

  test('luki we wczorajszym dniu i brak ruchu', () {
    final y = DateTime(2026, 10, 6);
    final p = plan(
      state(meals: {y: [meal(y, MealType.lunch, 13)]}, firstUse: DateTime(2026, 9, 1), lastActivity: DateTime(2026, 10, 4)),
      off: {'weigh', 'meal'},
    );
    expect(onDay(p, today).map((n) => n.kind), containsAll([NotifKind.gaps, NotifKind.noActivity]));
    expect(onDay(p, today).firstWhere((n) => n.kind == NotifKind.noActivity).title, '3 dni bez treningu');

    final confirmed = plan(state(meals: {y: [meal(y, MealType.lunch, 13)]}, complete: {y}, firstUse: DateTime(2026, 9, 1)),
        off: {'weigh', 'meal'});
    expect(onDay(confirmed, today).where((n) => n.kind == NotifKind.gaps), isEmpty);
  });

  test('pory posiłków dopasowują się do nawyków', () {
    final meals = {
      for (var i = 1; i <= 6; i++) DateTime(2026, 10, i): [meal(DateTime(2026, 10, i), MealType.lunch, 12)],
    };
    expect(mealReminderMinutes(meals, MealType.lunch), 12 * 60 + 90);
    expect(mealReminderMinutes({}, MealType.dinner), 20 * 60 + 30);
  });

  test('zmiana zapotrzebowania tylko w poniedziałek i przy 50+ kcal', () {
    final monday = DateTime(2026, 10, 12, 6);
    expect(plan(state(now: monday, base: 2380, lastBase: 2450), off: {'weigh', 'meal'}).map((n) => n.kind),
        contains(NotifKind.tdee));
    expect(plan(state(now: monday, base: 2420, lastBase: 2450), off: {'weigh', 'meal'}).map((n) => n.kind),
        isNot(contains(NotifKind.tdee)));
  });

  test('kamienie milowe na trendzie', () {
    expect(milestone(start: 100, before: 99.2, after: 98.9), 'Pierwszy kilogram mniej 🎉');
    expect(milestone(start: 100, before: 95.1, after: 94.9), 'Minus 5 kg od startu 🎉');
    expect(milestone(start: 100, before: 85.2, after: 84.9, goal: 85), 'Cel osiągnięty: 85 kg 🎉');
    expect(milestone(start: 100, before: 97, after: 96.8), isNull);
  });
}
