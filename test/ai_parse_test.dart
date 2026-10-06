import 'package:flutter_test/flutter_test.dart';
import 'package:food_diary/ai.dart';
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
}
