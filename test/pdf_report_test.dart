import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_diary/db.dart';
import 'package:image/image.dart' as img;
import 'package:food_diary/models.dart';
import 'package:food_diary/pdf_report.dart';
import 'package:food_diary/prefs.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF generuje się z polskimi znakami', () async {
    Intl.defaultLocale = 'pl_PL';
    await initializeDateFormatting('pl_PL');
    // zdjęcie posiłku: prawdziwe z PDF_PHOTO albo syntetyczne
    Db.photosDir = Directory.systemTemp.createTempSync('photos').path;
    final photo = Platform.environment['PDF_PHOTO'];
    photo != null
        ? File(photo).copySync(Db.photoFile('p.jpg').path)
        : Db.photoFile('p.jpg').writeAsBytesSync(img.encodeJpg(img.Image(width: 800, height: 600)));
    Entry e(int d, int h, String name, double kcal, MealType m) => Entry(
        eatenAt: DateTime(2026, 10, d, h, 15),
        mealType: m,
        name: name,
        portion: 'ok. 300 g',
        description: d == 1 && h == 8 ? 'z mlekiem 2%' : null,
        photo: h == 13 ? 'p.jpg' : null,
        values: {for (final n in nutrients) n.key: kcal / 20, 'kcal': kcal});
    final entries = [
      e(1, 8, 'Owsianka z bananem i orzechami', 420, MealType.breakfast),
      e(1, 13, 'Żurek z jajkiem', 380, MealType.lunch),
      e(1, 16, 'Kawa z mlekiem', 45, MealType.drink),
      e(3, 19, 'Łosoś z ziemniakami i sałatką', 610, MealType.dinner),
    ];
    final pdf = await buildReport(
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 3),
      entries,
      (d) => defaultNorms(Profile(), kcal: d.day == 1 ? 2600 : 2000),
      activities: [Activity(startedAt: DateTime(2026, 10, 1, 18), type: 'run', minutes: 61, kcal: 838)],
      weights: [WeightEntry(day: DateTime(2026, 10, 1), kg: 93.4), WeightEntry(day: DateTime(2026, 10, 3), kg: 92.9)],
    );
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    final out = Platform.environment['PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(pdf);
  });
}
