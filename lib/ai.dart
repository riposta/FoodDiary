import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'energy.dart';
import 'models.dart';
import 'prefs.dart';

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _system =
    '''Jesteś doświadczonym dietetykiem. Na podstawie zdjęcia i/lub opisu posiłku lub napoju oszacuj wielkość porcji oraz jej wartości odżywcze.
Odpowiedz WYŁĄCZNIE jednym obiektem JSON (bez markdown, bez komentarzy) z polami:
- name: krótka nazwa po polsku,
- portion: wielkość porcji, np. "ok. 350 g" (płyny w ml),
- meal_type: jedno z: breakfast, second_breakfast, lunch, snack, dinner, drink,
- kcal, protein, fat, sat_fat, carbs, sugars, fiber, salt: liczby dla CAŁEJ porcji (kcal oraz gramy),
- notes: jedno-dwa zdania po polsku o przyjętych założeniach.
Możesz dostać do 3 zdjęć tego samego posiłku: potrawę z różnych stron i/lub etykietę produktu (skład, tabela wartości odżywczych). Wartości z etykiety mają pierwszeństwo, przelicz je na zjedzoną porcję.
Jeśli opis podaje składniki lub ilości, mają pierwszeństwo przed zdjęciem. Same napoje (woda, kawa, herbata, sok) to meal_type "drink". Typ posiłku dobierz też na podstawie godziny.''';

/// Obiekt JSON z odpowiedzi modelu; toleruje JSON owinięty w markdown/tekst.
Map<dynamic, dynamic> _decodeObject(String content) {
  Object? decoded;
  try {
    decoded = jsonDecode(content);
  } catch (_) {
    final m = RegExp(r'\{[\s\S]*\}').firstMatch(content);
    if (m != null) {
      try {
        decoded = jsonDecode(m[0]!);
      } catch (_) {}
    }
  }
  if (decoded is! Map) {
    debugPrint('AI raw response: $content');
    throw AiException('Model zwrócił odpowiedź w nieoczekiwanym formacie. Spróbuj ponownie.');
  }
  return decoded;
}

double? _num(Object? v) {
  final d = v is num ? v.toDouble() : parseNum('${v ?? ''}');
  return d == null || d < 0 ? null : d;
}

/// Wyciąga dane wpisu z odpowiedzi modelu.
Entry parseAiResponse(String content, DateTime eatenAt) {
  final j = _decodeObject(content);
  double numOf(String k) => _num(j[k]) ?? 0;

  final name = '${j['name'] ?? ''}'.trim();
  return Entry(
    eatenAt: eatenAt,
    mealType: j['meal_type'] == null ? MealType.forTime(eatenAt) : MealType.fromKey('${j['meal_type']}'),
    name: name.isEmpty ? 'Posiłek' : name,
    portion: '${j['portion'] ?? ''}'.trim(),
    aiNotes: j['notes']?.toString(),
    values: {for (final n in nutrients) n.key: numOf(n.key)},
  );
}

Future<Entry> analyze({List<File> photos = const [], String? description, required DateTime eatenAt}) async {
  final desc = description?.trim() ?? '';
  final content = [
    {
      'type': 'text',
      'text': 'Godzina posiłku: ${DateFormat('HH:mm').format(eatenAt)}.\n'
          '${desc.isEmpty ? 'Brak opisu — oceń na podstawie zdjęć.' : 'Opis: $desc'}',
    },
    for (final photo in photos) await _image(photo),
  ];

  return parseAiResponse(await _complete(_system, content), eatenAt);
}

Future<Map<String, Object>> _image(File f) async => {
      'type': 'image_url',
      'image_url': {
        'url': 'data:image/${f.path.toLowerCase().endsWith('.png') ? 'png' : 'jpeg'};base64,'
            '${base64Encode(await f.readAsBytes())}',
      },
    };

