# FoodDiary v2: zdjęcia, waga, aktywność, dynamiczne zapotrzebowanie, powiadomienia

Uzupełnienie do `2026-10-06-food-diary-design.md`.

## 1. Decyzje
| Obszar | Decyzja |
|---|---|
| Zdjęcia | Do 3 na wpis, wszystkie idą do analizy. Zapisywane jest tylko zdjęcie główne (pierwsze, można zmienić) |
| Zapotrzebowanie | Adaptacyjne: jedzenie i trend wagi z ostatnich 28 dni. Przy braku danych wzór, z płynnym przejściem |
| Cel | Waga docelowa i tempo (kg/tydz.). Dzień ma dwie granice: **utrzymanie** i **cel z deficytem** |
| Aktywność | Lista typów, czas i intensywność, kcal wg MET. Opcjonalnie kcal z zegarka, które mają pierwszeństwo |
| Ważenie | Codziennie. Brakujące dni obsługuje trend (EWMA uwzględniający przerwy), a zapotrzebowanie liczy się do ostatniego ważenia |
| Powiadomienia | A (posiłki), B (waga), C (aktywność). Lokalne, planowane przy każdej zmianie danych, bez usługi w tle |
| Fitbit | Przygotowanie pod Health Connect: pola `source`/`external_id`, kcal „z urządzenia”, jeden punkt wejścia `onDataChanged()` |

## 2. Wiele zdjęć
- Ekran wpisu ma pasek z maks. 3 miniaturami. Pierwsza ma oznaczenie „w historii”. Stuknięcie w miniaturę daje do wyboru „Ustaw jako główne” albo „Usuń”.
- Galeria używa `pickMultiImage(limit: 3 - ile_jest)`, aparat dodaje po jednym zdjęciu.
- Wszystkie zdjęcia trafiają do jednej wiadomości dla AI. Prompt mówi wprost: kolejne zdjęcia mogą pokazywać tę samą potrawę albo **etykietę lub skład produktu**. Wartości z etykiety mają pierwszeństwo i są przeliczane na zjedzoną porcję.
- Do `photos/` kopiowane jest tylko zdjęcie główne, pozostałe zostają w cache. Przy edycji starego wpisu ponowna analiza używa zdjęcia głównego i nowo dodanych.

## 3. Waga
Tabela `weights`: `id, date TEXT UNIQUE (yyyy-MM-dd), kg REAL, source TEXT DEFAULT 'manual', external_id TEXT`. Jedno ważenie na dzień, kolejny wpis tego samego dnia zastępuje poprzedni.

**Trend** to EWMA z przerwami: `α_eff = 1 − (1 − 0,1)^dni_od_poprzedniego`. Pojedynczy skok (woda, sól) ledwo go rusza. Po kilku dniach przerwy kolejne ważenie ma większą wagę, bo trend „nie wie”, co działo się w tym czasie.

**Ekran „Waga”** (nowa zakładka między „Dziś” i „Statystyki”):
- u góry trend wagi, zmiana w tym tygodniu, ile zostało do celu i prognozowana data jego osiągnięcia,
- wykres: surowe ważenia jako kropki, linia trendu, przerywana linia celu, kropkowana prognoza; zakres 1M / 3M / Całość,
- karta „Zapotrzebowanie”: utrzymanie, cel, źródło (wzór / pomiar z N dni) i pewność pomiaru,
- karta „Cel”: waga docelowa i tempo (0,25 / 0,5 / 0,75 / 1 kg/tydz.),
- lista ostatnich ważeń (przesunięcie usuwa wpis) i FAB „Dodaj wagę”.

## 4. Zapotrzebowanie adaptacyjne (`lib/energy.dart`, czyste funkcje + testy)
```
okno       = 28 dni kończące się na OSTATNIM ważeniu (nie na dziś)
dni_ok     = dni zatwierdzone jako pełne LUB (≥ 2 posiłki i ≥ 50% wzoru)
I          = średnie kcal z dni_ok
A          = średnie kcal z aktywności w oknie
ΔW         = trend(koniec) − trend(początek)        [kg]
TDEE_pom   = I − ΔW·7700/dni_okna
baza_pom   = TDEE_pom − A                            (bez treningów)
baza_wzór  = Mifflin(trend wagi) × współczynnik codziennej aktywności
pewność    = clamp((dni_ok − 7) / 21, 0, 1) · [≥ 2 ważenia rozpięte na ≥ 10 dni]
baza       = pewność·clamp(baza_pom, ±35% wzoru) + (1 − pewność)·baza_wzór
```
- Gdy ważenia brakuje, okno kończy się na ostatnim ważeniu, więc pomiar nie zgaduje wagi z przyszłości. Po więcej niż 14 dniach bez ważenia pewność spada liniowo do 0 i aplikacja wraca do wzoru.
- Dni z niepełnym dzienniczkiem pomijamy przy liczeniu jedzenia, żeby zapomniany posiłek nie zaniżał zapotrzebowania.
- **Zatwierdzanie dnia:** na ekranie „Dziś” jest przycisk „Zatwierdź dzień jako pełny”. Dzięki niemu dzień z jednym posiłkiem (np. jeden posiłek dziennie) liczy się normalnie. Zatwierdzenie jest odwracalne. Tabela `day_status(date TEXT PRIMARY KEY, complete INTEGER)` jest w kopii zapasowej.
- Profil: „Aktywność” zmienia znaczenie na **„Na co dzień (bez treningów)”**: 1,2 siedząca / 1,3 lekko aktywna / 1,4 dużo chodzenia / 1,5 praca fizyczna. Treningi dochodzą osobno, więc nie liczymy ich podwójnie. Stara wartość jest mapowana na najbliższą.

