import 'dart:math';

import 'package:flutter/material.dart';

import 'models.dart';
import 'prefs.dart';

const kcalPerKg = 7700.0;

// ---------- Aktywności ----------

class ActivityType {
  const ActivityType(this.key, this.label, this.icon, this.met);
  final String key;
  final String label;
  final IconData icon;
  final List<double> met; // lekka, umiarkowana, intensywna (Compendium of Physical Activities)
}

const activityTypes = [
  ActivityType('walk', 'Spacer', Icons.directions_walk_rounded, [2.8, 3.5, 4.3]),
  ActivityType('run', 'Bieganie', Icons.directions_run_rounded, [7.0, 9.8, 11.5]),
  ActivityType('bike', 'Rower', Icons.directions_bike_rounded, [4.0, 6.8, 10.0]),
  ActivityType('gym', 'Siłownia', Icons.fitness_center_rounded, [3.5, 5.0, 6.0]),
  ActivityType('swim', 'Pływanie', Icons.pool_rounded, [5.8, 7.0, 9.8]),
  ActivityType('nordic', 'Nordic walking', Icons.hiking_rounded, [4.8, 5.5, 6.8]),
  ActivityType('hiit', 'HIIT / crossfit', Icons.bolt_rounded, [6.0, 8.0, 10.0]),
  ActivityType('racket', 'Tenis / padel', Icons.sports_tennis_rounded, [5.0, 7.3, 8.0]),
  ActivityType('hike', 'Góry', Icons.terrain_rounded, [5.3, 6.0, 7.3]),
  ActivityType('yoga', 'Joga / stretching', Icons.self_improvement_rounded, [2.5, 3.0, 4.0]),
  ActivityType('other', 'Inne', Icons.sports_rounded, [3.0, 5.0, 7.0]),
];

ActivityType activityType(String key) => activityTypes.firstWhere((t) => t.key == key, orElse: () => activityTypes.last);

/// Kalorie ponad spoczynek: (MET − 1) × kg × h. Spoczynek jest już w bazie, więc go nie dublujemy.
double metKcal(String type, Intensity i, int minutes, double kg) =>
    max(0, activityType(type).met[i.index] - 1) * kg * minutes / 60;

// ---------- Waga ----------

typedef WeighIn = ({DateTime day, double kg});

/// Trend EWMA uwzględniający przerwy: po n dniach bez ważenia nowy pomiar waży 1 − 0,9ⁿ.
List<WeighIn> weightTrend(List<WeighIn> weighIns) {
  final out = <WeighIn>[];
  for (final w in weighIns) {
    if (out.isEmpty) {
      out.add(w);
      continue;
    }
    final gap = max(1, daysBetween(out.last.day, w.day));
    final a = 1 - pow(0.9, gap);
    out.add((day: w.day, kg: out.last.kg + a * (w.kg - out.last.kg)));
  }
  return out;
}

/// Ostatnia wartość trendu z dnia [day] lub wcześniejsza.
double? trendAt(List<WeighIn> trend, DateTime day) {
  double? v;
  for (final t in trend) {
    if (t.day.isAfter(day)) break;
    v = t.kg;
  }
  return v;
}

/// Nachylenie regresji liniowej w kg/dzień (odporne na brakujące dni i pojedyncze skoki).
double slopePerDay(List<WeighIn> pts) {
  final x0 = pts.first.day;
  final xs = [for (final p in pts) daysBetween(x0, p.day).toDouble()];
  final mx = xs.reduce((a, b) => a + b) / xs.length;
  final my = pts.map((p) => p.kg).reduce((a, b) => a + b) / pts.length;
  var num = 0.0, den = 0.0;
  for (var i = 0; i < pts.length; i++) {
    num += (xs[i] - mx) * (pts[i].kg - my);
    den += (xs[i] - mx) * (xs[i] - mx);
  }
  return den == 0 ? 0 : num / den;
}

