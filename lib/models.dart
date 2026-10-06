import 'dart:ui';

import 'package:intl/intl.dart';

import 'theme.dart';

enum MealType {
  breakfast('breakfast', 'Śniadanie'),
  secondBreakfast('second_breakfast', 'II śniadanie'),
  lunch('lunch', 'Obiad'),
  snack('snack', 'Przekąska'),
  dinner('dinner', 'Kolacja'),
  drink('drink', 'Napój');

  const MealType(this.key, this.label);
  final String key;
  final String label;

  static MealType fromKey(String? k) => values.firstWhere((m) => m.key == k, orElse: () => snack);

  /// Zgadywanie typu posiłku po godzinie, gdy AI nie poda.
  static MealType forTime(DateTime t) => switch (t.hour) {
        < 10 => breakfast,
        < 12 => secondBreakfast,
        < 16 => lunch,
        < 18 => snack,
        _ => dinner,
      };
}

class Nutrient {
  const Nutrient(this.key, this.label, this.unit, this.color, {this.limit = true});
  final String key;
  final String label;
  final String unit;
  final Color color;
  final bool limit; // przekroczenie normy = źle (dla białka i błonnika nie)
}

/// Kolejność = kolejność w UI, PDF, bazie i JSON od AI.
const nutrients = [
  Nutrient('kcal', 'Kalorie', 'kcal', blush),
  Nutrient('protein', 'Białko', 'g', lilac, limit: false),
  Nutrient('fat', 'Tłuszcze', 'g', clay),
  Nutrient('sat_fat', 'w tym nasycone', 'g', clay),
  Nutrient('carbs', 'Węglowodany', 'g', powder),
  Nutrient('sugars', 'w tym cukry', 'g', powder),
  Nutrient('fiber', 'Błonnik', 'g', sage, limit: false),
  Nutrient('salt', 'Sól', 'g', slate),
];

typedef Values = Map<String, double>;

Values sumValues(Iterable<Values> items) => {
      for (final n in nutrients) n.key: items.fold(0.0, (s, v) => s + (v[n.key] ?? 0)),
    };

class Entry {
  Entry({
    this.id,
    required this.eatenAt,
    required this.mealType,
    required this.name,
    this.portion = '',
    this.description,
    this.photo,
    this.aiNotes,
    Values? values,
  }) : values = values ?? {for (final n in nutrients) n.key: 0.0};

  int? id;
  DateTime eatenAt;
  MealType mealType;
  String name;
  String portion;
  String? description;
  String? photo; // nazwa pliku w katalogu zdjęć aplikacji
  String? aiNotes;
  Values values;

  Map<String, Object?> toMap() => {
        'id': id,
        'eaten_at': eatenAt.toIso8601String(),
        'meal_type': mealType.key,
        'name': name,
        'portion': portion,
        'description': description,
        'photo_path': photo,
        'ai_notes': aiNotes,
        ...values,
      };

  factory Entry.fromMap(Map<String, Object?> m) => Entry(
        id: m['id'] as int?,
        eatenAt: DateTime.parse(m['eaten_at'] as String),
        mealType: MealType.fromKey(m['meal_type'] as String?),
        name: m['name'] as String,
        portion: (m['portion'] as String?) ?? '',
        description: m['description'] as String?,
        photo: m['photo_path'] as String?,
        aiNotes: m['ai_notes'] as String?,
        values: {for (final n in nutrients) n.key: ((m[n.key] as num?) ?? 0).toDouble()},
      );
}

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Wpisy pogrupowane po dniu (klucze rosnąco).
Map<DateTime, List<Entry>> byDay(Iterable<Entry> entries) {
  final out = <DateTime, List<Entry>>{};
  for (final e in entries) {
    (out[dayOf(e.eatenAt)] ??= []).add(e);
  }
  return Map.fromEntries(out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
}

/// Średnia dzienna liczona po dniach, w których są wpisy.
Values dailyAverage(Iterable<Entry> entries) {
  final days = byDay(entries);
  if (days.isEmpty) return sumValues(const []);
  final total = sumValues(entries.map((e) => e.values));
  return total.map((k, v) => MapEntry(k, v / days.length));
}

final _whole = NumberFormat('#,##0', 'pl_PL'), _oneDecimal = NumberFormat('0.#', 'pl_PL');

/// Do wyświetlania: od 10 w górę liczby całkowite ("1 996"), poniżej jedno miejsce po przecinku ("2,5").
String fmtNum(double v) => (v.abs() >= 10 ? _whole : _oneDecimal).format(v);

/// Polska odmiana: plural(1,'wpis','wpisy','wpisów') -> wpis, 3 -> wpisy, 5 -> wpisów, 22 -> wpisy.
String plural(int n, String one, String few, String many) {
  if (n == 1) return one;
  final d = n % 10, dd = n % 100;
  return d >= 2 && d <= 4 && (dd < 12 || dd > 14) ? few : many;
}

/// Do pól edycji: bez zaokrąglania do całości ("14,5").
String fmtExact(double v) => _oneDecimal.format(v);