## 5. Granice dnia
```
utrzymanie(dzień) = baza + aktywność(dzień)
deficyt           = tempo_kg_tydz · 7700 / 7          (0,5 kg/tydz. → 550 kcal)
cel(dzień)        = max(utrzymanie − deficyt, BMR)    (nie schodzimy poniżej BMR)
```
- Ręczne nadpisanie „Kalorie” w normach oznacza cel dnia bez treningu (np. zalecenie dietetyczki). Aktywność dalej się do niego dolicza.
- Makro jak dotąd liczymy jako % kcal celu dnia. Nadpisania mają pierwszeństwo, błonnik i sól pozostają stałe.
- Na ekranie „Dziś” pierścień pokazuje cel z deficytem, pod nim jest linia „utrzymanie 2400 kcal”. Stuknięcie otwiera rozbicie: baza 2400 + aktywność 1350 − deficyt 550 = cel 3200.
- Na wykresie w statystykach każdy słupek ma tło do wysokości celu tego dnia (`backDrawRodData`) zamiast jednej stałej linii.

## 6. Aktywności
Tabela `activities`: `id, started_at TEXT, type TEXT, duration_min INT, intensity TEXT, kcal REAL, kcal_source TEXT ('met'|'manual'|'device'), source TEXT DEFAULT 'manual', external_id TEXT, note TEXT`.

**Katalog MET** (lekka / umiarkowana / intensywna, wg Compendium of Physical Activities):

| Aktywność | MET |
|---|---|
| spacer | 2,8 / 3,5 / 4,3 |
| nordic walking | 4,8 / 5,5 / 6,8 |
| bieganie | 7,0 / 9,8 / 11,5 |
| rower | 4,0 / 6,8 / 10,0 |
| siłownia | 3,5 / 5,0 / 6,0 |
| pływanie | 5,8 / 7,0 / 9,8 |
| HIIT / crossfit | 6,0 / 8,0 / 10,0 |
| tenis / padel | 5,0 / 7,3 / 8,0 |
| turystyka górska | 5,3 / 6,0 / 7,3 |
| joga / stretching | 2,5 / 3,0 / 4,0 |
| inne | 3,0 / 5,0 / 7,0 |

- **Wzór:** `kcal = (MET − 1) × trend_wagi × godziny`. Odejmujemy 1 MET, czyli spoczynek, który jest już w bazie. Kalorie z zegarka (spalanie aktywne) zapisujemy bez zmian.
- **UI:** na ekranie „Dziś” jest sekcja „Aktywność” z listą i przyciskiem „Dodaj aktywność”. Formularz w dolnym arkuszu:
  - siatka typów,
  - czas (szybkie przyciski 15/30/45/60/90/120 albo własny),
  - intensywność,
  - kcal przeliczane na żywo,
  - opcjonalne pole „kcal z zegarka”,
  - godzina.

## 7. Powiadomienia (`lib/notifications.dart`)
- **Silnik:** czysta funkcja `plan(teraz, stan, ustawienia) → List<Plan>` (testowalna) i `reschedule()`, która kasuje i planuje na najbliższe 48 h. Wywołujemy ją przy starcie i wznowieniu aplikacji, po każdym zapisie oraz po zmianie ustawień.
- **Dlaczego treść się zgadza:** treść liczymy w chwili planowania. Jest poprawna, bo każda zmiana danych planuje powiadomienia od nowa.
- **Pluginy:**
  - `flutter_local_notifications` z harmonogramem `inexactAllowWhileIdle` (bez uprawnienia do dokładnych alarmów, dokładność kilku minut),
  - `timezone`: lokalną godzinę zamieniamy na chwilę w UTC przy każdym planowaniu, więc zmiana czasu letniego jest obsłużona,
  - przywracanie harmonogramu po restarcie telefonu (odbiornik `RECEIVE_BOOT_COMPLETED` z pluginu),
  - na Androidzie 13+ pytamy o zgodę na powiadomienia przy pierwszym włączeniu.

