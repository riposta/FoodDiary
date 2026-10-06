import 'package:flutter_test/flutter_test.dart';
import 'package:food_diary/ai.dart';
import 'package:food_diary/energy.dart';
import 'package:food_diary/models.dart';

void main() {
  final t = DateTime(2026, 10, 6, 8, 15);

  test('czysty JSON', () {
    final e = parseAiResponse(
        '{"name":"Owsianka","portion":"ok. 350 g","meal_type":"breakfast","kcal":420,"protein":14,'
        '"fat":9,"sat_fat":2.5,"carbs":70,"sugars":22,"fiber":8,"salt":0.3,"notes":"Mleko 2%."}',
        t);
    expect(e.name, 'Owsianka');
    expect(e.mealType, MealType.breakfast);
    expect(e.values['kcal'], 420);
    expect(e.values['sat_fat'], 2.5);
    expect(e.aiNotes, 'Mleko 2%.');
    expect(e.eatenAt, t);
  });

  test('JSON w markdownie, liczby jako tekst, brakujące pola', () {
    final e = parseAiResponse('Oto wynik:\n```json\n{"name":"Kawa z mlekiem","kcal":"45,5","protein":"2"}\n```', t);
    expect(e.name, 'Kawa z mlekiem');
    expect(e.values['kcal'], 45.5);
    expect(e.values['protein'], 2);
    expect(e.values['fiber'], 0);
    expect(e.mealType, MealType.breakfast); // brak meal_type -> z godziny
  });

  test('śmieci -> AiException', () {
    expect(() => parseAiResponse('nie wiem', t), throwsA(isA<AiException>()));
    expect(() => parseAiResponse('[1,2]', t), throwsA(isA<AiException>()));
  });

  group('aktywność z AI', () {
    final day = DateTime(2026, 10, 6);

    test('kalorie aktywne z aplikacji biegowej', () {
      final g = parseActivityResponse(
          '{"type":"run","minutes":62,"intensity":"vigorous","kcal":780,"kcal_kind":"active","start_time":"07:15",'
          '"distance_km":10.2,"summary":"Strava: 10,2 km, tempo 6:05/km"}',
          day: day, bmr: 1800, weightKg: 80);
      expect(g.activity.type, 'run');
      expect(g.activity.minutes, 62);
      expect(g.activity.intensity, Intensity.vigorous);
      expect(g.activity.kcal, 780);
      expect(g.activity.kcalSource, 'manual');
      expect(g.activity.startedAt, DateTime(2026, 10, 6, 7, 15));
      expect(g.summary, contains('Strava'));
    });

    test('kalorie całkowite z maszyny: odejmujemy spoczynek', () {
      final g = parseActivityResponse('{"type":"bike","minutes":40,"intensity":"moderate","kcal":420,"kcal_kind":"total"}',
          day: day, bmr: 1800, weightKg: 80);
      expect(g.activity.kcal, closeTo(420 - 1800 / 1440 * 40, 1e-9));
    });

    test('brak kalorii: liczymy z MET, nieznany typ -> inne', () {
      final g = parseActivityResponse('```json\n{"type":"zumba","minutes":"45","intensity":"x","kcal":null,"kcal_kind":"none"}\n```',
          day: day, bmr: 1800, weightKg: 80);
      expect(g.activity.type, 'other');
      expect(g.activity.intensity, Intensity.moderate);
      expect(g.activity.kcal, closeTo(metKcal('other', Intensity.moderate, 45, 80), 1e-9));
      expect(g.activity.kcalSource, 'met');
      expect(g.hasKcal, isFalse);
    });

    test('duże pliki: zostaje początek i koniec', () {
      final big = 'A' * 20000 + 'B' * 20000;
      final c = clipData(big, max: 1000);
      expect(c.startsWith('A' * 500), isTrue);
      expect(c.endsWith('B' * 500), isTrue);
      expect(clipData('krótki'), 'krótki');
    });
  });
}
