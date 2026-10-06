import 'package:flutter_test/flutter_test.dart';
import 'package:food_diary/models.dart';

Entry e(DateTime t, double kcal) => Entry(eatenAt: t, mealType: MealType.snack, name: 'x', values: {'kcal': kcal});

void main() {
  test('suma i średnia dzienna po dniach z wpisami', () {
    final entries = [e(DateTime(2026, 10, 1, 8), 500), e(DateTime(2026, 10, 1, 13), 700), e(DateTime(2026, 10, 3, 9), 600)];
    expect(sumValues(entries.map((x) => x.values))['kcal'], 1800);
    expect(sumValues(entries.map((x) => x.values))['protein'], 0);
    expect(byDay(entries).keys, [DateTime(2026, 10, 1), DateTime(2026, 10, 3)]);
    expect(dailyAverage(entries)['kcal'], 900);
    expect(dailyAverage([])['kcal'], 0);
  });

  test('Entry map roundtrip', () {
    final x = Entry.fromMap(e(DateTime(2026, 10, 1, 8, 30), 123.5).toMap());
    expect(x.eatenAt, DateTime(2026, 10, 1, 8, 30));
    expect(x.values['kcal'], 123.5);
    expect(MealType.fromKey('second_breakfast'), MealType.secondBreakfast);
  });
}
