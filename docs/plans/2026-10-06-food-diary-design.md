# FoodDiary — SDD i plan implementacji

## 1. Cel
Prywatna aplikacja na Androida do prowadzenia dzienniczka żywieniowego. Posiłek lub napój dodajesz zdjęciem i/lub opisem, a model AI (OpenRouter, API zgodne z OpenAI) szacuje kaloryczność i wartości odżywcze. Aplikacja pokazuje podsumowanie dnia, wykresy tygodniowe i miesięczne oraz generuje do druku dzienniczek PDF dla dietetyczki.

## 2. Decyzje
| Obszar | Decyzja |
|---|---|
| Technologia | Flutter (Dart), tylko Android, minSdk 24, Material 3 |
| Dane | Lokalnie: SQLite (`sqflite`) + zdjęcia w katalogu aplikacji. Backup: eksport i import ZIP |
| AI | `POST {baseUrl}/chat/completions`. Base URL, klucz i ID modelu (z obsługą obrazu) ustawiane w ustawieniach |
| Wpis | Wymagane zdjęcie LUB opis. Zdjęcie z aparatu albo z galerii |
| Przepływ | AI → podgląd z edycją → zapis. Edycja i ponowna analiza możliwe później |
| Składniki | kcal, białko, tłuszcze, w tym nasycone, węglowodany, w tym cukry, błonnik, sól |
| Normy | Profil (Mifflin-St Jeor × aktywność). Każdą normę można nadpisać ręcznie |
| Raport | PDF: dzień po dniu, posiłki z miniaturą, suma dnia i % normy, na końcu średnie z okresu. Systemowe okno druku i udostępniania |
| Język UI | polski |

**% normy liczy aplikacja, nie AI.** Model zwraca tylko wartości bezwzględne. Procenty wylicza kod z norm z profilu, dzięki czemu są zawsze spójne i przeliczają się po zmianie normy.

## 3. Pakiety
`sqflite`, `path_provider`, `image_picker` (z `maxWidth: 1280` i `imageQuality: 80`, bez osobnej biblioteki do kompresji), `http`, `flutter_secure_storage` (klucz API), `shared_preferences` (profil i normy), `fl_chart`, `pdf` + `printing`, `intl`, `archive`, `share_plus`, `file_picker` (import backupu).
Stan aplikacji: `ChangeNotifier` + `setState`, bez Riverpoda i Bloca.

## 4. Model danych
Tabela `entries`:
```
id INTEGER PK, eaten_at TEXT (ISO, lokalny czas), meal_type TEXT,
name TEXT, portion TEXT, description TEXT NULL, photo_path TEXT NULL,
kcal REAL, protein REAL, fat REAL, sat_fat REAL, carbs REAL, sugars REAL,
fiber REAL, salt REAL, ai_notes TEXT NULL
```
`meal_type`: `breakfast | second_breakfast | lunch | snack | dinner | drink`.
Ustawienia (prefs): płeć, wiek, waga, wzrost, aktywność (1.2–1.9) oraz opcjonalne nadpisania każdej normy. Klucz API trzymany w secure storage.

**Domyślne normy:** kcal = BMR × aktywność. Z energii: białko 20%, tłuszcz 30%, węglowodany 50%. Tłuszcze nasycone poniżej 10% kcal, cukry poniżej 10% kcal. Błonnik 25 g, sól 5 g (wg WHO).

## 5. Kontrakt AI
Request: `model`, `response_format: {type: json_object}` oraz wiadomości:
- system: rola dietetyka i wymóg zwrócenia wyłącznie JSON według schematu, nazwy po polsku. Dla płynów obowiązuje porcja w ml.
- user: opis (jeśli jest), godzina posiłku oraz `image_url` z obrazem jako `data:image/jpeg;base64,...` (jeśli jest zdjęcie).

Odpowiedź (JSON):
```json
{"name":"Owsianka z bananem","portion":"ok. 350 g","meal_type":"breakfast",
 "kcal":420,"protein":14,"fat":9,"sat_fat":2.5,"carbs":70,"sugars":22,
 "fiber":8,"salt":0.3,"notes":"Założono mleko 2%."}
```
Parser najpierw próbuje `jsonDecode`, a jeśli to się nie uda, wycina pierwszy blok `{...}`, bo nie każdy model respektuje `response_format`. Brakujące liczby → 0, a pole jest oznaczone do sprawdzenia. Timeout wynosi 60 s.

