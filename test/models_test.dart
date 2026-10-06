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

  test('formatowanie liczb po polsku', () {
    expect(fmtNum(1996.4), '1\u00a0996');
    expect(fmtNum(99.8), '100');
    expect(fmtNum(2.5), '2,5');
    expect(fmtNum(3), '3');
    expect(fmtExact(14.5), '14,5');
  });

  test('odmiana liczebników', () {
    expect([1, 2, 5, 12, 22, 25].map((n) => plural(n, 'wpis', 'wpisy', 'wpisów')),
        ['wpis', 'wpisy', 'wpisów', 'wpisów', 'wpisy', 'wpisów']);
  });
}
