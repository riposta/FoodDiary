# Dzienniczek

Prywatny dzienniczek żywieniowy na Androida (Flutter). Posiłki dodajesz zdjęciem lub opisem, AI (OpenRouter, API zgodne z OpenAI) szacuje kalorie i składniki, a aplikacja liczy % dziennej normy, pokazuje statystyki i generuje PDF dla dietetyczki.

Funkcje:
- posiłki ze zdjęć (do 3, np. potrawa i etykieta ze składem) i/lub opisu, analiza AI z korektą przed zapisem,
- waga z trendem, wykresem i prognozą osiągnięcia celu,
- adaptacyjne zapotrzebowanie (jedzenie + trend wagi z 28 dni, z odpornością na brakujące ważenia i literówki),
- aktywności ręcznie (MET) albo z AI (zrzut z aplikacji, zdjęcie maszyny, plik z danymi), cel dnia rośnie po treningu,
- powiadomienia: posiłki, wieczorny bilans, ważenie, brak ruchu, kamienie milowe (cisza nocna, maks. 3 dziennie),
- statystyki tygodniowe/miesięczne i dzienniczek PDF dla dietetyczki.

Projekt: `docs/plans/2026-10-06-food-diary-design.md`, `docs/plans/2026-10-06-weight-activity-notifications-design.md`.

Integracja z opaską Fitbit (planowana): Fitbit → Health Connect → aplikacja. Tabele `weights` i `activities` mają pola
`source` / `external_id`, kalorie z urządzenia (`kcal_source = 'device'`) mają pierwszeństwo, a import wystarczy zapisać
przez `Db.saveWeight` / `Db.saveActivity` (to samo przeplanuje powiadomienia).

## Build

Klucz API trzymaj w `secrets.json` (plik jest w `.gitignore`):

```json
{ "OPENROUTER_API_KEY": "sk-or-v1-..." }
```

```bash
flutter build apk --release --split-per-abi --dart-define-from-file=secrets.json
# telefon: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Bez `secrets.json` aplikacja też się zbuduje, a klucz wpiszesz w Ustawieniach. Klucz z Ustawień ma pierwszeństwo przed wkompilowanym.

Domyślny model: `deepseek/deepseek-v4.1-flash` (obsługuje obraz, rozumowanie wyłączone, odpowiedź w ok. 2 s). Można go zmienić w Ustawieniach.

## Ikona

Źródła w `assets/icon/*.svg`. PNG w `android/app/src/main/res/mipmap-*` są z nich renderowane (`rsvg-convert`).