int daysBetween(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

// ---------- Zapotrzebowanie ----------

typedef DayIntake = ({double kcal, int meals, bool confirmed});

class EnergyEstimate {
  const EnergyEstimate({
    required this.base,
    required this.formula,
    required this.bmr,
    required this.weight,
    this.measured,
    this.confidence = 0,
    this.okDays = 0,
    this.slopeKgWeek,
  });

  final double base; // zapotrzebowanie bez treningów, którego używamy
  final double formula; // Mifflin × codzienna aktywność
  final double bmr;
  final double weight; // trend wagi (albo waga z profilu)
  final double? measured; // z danych, przed mieszaniem
  final double confidence; // 0..1, jak bardzo ufamy pomiarowi
  final int okDays; // dni z pełnym dzienniczkiem w oknie
  final double? slopeKgWeek; // zmierzone tempo zmian wagi
}

bool isCompleteDay(DayIntake d, double formula) => d.confirmed || (d.meals >= 2 && d.kcal >= formula * .5);

/// Adaptacyjne zapotrzebowanie: jedzenie i nachylenie wagi z 28 dni (przedziałów) kończących się na ostatnim ważeniu.
EnergyEstimate estimateEnergy({
  required Profile profile,
  required List<WeighIn> weighIns, // rosnąco po dniu
  required Map<DateTime, DayIntake> intake,
  required Map<DateTime, double> activityKcal,
  required DateTime today,
}) {
  final trend = weightTrend(weighIns);
  final weight = trend.isEmpty ? profile.weight : trend.last.kg;
  final bmr = mifflin(profile, weight);
  final formula = bmr * profile.activity;
  EnergyEstimate fallback() => EnergyEstimate(base: formula, formula: formula, bmr: bmr, weight: weight);
  if (weighIns.length < 2) return fallback();

  final end = weighIns.last.day;
  final start = DateTime(end.year, end.month, end.day - 28);
  final pts = weighIns.where((w) => !w.day.isBefore(start)).toList();
  final span = pts.length < 2 ? 0 : daysBetween(pts.first.day, end);
  if (span < 10) return fallback();

  final from = pts.first.day;
  final days = [for (var i = 0; i < span; i++) DateTime(from.year, from.month, from.day + i)];
  final ok = [for (final d in days) if (intake[d] != null && isCompleteDay(intake[d]!, formula)) intake[d]!.kcal];
  if (ok.isEmpty) return fallback();

  final slope = slopePerDay(pts);
  final avgIntake = ok.reduce((a, b) => a + b) / ok.length;
  final avgActivity = days.fold(0.0, (s, d) => s + (activityKcal[d] ?? 0)) / span;
  final measured = (avgIntake - slope * kcalPerKg - avgActivity).clamp(formula * .65, formula * 1.35).toDouble();

  final stale = daysBetween(end, today);
  final freshness = stale <= 14 ? 1.0 : (1 - (stale - 14) / 14).clamp(0, 1).toDouble();
  final confidence =
      ((ok.length - 7) / 21).clamp(0, 1) * (pts.length / 6).clamp(0, 1) * freshness;

  return EnergyEstimate(
    base: confidence * measured + (1 - confidence) * formula,
    formula: formula,
    bmr: bmr,
    weight: weight,
    measured: measured,
    confidence: confidence.toDouble(),
    okDays: ok.length,
    slopeKgWeek: slope * 7,
  );
}

// ---------- Granice dnia ----------

class DayBudget {
  const DayBudget({required this.base, required this.activity, required this.deficit, required this.goal});
  final double base;
  final double activity;
  final double deficit;
  final double goal; // cel z deficytem (to pokazuje pierścień)
  double get maintenance => base + activity;
}

DayBudget dayBudget(EnergyEstimate e, double activity, {required double rateKgWeek, double? goalWeight, double? kcalOverride}) {
  final reached = goalWeight != null && e.weight <= goalWeight;
  final deficit = reached ? 0.0 : rateKgWeek * kcalPerKg / 7;
  final goal = kcalOverride != null ? kcalOverride + activity : max(e.base + activity - deficit, e.bmr);
  return DayBudget(base: e.base, activity: activity, deficit: deficit, goal: goal);
}

/// Przewidywana data osiągnięcia celu przy danym tempie (kg/tydz., dodatnie = chudnięcie).
DateTime? etaToGoal(double current, double goal, double kgPerWeek, DateTime today) {
  if (kgPerWeek <= 0.01 || current <= goal) return null;
  return DateTime(today.year, today.month, today.day + ((current - goal) / kgPerWeek * 7).ceil());
}

/// Normy dnia: kalorie z celu dnia, makro jako % tych kalorii, nadpisania mają pierwszeństwo.
Values dayNorms(Profile p, Values overrides, double goalKcal) => {
      ...defaultNorms(p, kcal: goalKcal),
      ...overrides,
      'kcal': goalKcal,
    };
