import 'package:flutter_test/flutter_test.dart';
import 'package:food_diary/prefs.dart';

void main() {
  test('Mifflin-St Jeor', () {
    // kobieta 30 l., 60 kg, 165 cm: BMR = 600 + 1031.25 - 150 - 161 = 1320.25
    final f = defaultNorms(Profile(sex: Sex.female, age: 30, weight: 60, height: 165, activity: 1.2));
    expect(f['kcal'], closeTo(1584.3, 0.1));
    expect(f['protein'], closeTo(1584.3 * .2 / 4, 0.1));
    // mężczyzna 40 l., 80 kg, 180 cm: BMR = 800 + 1125 - 200 + 5 = 1730
    final m = defaultNorms(Profile(sex: Sex.male, age: 40, weight: 80, height: 180, activity: 1.55));
    expect(m['kcal'], closeTo(2681.5, 0.1));
    expect(m['salt'], 5);
  });

  test('nadpisanie normy', () {
    final p = Prefs()..overrides = {'kcal': 1800};
    expect(p.norms['kcal'], 1800);
    expect(p.norms['fiber'], 25);
  });

  test('parseNum przyjmuje przecinek', () {
    expect(parseNum('72,5'), 72.5);
    expect(parseNum(' 1800 '), 1800);
    expect(parseNum('abc'), null);
  });
}