## 6. Ekrany
1. **Dziś** (start): strzałki do zmiany dnia i wybór daty. Na górze karta podsumowania: pierścień kcal (spożyte/norma) i paski makro z %. Pod nią lista posiłków pogrupowana po `meal_type`, z miniaturą i kcal. Tap otwiera edycję, swipe usuwa (z potwierdzeniem). FAB „+”.
2. **Dodaj/edytuj**: przyciski Aparat/Galeria, podgląd zdjęcia, pole opisu, data i godzina (domyślnie teraz), „Analizuj”. Następnie formularz z polami od AI (do edycji), a w nim przyciski „Zapisz” i „Analizuj ponownie”. Można też zapisać wpis ręcznie, bez AI.
3. **Statystyki**: przełącznik Tydzień/Miesiąc. Słupki kcal na dzień z linią normy, średnie dzienne makro i % normy, liczba dni z wpisami.
4. **Dzienniczek PDF**: zakres dat (`showDateRangePicker`) i przycisk „Generuj”. Generowanie wywołuje `Printing.layoutPdf` (druk lub zapis do PDF), obok jest przycisk „Udostępnij” (`Printing.sharePdf`).
5. **Ustawienia**: profil i wyliczone normy z możliwością nadpisania, ustawienia API (base URL, klucz, model, „Testuj połączenie”) oraz backup (Eksportuj ZIP / Importuj ZIP).

Nawigacja: `NavigationBar` z zakładkami Dziś / Statystyki / Raport / Ustawienia.

**Paleta pastelowa:** tło `#FFF8F0` (krem), primary `#B8E0D2` (mięta), białko `#D6C8F0` (lawenda), tłuszcz `#FFD6BA` (brzoskwinia), węglowodany `#BFD7EA` (błękit), akcent i przekroczenie normy `#F7C5CC` (róż). Zaokrąglone karty (radius 24) i miękkie cienie.

## 7. Błędy
- Brak klucza: zamiast analizy pokazuje się baner z linkiem do Ustawień.
- Błąd sieci, timeout, 401 albo 429: SnackBar z czytelnym komunikatem. Formularz zachowuje zdjęcie i opis, więc można ponowić albo wypełnić ręcznie. Nic nie ginie.
- Nieparsowalna odpowiedź: komunikat i przycisk „Ponów”. Surowa odpowiedź trafia do logów debug.
- Import backupu: przed nadpisaniem bazy wymagane jest potwierdzenie. Import odbywa się do katalogu tymczasowego, a dopiero potem następuje podmiana, więc uszkodzony ZIP niczego nie psuje.

## 8. Testy
- Unit: parser odpowiedzi AI (czysty JSON, JSON w markdownie, brakujące pola), wyliczanie norm (Mifflin) oraz agregacja dnia i okresu z %.
- Ręcznie na emulatorze lub telefonie: dodanie wpisu ze zdjęciem, edycja, wykresy, PDF, eksport i import.

## 9. Struktura (płasko, mało plików)
```
lib/
  main.dart          // app, motyw, nawigacja
  models.dart        // Entry, Norms, Profile
  db.dart            // sqflite CRUD + agregacje
  ai.dart            // klient OpenRouter + parser
  prefs.dart         // profil, normy (Mifflin), ustawienia API
  screens/today.dart, entry_edit.dart, stats.dart, report.dart, settings.dart
  pdf_report.dart    // budowa PDF
  backup.dart        // eksport/import ZIP
test/
  ai_parse_test.dart, norms_test.dart
```

## 10. Plan implementacji
1. `flutter create --org pl.fooddiary --platforms android food_diary`, pakiety, motyw pastelowy, szkielet nawigacji.
2. `models.dart` + `db.dart` (schemat, CRUD, sumy dzienne i z zakresu).
3. `prefs.dart` + ekran Ustawień (profil, normy, API, secure storage) oraz test norm.
4. `ai.dart` (request, parser) i jego test, plus „Testuj połączenie”.
5. Ekran Dodaj/edytuj (image_picker, analiza, formularz, zapis zdjęcia do katalogu aplikacji).
6. Ekran Dziś (podsumowanie, lista, nawigacja po dniach, usuwanie).
7. Statystyki (`fl_chart`, tydzień i miesiąc).
8. Raport PDF (`pdf` + `printing`, miniatury, sumy, średnie).
9. Backup ZIP (eksport przez share, import przez file_picker).
10. `flutter analyze`, testy, build `flutter build apk --release` i instalacja na telefonie.

**Poza zakresem (YAGNI):** konta i synchronizacja, przypomnienia, baza produktów i kody kreskowe, cele wagowe, iOS. Można je dodać później, jeśli zajdzie potrzeba.
