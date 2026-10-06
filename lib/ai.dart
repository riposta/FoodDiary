import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'models.dart';
import 'prefs.dart';

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _system = '''Jesteś doświadczonym dietetykiem. Na podstawie zdjęcia i/lub opisu posiłku lub napoju oszacuj wielkość porcji oraz jej wartości odżywcze.
Odpowiedz WYŁĄCZNIE jednym obiektem JSON (bez markdown, bez komentarzy) z polami:
- name: krótka nazwa po polsku,
- portion: wielkość porcji, np. "ok. 350 g" (płyny w ml),
- meal_type: jedno z: breakfast, second_breakfast, lunch, snack, dinner, drink,
- kcal, protein, fat, sat_fat, carbs, sugars, fiber, salt: liczby dla CAŁEJ porcji (kcal oraz gramy),
- notes: jedno-dwa zdania po polsku o przyjętych założeniach.
Jeśli opis podaje składniki lub ilości, mają pierwszeństwo przed zdjęciem. Same napoje (woda, kawa, herbata, sok) to meal_type "drink". Typ posiłku dobierz też na podstawie godziny.''';

/// Wyciąga dane wpisu z odpowiedzi modelu. Toleruje JSON owinięty w markdown/tekst.
Entry parseAiResponse(String content, DateTime eatenAt) {
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
  final j = decoded;
  double numOf(String k) {
    final v = j[k];
    final d = v is num ? v.toDouble() : parseNum('${v ?? ''}') ?? 0;
    return d < 0 ? 0 : d;
  }

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

Future<Entry> analyze({File? photo, String? description, required DateTime eatenAt}) async {
  if (prefs.apiKey.isEmpty) throw AiException('Ustaw klucz API w zakładce Ustawienia.');
  final desc = description?.trim() ?? '';
  final content = [
    {
      'type': 'text',
      'text': 'Godzina posiłku: ${DateFormat('HH:mm').format(eatenAt)}.\n'
          '${desc.isEmpty ? 'Brak opisu — oceń na podstawie zdjęcia.' : 'Opis: $desc'}',
    },
    if (photo != null)
      {
        'type': 'image_url',
        'image_url': {
          'url': 'data:image/${photo.path.toLowerCase().endsWith('.png') ? 'png' : 'jpeg'};base64,'
              '${base64Encode(await photo.readAsBytes())}',
        },
      },
  ];

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
            'messages': [
              {'role': 'system', 'content': _system},
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
  return parseAiResponse(text, eatenAt);
}