| # | Typ | Kiedy | Treść (przykład) |
|---|---|---|---|
| A1 | Brak posiłku | 11:00 / 15:00 / 20:30, po 14 dniach mediana Twoich godzin + 90 min; nie wysyłamy, gdy dzień jest zatwierdzony | „Nie widzę obiadu, zrób zdjęcie, zanim zapomnisz” |
| A2 | Wieczorny bilans | 19:00 | „Zostało 450 kcal do celu” / „300 kcal ponad celem, 45 min spaceru to wyrówna” |
| A3 | Luki | 9:00, gdy wczoraj zapisano mniej niż 2 posiłki i dzień nie jest zatwierdzony | „Wczoraj masz zapisany 1 posiłek. Uzupełnij albo zatwierdź dzień jako pełny” |
| B4 | Ważenie | codziennie o ustawionej godzinie (domyślnie 7:30), jeśli dziś jeszcze nie było | „Zważ się przed śniadaniem” |
| B5 | Brak ważenia | jak B4, gdy minęło ≥ 5 dni (zastępuje B4) | „5 dni bez ważenia, zapotrzebowanie przestaje się aktualizować” |
| B6 | Kamienie milowe | od razu po zapisie wagi (na podstawie trendu) | „Minus 5 kg od startu 🎉” |
| B7 | Zmiana zapotrzebowania | poniedziałek 9:00, gdy zmiana wynosi ≥ 50 kcal od ostatniej informacji | „Utrzymanie: 2450 → 2380 kcal, cel 1830 kcal” |
| C8 | Brak ruchu | 17:30, gdy przez ≥ 2 dni nie było aktywności | „Dwa dni bez treningu. 30 min spaceru to ok. +150 kcal do limitu” |
| C9 | Po treningu | SnackBar w aplikacji przy zapisie ręcznym; powiadomienie przy imporcie z Fitbita (w przyszłości) | „Bieganie 2 h: +1350 kcal, limit dziś 3750 kcal” |

**Zasady:**
- cisza nocna 22:00–7:00 (powiadomienia z tego czasu przepadają),
- najwyżej 3 dziennie, w kolejności priorytetu B4/B5 > A1 > A2 > C8 > A3 > B7,
- każdy typ ma osobny przełącznik w Ustawieniach, godzinę ważenia też da się zmienić,
- stuknięcie w powiadomienie otwiera właściwy ekran (`payload`).

## 8. Przygotowanie pod Fitbit
- **Ścieżka:** opaska → aplikacja Fitbit → **Health Connect** (waga, sesje treningowe, spalone kalorie, kroki) → nasza aplikacja przez plugin `health`.
- **Już teraz:** pola `source` i `external_id` (deduplikacja importu), `kcal_source = 'device'` z pierwszeństwem przed MET, a cała logika (zapotrzebowanie, granice dnia, powiadomienia) czyta dane z bazy niezależnie od źródła. Import będzie tylko kolejnym zapisem do tych samych tabel i wywołaniem `onDataChanged()`.
- **Na później:** okresowa synchronizacja w tle (WorkManager) i powiadomienia C9 oraz o krokach.

## 9. Inne
- **Baza:** `version: 2`, w `onUpgrade` tworzymy `weights` i `activities`. Kopia zapasowa obejmuje je automatycznie, bo kopiuje cały plik bazy.
- **PDF dla dietetyczki:** przy każdym dniu aktywności (typ, czas, kcal) i waga, jeśli była. W podsumowaniu waga na początku i końcu okresu.

## 10. Plan implementacji (każdy krok to osobny commit)
1. `energy.dart`: trend, zapotrzebowanie adaptacyjne, MET, granice dnia, plus testy przypadków brzegowych (luki w ważeniu, niepełne dni, brak danych).
2. Baza v2 (`weights`, `activities`, `day_status`) i modele, plus migracja współczynnika aktywności w profilu.
3. Wiele zdjęć (UI, prompt, zapis tylko głównego).
4. Aktywności: arkusz dodawania i sekcja na ekranie „Dziś”.
5. Granice dnia na ekranie „Dziś” (cel, utrzymanie, rozbicie) i w statystykach.
6. Ekran „Waga” (wykres, cel, karta zapotrzebowania).
7. Powiadomienia: `plan()` z testami, harmonogram, uprawnienia, ustawienia.
8. PDF (aktywności i waga), weryfikacja na urządzeniu, APK.