/// Wysyła zapytanie chat/completions i zwraca treść odpowiedzi modelu.
Future<String> _complete(String system, List<Object> content) async {
  if (prefs.apiKey.isEmpty) throw AiException('Ustaw klucz API w zakładce Ustawienia.');
  final http.Response res;
  try {
    res = await http
        .post(
          Uri.parse('${prefs.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions'),
          headers: {
            'Authorization': 'Bearer ${prefs.apiKey}',
            'Content-Type': 'application/json',
            'X-Title': 'Dzienniczek',
          },
          body: jsonEncode({
            'model': prefs.model,
            'temperature': 0.2,
            'response_format': {'type': 'json_object'},
            // bez "myślenia" odpowiedź przychodzi w ~2 s zamiast ~25 s, przy podobnych wartościach
            if (prefs.baseUrl.contains('openrouter.ai')) 'reasoning': {'enabled': false},
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': content},
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));
  } on TimeoutException {
    throw AiException('Przekroczono czas oczekiwania (60 s). Spróbuj ponownie.');
  } on SocketException {
    throw AiException('Brak połączenia z internetem.');
  } on http.ClientException catch (e) {
    throw AiException('Błąd połączenia: ${e.message}');
  } on FormatException {
    throw AiException('Nieprawidłowy Base URL w Ustawieniach.');
  }

  Map<String, dynamic>? body;
  try {
    body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  } catch (_) {}
  final apiError = body?['error'];
  if (res.statusCode != 200 || apiError != null) {
    final msg = apiError is Map ? apiError['message'] : apiError ?? res.reasonPhrase;
    throw AiException(switch (res.statusCode) {
      401 => 'Nieprawidłowy klucz API.',
      402 => 'Brak środków na koncie OpenRouter.',
      429 => 'Za dużo zapytań — spróbuj za chwilę.',
      _ => 'Błąd API (${res.statusCode}): $msg',
    });
  }
  final text = body?['choices']?[0]?['message']?['content'];
  if (text is! String) throw AiException('Pusta odpowiedź modelu. Spróbuj ponownie.');
  return text;
}

// ---------- aktywności ----------

final _activitySystem =
    '''Jesteś trenerem i analitykiem danych sportowych. Dostajesz zrzuty ekranu z aplikacji sportowych (Strava, Garmin, Fitbit, Samsung Health, Apple Fitness…), zdjęcia wyświetlaczy maszyn (bieżnia, orbitrek, rower stacjonarny, wioślarz, stepper), raporty albo surowe dane z urządzeń (CSV, GPX, TCX, JSON, tekst) i/lub opis. Rozpoznaj JEDNĄ aktywność (jeśli jest ich kilka, wybierz główną i wspomnij o tym w notatce).
Odpowiedz WYŁĄCZNIE jednym obiektem JSON z polami:
- type: jedno z: ${activityTypes.map((t) => '${t.key} (${t.label})').join(', ')},
- minutes: czas trwania w minutach (liczba całkowita),
- intensity: light, moderate albo vigorous (na podstawie tempa, tętna, mocy, prędkości lub opisu),
- kcal: kalorie odczytane z danych albo null, gdy ich nie ma,
- kcal_kind: "active" (kalorie aktywne / ponad spoczynek), "total" (całkowite, np. z wyświetlacza maszyny) albo "none",
- start_time: godzina rozpoczęcia "HH:MM" albo null,
- distance_km: dystans albo null,
- avg_hr: średnie tętno albo null,
- summary: jedno zdanie po polsku, co odczytałeś (dystans, tempo, tętno, źródło).
Nie zgaduj kalorii, jeśli ich nie widać: wtedy kcal = null, kcal_kind = "none".''';

typedef ActivityGuess = ({Activity activity, String summary, bool hasKcal});

/// Aktywność z odpowiedzi modelu. Kalorie całkowite zamieniamy na aktywne (odejmujemy spoczynek ≈ BMR),
/// a gdy ich brak, liczymy z MET.
ActivityGuess parseActivityResponse(String content,
    {required DateTime day, required double bmr, required double weightKg}) {
  final j = _decodeObject(content);
  final type = activityTypes.any((t) => t.key == j['type']) ? j['type'] as String : 'other';
  final minutes = (_num(j['minutes']) ?? 0).round();
  final intensity = Intensity.values.firstWhere((i) => i.name == j['intensity'], orElse: () => Intensity.moderate);
  final hm = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch('${j['start_time'] ?? ''}');
  final now = DateTime.now();
  final start = hm == null
      ? DateTime(day.year, day.month, day.day, now.hour, now.minute)
      : DateTime(day.year, day.month, day.day, int.parse(hm[1]!).clamp(0, 23), int.parse(hm[2]!).clamp(0, 59));

  final reported = _num(j['kcal']);
  final kind = '${j['kcal_kind'] ?? 'none'}';
  double? kcal;
  if (reported != null && reported > 0 && kind != 'none') {
    kcal = kind == 'total' ? reported - bmr / 1440 * minutes : reported;
    if (kcal < 0) kcal = 0;
  }
  final a = Activity(
    startedAt: start,
    type: type,
    minutes: minutes,
    intensity: intensity,
    kcal: kcal ?? metKcal(type, intensity, minutes, weightKg),
    kcalSource: kcal == null ? 'met' : 'manual',
    note: '${j['summary'] ?? ''}'.trim().isEmpty ? null : '${j['summary']}'.trim(),
  );
  return (activity: a, summary: a.note ?? '', hasKcal: kcal != null);
}

/// Pliki tekstowe (CSV, GPX, TCX, JSON, TXT): duże przycinamy, zostawiając początek i koniec (start i meta).
String clipData(String text, {int max = 30000}) => text.length <= max
    ? text
    : '${text.substring(0, max ~/ 2)}\n…[pominięto ${text.length - max} znaków]…\n${text.substring(text.length - max ~/ 2)}';

Future<ActivityGuess> analyzeActivity({
  List<File> photos = const [],
  String? text,
  String? fileName,
  String? fileText,
  required DateTime day,
  required double bmr,
  required double weightKg,
}) async {
  final t = text?.trim() ?? '';
  final content = <Object>[
    {
      'type': 'text',
      'text': [
        'Data aktywności: ${DateFormat('yyyy-MM-dd').format(day)}.',
        if (t.isNotEmpty) 'Opis / dane od użytkownika:\n$t',
        if (fileText != null) 'Plik "${fileName ?? 'dane'}":\n${clipData(fileText)}',
        if (t.isEmpty && fileText == null) 'Brak opisu, oceń na podstawie zdjęć.',
      ].join('\n\n'),
    },
    for (final p in photos) await _image(p),
  ];
  return parseActivityResponse(await _complete(_activitySystem, content), day: day, bmr: bmr, weightKg: weightKg);
}
