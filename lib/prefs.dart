import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

enum Sex {
  female('Kobieta'),
  male('Mężczyzna');

  const Sex(this.label);
  final String label;
}

/// Codzienna aktywność BEZ treningów; treningi doliczamy osobno z zakładki aktywności.
final activityLevels = {
  1.2: 'Siedząca praca, mało ruchu',
  1.3: 'Lekko aktywna (trochę chodzenia)',
  1.4: 'Dużo chodzenia, na nogach',
  1.5: 'Praca fizyczna',
};

/// Stare współczynniki (z treningami, do 1,9) mapujemy na najbliższy nowy.
double nearestActivity(double v) =>
    activityLevels.keys.reduce((a, b) => (a - v).abs() <= (b - v).abs() ? a : b);

class Profile {
  Profile({this.sex = Sex.female, this.age = 30, this.weight = 70, this.height = 170, this.activity = 1.3});
  Sex sex;
  int age;
  double weight; // kg
  double height; // cm
  double activity;
}

/// BMR wg Mifflin-St Jeor; [weight] pozwala podać trend wagi zamiast wagi z profilu.
double mifflin(Profile p, [double? weight]) =>
    10 * (weight ?? p.weight) + 6.25 * p.height - 5 * p.age + (p.sex == Sex.male ? 5 : -161);

/// Normy dla [kcal] (domyślnie wzór z profilu): makro wg proporcji energii, błonnik i sól wg WHO.
Values defaultNorms(Profile p, {double? kcal}) {
  kcal ??= mifflin(p) * p.activity;
  return {
    'kcal': kcal,
    'protein': kcal * .20 / 4,
    'fat': kcal * .30 / 9,
    'sat_fat': kcal * .10 / 9,
    'carbs': kcal * .50 / 4,
    'sugars': kcal * .10 / 4,
    'fiber': 25,
    'salt': 5,
  };
}

double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

const defaultBaseUrl = 'https://openrouter.ai/api/v1';
const defaultModel = 'deepseek/deepseek-v4.1-flash';

/// Klucz wkompilowany przy buildzie (`--dart-define-from-file=secrets.json`); ten z Ustawień ma pierwszeństwo.
const _builtInKey = String.fromEnvironment('OPENROUTER_API_KEY');

late Prefs prefs;

class Prefs {
  Profile profile = Profile();
  Values overrides = {}; // ręcznie ustawione normy (np. od dietetyczki)
  String baseUrl = defaultBaseUrl;
  String model = defaultModel;
  String apiKey = '';
  double? goalWeight;
  double rateKgWeek = 0.5;
  Set<String> notifOff = {}; // wyłączone typy powiadomień
  int weighMinutes = 7 * 60 + 30; // godzina przypomnienia o ważeniu
  double? lastNotifiedBase; // do powiadomienia o zmianie zapotrzebowania

  Values get norms => {...defaultNorms(profile), ...overrides};

  static const _secure = FlutterSecureStorage(); // szyfrowane kluczem z Android Keystore

  static Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    prefs = Prefs()
      ..profile = Profile(
        sex: Sex.values[sp.getInt('sex') ?? 0],
        age: sp.getInt('age') ?? 30,
        weight: sp.getDouble('weight') ?? 70,
        height: sp.getDouble('height') ?? 170,
        activity: nearestActivity(sp.getDouble('activity') ?? 1.3),
      )
      ..overrides = {
        for (final n in nutrients)
          if (sp.getDouble('norm_${n.key}') != null) n.key: sp.getDouble('norm_${n.key}')!,
      }
      ..baseUrl = sp.getString('base_url') ?? defaultBaseUrl
      ..model = sp.getString('model') ?? defaultModel
      ..goalWeight = sp.getDouble('goal_weight')
      ..rateKgWeek = sp.getDouble('rate_kg_week') ?? 0.5
      ..notifOff = (sp.getStringList('notif_off') ?? []).toSet()
      ..weighMinutes = sp.getInt('weigh_minutes') ?? 7 * 60 + 30
      ..lastNotifiedBase = sp.getDouble('last_notified_base')
      ..apiKey = await _secure.read(key: 'api_key') ?? '';
    if (prefs.apiKey.isEmpty) prefs.apiKey = _builtInKey;
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('sex', profile.sex.index);
    await sp.setInt('age', profile.age);
    await sp.setDouble('weight', profile.weight);
    await sp.setDouble('height', profile.height);
    await sp.setDouble('activity', profile.activity);
    for (final n in nutrients) {
      final v = overrides[n.key];
      v == null ? await sp.remove('norm_${n.key}') : await sp.setDouble('norm_${n.key}', v);
    }
    goalWeight == null ? await sp.remove('goal_weight') : await sp.setDouble('goal_weight', goalWeight!);
    await sp.setDouble('rate_kg_week', rateKgWeek);
    await sp.setStringList('notif_off', notifOff.toList());
    await sp.setInt('weigh_minutes', weighMinutes);
    lastNotifiedBase == null ? await sp.remove('last_notified_base') : await sp.setDouble('last_notified_base', lastNotifiedBase!);
    await sp.setString('base_url', baseUrl);
    await sp.setString('model', model);
    await _secure.write(key: 'api_key', value: apiKey);
  }
}
