import 'package:flutter_test/flutter_test.dart';
import 'package:food_diary/energy.dart';
import 'package:food_diary/prefs.dart';

DateTime d(int i) => DateTime(2026, 9, 1 + i);

final profile = Profile(sex: Sex.male, age: 40, weight: 90, height: 180, activity: 1.2);

/// Symulacja: [days] dni, prawdziwe zapotrzebowanie bez treningów [tdee], jedzenie [eat], ważenia co dzień
/// poza dniami z [skipWeigh]. Waga spada dokładnie wg bilansu energii.
({List<WeighIn> w, Map<DateTime, DayIntake> intake, Map<DateTime, double> act}) simulate({
  int days = 28,
  double tdee = 2500,
  double eat = 2000,
  double activity = 0,
  int meals = 3,
  bool confirmed = false,
  Set<int> skipWeigh = const {},
}) {
  var kg = 90.0;
  final w = <WeighIn>[], intake = <DateTime, DayIntake>{}, act = <DateTime, double>{};
  for (var i = 0; i <= days; i++) {
    if (!skipWeigh.contains(i)) w.add((day: d(i), kg: kg));
    intake[d(i)] = (kcal: eat, meals: meals, confirmed: confirmed);
    if (activity > 0) act[d(i)] = activity;
    kg -= (tdee + activity - eat) / kcalPerKg;
  }
  return (w: w, intake: intake, act: act);
}

void main() {
  test('MET: 2 h biegu w umiarkowanym tempie, 80 kg', () {
    expect(metKcal('run', Intensity.moderate, 120, 80), closeTo((9.8 - 1) * 80 * 2, .01));
    expect(metKcal('nieznana', Intensity.light, 60, 80), closeTo((3.0 - 1) * 80, .01)); // -> "inne"
  });

  test('trend: przerwa w ważeniu zwiększa wagę nowego pomiaru', () {
    final day = weightTrend([(day: d(0), kg: 80), (day: d(1), kg: 81)]);
    expect(day.last.kg, closeTo(80.1, 1e-9));
    final gap = weightTrend([(day: d(0), kg: 80), (day: d(5), kg: 81)]);
    expect(gap.last.kg, closeTo(80 + (1 - 0.59049), 1e-9));
    expect(trendAt(gap, d(3)), 80);
    expect(trendAt(gap, d(-1)), isNull);
  });

  test('nachylenie z dziurami w ważeniach', () {
    final pts = [for (final i in [0, 1, 4, 9, 10]) (day: d(i), kg: 90 - 0.1 * i)];
    expect(slopePerDay(pts), closeTo(-0.1, 1e-9));
  });

  test('za mało danych -> wzór', () {
    final e = estimateEnergy(profile: profile, weighIns: [(day: d(0), kg: 90)], intake: {}, activityKcal: {}, today: d(0));
    expect(e.confidence, 0);
    expect(e.base, closeTo(e.formula, 1e-9));
    expect(e.formula, closeTo(mifflin(profile, 90) * 1.2, 1e-9));
  });

  test('pomiar odtwarza prawdziwe zapotrzebowanie mimo brakujących ważeń', () {
    final s = simulate(skipWeigh: {3, 4, 5, 11, 17, 18, 25});
    final e = estimateEnergy(profile: profile, weighIns: s.w, intake: s.intake, activityKcal: s.act, today: d(28));
    expect(e.confidence, 1);
    expect(e.base, closeTo(2500, 15));
    expect(e.slopeKgWeek, closeTo(-500 * 7 / kcalPerKg, .01));
  });

  test('treningi są odejmowane od bazy (nie liczymy ich podwójnie)', () {
    final s = simulate(eat: 2600, activity: 300, tdee: 2300);
    final e = estimateEnergy(profile: profile, weighIns: s.w, intake: s.intake, activityKcal: s.act, today: d(28));
    expect(e.base, closeTo(2300, 15));
  });

  test('jeden posiłek dziennie: liczy się tylko, gdy dzień zatwierdzony', () {
    final notConfirmed = simulate(eat: 1800, meals: 1);
    final a = estimateEnergy(
        profile: profile, weighIns: notConfirmed.w, intake: notConfirmed.intake, activityKcal: {}, today: d(28));
    expect(a.confidence, 0);
    expect(a.okDays, 0);

    final confirmed = simulate(eat: 1800, meals: 1, confirmed: true);
    final b = estimateEnergy(profile: profile, weighIns: confirmed.w, intake: confirmed.intake, activityKcal: {}, today: d(28));
    expect(b.okDays, 28);
    expect(b.base, closeTo(2500, 15));
  });

  test('długi brak ważenia: pewność spada do zera', () {
    final s = simulate();
    final fresh = estimateEnergy(profile: profile, weighIns: s.w, intake: s.intake, activityKcal: {}, today: d(28 + 14));
    final mid = estimateEnergy(profile: profile, weighIns: s.w, intake: s.intake, activityKcal: {}, today: d(28 + 21));
    final old = estimateEnergy(profile: profile, weighIns: s.w, intake: s.intake, activityKcal: {}, today: d(28 + 30));
    expect(fresh.confidence, 1);
    expect(mid.confidence, closeTo(.5, 1e-9));
    expect(old.confidence, 0);
    expect(old.base, closeTo(old.formula, 1e-9));
  });

  test('granice dnia: przykład z bieganiem', () {
    const e = EnergyEstimate(base: 2400, formula: 2400, bmr: 1800, weight: 95);
    final rest = dayBudget(e, 0, rateKgWeek: .5, goalWeight: 85);
    expect(rest.deficit, closeTo(550, 1e-9));
    expect(rest.goal, closeTo(1850, 1e-9));
    final run = dayBudget(e, 1350, rateKgWeek: .5, goalWeight: 85);
    expect(run.maintenance, 3750);
    expect(run.goal, closeTo(3200, 1e-9));
    // nigdy poniżej BMR
    expect(dayBudget(e, 0, rateKgWeek: 1.0).goal, 1800);
    // cel wagi osiągnięty -> utrzymanie
    expect(dayBudget(e, 0, rateKgWeek: .5, goalWeight: 96).goal, 2400);
    // zalecenie dietetyczki + trening
    expect(dayBudget(e, 300, rateKgWeek: .5, kcalOverride: 1800).goal, 2100);
  });

  test('prognoza osiągnięcia celu', () {
    expect(etaToGoal(90, 85, .5, d(0)), d(70));
    expect(etaToGoal(84, 85, .5, d(0)), isNull);
    expect(etaToGoal(90, 85, 0, d(0)), isNull);
  });

  test('normy dnia skalują makro do celu', () {
    final n = dayNorms(profile, {'fiber': 30}, 2000);
    expect(n['kcal'], 2000);
    expect(n['protein'], closeTo(2000 * .2 / 4, 1e-9));
    expect(n['fiber'], 30);
  });
}
