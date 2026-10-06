# Dzienniczek

Prywatny dzienniczek żywieniowy na Androida (Flutter). Posiłki dodajesz zdjęciem lub opisem, AI (OpenRouter, API zgodne z OpenAI) szacuje kalorie i składniki, a aplikacja liczy % dziennej normy, pokazuje statystyki i generuje PDF dla dietetyczki.

Projekt i plan: `docs/plans/2026-10-06-food-diary-design.md`.

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
