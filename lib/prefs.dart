import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

enum Sex {
  female('Kobieta'),
  male('Mężczyzna');

  const Sex(this.label);
  final String label;
}

final activityLevels = {
  1.2: 'Siedzący tryb życia',
  1.375: 'Lekka aktywność (1–3×/tydz.)',
  1.55: 'Umiarkowana (3–5×/tydz.)',
  1.725: 'Duża (6–7×/tydz.)',
  1.9: 'Bardzo duża / praca fizyczna',
};

class Profile {
  Profile({this.sex = Sex.female, this.age = 30, this.weight = 70, this.height = 170, this.activity = 1.375});
  Sex sex;
  int age;
  double weight; // kg
  double height; // cm
  double activity;
}

/// Mifflin-St Jeor × aktywność; makro wg proporcji energii, błonnik i sól wg WHO.
Values defaultNorms(Profile p) {
  final bmr = 10 * p.weight + 6.25 * p.height - 5 * p.age + (p.sex == Sex.male ? 5 : -161);
  final kcal = bmr * p.activity;
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
const defaultModel = 'google/gemini-3.8-flash';

late Prefs prefs;

class Prefs {
  Profile profile = Profile();
  Values overrides = {}; // ręcznie ustawione normy (np. od dietetyczki)
  String baseUrl = defaultBaseUrl;
  String model = defaultModel;
  String apiKey = '';

  Values get norms => {...defaultNorms(profile), ...overrides};

  static const _secure = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  static Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    prefs = Prefs()
      ..profile = Profile(
        sex: Sex.values[sp.getInt('sex') ?? 0],
        age: sp.getInt('age') ?? 30,
        weight: sp.getDouble('weight') ?? 70,
        height: sp.getDouble('height') ?? 170,
        activity: sp.getDouble('activity') ?? 1.375,
      )
      ..overrides = {
        for (final n in nutrients)
          if (sp.getDouble('norm_${n.key}') != null) n.key: sp.getDouble('norm_${n.key}')!,
      }
      ..baseUrl = sp.getString('base_url') ?? defaultBaseUrl
      ..model = sp.getString('model') ?? defaultModel
      ..apiKey = await _secure.read(key: 'api_key') ?? '';
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
    await sp.setString('base_url', baseUrl);
    await sp.setString('model', model);
    await _secure.write(key: 'api_key', value: apiKey);
  }
}
