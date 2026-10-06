import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../energy.dart';
import '../models.dart';
import '../prefs.dart';
import '../theme.dart';
import 'activity_edit.dart';
import 'entry_edit.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  DateTime _day = dayOf(DateTime.now());
  List<Entry> _entries = [];
  List<Activity> _acts = [];
  EnergyEstimate? _energy;
  DayBudget? _budget;
  bool _complete = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final day = _day;
    final entries = await Db.day(day);
    final acts = await Db.activities(day, day);
    final energy = await Db.estimate();
    final budget = await Db.budget(day, energy);
    final complete = (await Db.completeDays(day, day)).isNotEmpty;
    if (!mounted || day != _day) return;
    setState(() {
      _entries = entries;
      _acts = acts;
      _energy = energy;
      _budget = budget;
      _complete = complete;
    });
  }

  Future<void> _openActivity([Activity? a]) async {
    final saved = await showActivitySheet(context,
        activity: a,
        day: _day,
        weightKg: _energy?.weight ?? prefs.profile.weight,
        bmr: _energy?.bmr ?? mifflin(prefs.profile));
    await _load();
    if (saved != null && mounted && _budget != null) {
      final type = activityType(saved.type).label;
      final time = saved.minutes < 60 ? '${saved.minutes} min' : '${fmtNum(saved.minutes / 60)} h';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$type $time: +${fmtNum(saved.kcal)} kcal. Cel na dziś: ${fmtNum(_budget!.goal)} kcal')));
    }
  }

  Future<void> _setComplete(bool v) async {
    await Db.setDayComplete(_day, v);
    await _load();
  }

  void _shift(int days) {
    _day = DateTime(_day.year, _day.month, _day.day + days);
    _load();
  }

  Future<void> _pickDay() async {
    final d =
        await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (d != null) {
      _day = dayOf(d);
      _load();
    }
  }

  Future<void> _open({Entry? entry}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => EntryEditScreen(entry: entry, day: _day)));
    _load(); // zawsze, bo edycja mogła zmienić obiekt nawet bez zapisu
  }

  @override
  Widget build(BuildContext context) {
    final today = dayOf(DateTime.now());
    final isToday = _day == today;
    final title = isToday
        ? 'Dziś'
        : _day == DateTime(today.year, today.month, today.day - 1)
            ? 'Wczoraj'
            : toBeginningOfSentenceCase(DateFormat('EEEE').format(_day));
    final groups = <MealType, List<Entry>>{};
    for (final e in _entries) {
      (groups[e.mealType] ??= []).add(e);
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Dodaj posiłek'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 104),
          children: [
            PageHeader(
              title,
              subtitle: DateFormat('d MMMM y').format(_day),
              onTap: _pickDay,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    tooltip: 'Poprzedni dzień',
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => _shift(-1)),
                IconButton(
                    tooltip: 'Następny dzień',
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: isToday ? null : () => _shift(1)),
              ]),
            ),
            SummaryCard(
              total: sumValues(_entries.map((e) => e.values)),
              norms: _budget == null ? prefs.norms : dayNorms(prefs.profile, prefs.overrides, _budget!.goal),
              budget: _budget,
              onTap: _budget == null ? null : () => showBudgetSheet(context, _budget!, _energy!),
            ),
            _ActivitySection(acts: _acts, onAdd: () => _openActivity(), onOpen: _openActivity),
            if (_entries.isEmpty) const _EmptyDay(),
            for (final m in MealType.values)
              if (groups[m] != null)
                _MealGroup(meal: m, entries: groups[m]!, onOpen: (e) => _open(entry: e), onDeleted: _load),
            _CompleteDay(complete: _complete, onChanged: _setComplete),
          ],
        ),
      ),
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({required this.acts, required this.onAdd, required this.onOpen});
  final List<Activity> acts;
  final VoidCallback onAdd;
  final void Function(Activity) onOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final total = acts.fold(0.0, (s, a) => s + a.kcal);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 12, 4),
        child: Row(children: [
          Text('Aktywność', style: t.titleSmall),
          if (acts.isNotEmpty) ...[const SizedBox(width: 8), Text('+${fmtNum(total)} kcal', style: t.bodySmall)],
          const Spacer(),
          TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Dodaj')),
        ]),
      ),
      if (acts.isEmpty)
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onAdd,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.directions_run_rounded, color: inkMuted),
                const SizedBox(width: 14),
                Expanded(child: Text('Trening podniesie dzisiejszy limit kalorii', style: t.bodySmall)),
              ]),
            ),
          ),
        )
      else
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final (i, a) in acts.indexed) ...[
              if (i > 0) const Divider(indent: 64),
              InkWell(
                onTap: () => onOpen(a),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
                  child: Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration:
                          BoxDecoration(color: const Color(0xFFE9F3EF), borderRadius: BorderRadius.circular(10)),
                      child: Icon(activityType(a.type).icon, size: 20, color: const Color(0xFF5E9C86)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(activityType(a.type).label, style: t.titleSmall),
                        Text(
                          '${DateFormat('HH:mm').format(a.startedAt)}, ${a.minutes} min, ${a.intensity.label.toLowerCase()}'
                          '${a.kcalSource == 'met' ? '' : ', kcal z urządzenia'}',
                          style: t.bodySmall,
                        ),
                      ]),
                    ),
                    Text('+${fmtNum(a.kcal)} kcal', style: t.titleSmall?.copyWith(color: const Color(0xFF4F8B76))),
                  ]),
                ),
              ),
            ],
          ]),
        ),
    ]);
  }
}

/// Zatwierdzenie dnia jako pełnego: wtedy liczy się do zapotrzebowania nawet z jednym posiłkiem.
class _CompleteDay extends StatelessWidget {
  const _CompleteDay({required this.complete, required this.onChanged});
  final bool complete;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: complete
          ? Row(children: [
              const SizedBox(width: 8),
              const Icon(Icons.check_circle_rounded, color: Color(0xFF5E9C86), size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('Dzień zatwierdzony jako pełny', style: t.bodyMedium)),
              TextButton(onPressed: () => onChanged(false), child: const Text('Cofnij')),
            ])
          : OutlinedButton.icon(
              onPressed: () => onChanged(true),
              icon: const Icon(Icons.task_alt_rounded),
              label: const Text('Zatwierdź dzień jako pełny'),
            ),
    );
  }
}

/// Rozbicie celu dnia: baza (wzór/pomiar) + aktywność − deficyt.
void showBudgetSheet(BuildContext context, DayBudget b, EnergyEstimate e) {
  final t = Theme.of(context).textTheme;
  Widget row(String label, String value, {String? hint, bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: strong ? t.titleMedium : t.bodyMedium),
              if (hint != null) Text(hint, style: t.bodySmall),
            ]),
          ),
          Text(value, style: strong ? t.titleMedium : t.titleSmall),
        ]),
      );
  final source = e.confidence < .05
      ? 'Z wzoru: za mało danych o wadze i jedzeniu'
      : e.confidence > .95
          ? 'Zmierzone z ${e.okDays} pełnych dni i trendu wagi'
          : 'Wzór + pomiar z ${e.okDays} pełnych dni (pewność ${(e.confidence * 100).round()}%)';
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Skąd ten limit', style: t.titleLarge),
          const SizedBox(height: 12),
          row('Zapotrzebowanie bez treningów', '${fmtNum(b.base)} kcal', hint: source),
          row('Aktywność dziś', '+${fmtNum(b.activity)} kcal'),
          const Divider(),
          row('Utrzymanie wagi', '${fmtNum(b.maintenance)} kcal', hint: 'Tyle możesz zjeść, żeby waga stała'),
          if (b.deficit > 0)
            row('Deficyt', '−${fmtNum(b.deficit)} kcal', hint: 'Tempo ${fmtNum(prefs.rateKgWeek)} kg/tydz.'),
          const Divider(),
          row('Cel na dziś', '${fmtNum(b.goal)} kcal',
              strong: true,
              hint: b.goal <= e.bmr + 1 ? 'Nie schodzimy poniżej przemiany podstawowej (${fmtNum(e.bmr)} kcal)' : null),
        ]),
      ),
    ),
  );
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 0),
      child: Column(children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(color: heatherSoft, shape: BoxShape.circle),
          child: const Icon(Icons.restaurant_rounded, color: heather, size: 28),
        ),
        const SizedBox(height: 16),
        Text('Brak wpisów w tym dniu', style: t.titleMedium),
        const SizedBox(height: 6),
        Text('Zrób zdjęcie posiłku albo go opisz, a AI policzy kalorie i składniki.',
            textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: inkMuted)),
      ]),
    );
  }
}

class _MealGroup extends StatelessWidget {
  const _MealGroup({required this.meal, required this.entries, required this.onOpen, required this.onDeleted});
  final MealType meal;
  final List<Entry> entries;
  final void Function(Entry) onOpen;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final kcal = sumValues(entries.map((e) => e.values))['kcal']!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        child: Row(children: [
          Text(meal.label, style: t.titleSmall),
          const Spacer(),
          Text('${fmtNum(kcal)} kcal', style: t.bodySmall),
        ]),
      ),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (final (i, e) in entries.indexed) ...[
            if (i > 0) const Divider(indent: 76),
            Dismissible(
              key: ValueKey(e.id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: const Color(0xFFF6E3E7),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                child: const Icon(Icons.delete_outline_rounded, color: overText),
              ),
              confirmDismiss: (_) => confirmDelete(context, e),
              onDismissed: (_) async {
                await Db.delete(e);
                onDeleted();
              },
              child: InkWell(
                onTap: () => onOpen(e),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
                  child: Row(children: [
                    Thumb(entry: e, size: 48),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                        const SizedBox(height: 2),
                        Text([DateFormat('HH:mm').format(e.eatenAt), if (e.portion.isNotEmpty) e.portion].join(', '),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(fmtNum(e.values['kcal']!), style: t.titleMedium),
                      Text('kcal', style: t.labelSmall),
                    ]),
                  ]),
                ),
              ),
            ),
          ],
        ]),
      ),
    ]);
  }
}

class Thumb extends StatelessWidget {
  const Thumb({super.key, required this.entry, this.size = 48});
  final Entry entry;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: entry.photo != null
            ? Image.file(Db.photoFile(entry.photo!),
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                errorBuilder: (_, __, ___) => _icon())
            : _icon(),
      );

  Widget _icon() {
    final drink = entry.mealType == MealType.drink;
    return Container(
      width: size,
      height: size,
      color: drink ? const Color(0xFFE8F0F9) : const Color(0xFFF7ECE8),
      child: Icon(drink ? Icons.local_cafe_outlined : Icons.restaurant_outlined,
          size: size * .45, color: drink ? const Color(0xFF6F90B8) : const Color(0xFFB07F70)),
    );
  }
}

/// Podsumowanie: pierścień kcal (zostało / ponad normę), trzy makro i kompaktowa siatka reszty.
class SummaryCard extends StatelessWidget {
  const SummaryCard(
      {super.key, required this.total, required this.norms, this.title, this.average = false, this.budget, this.onTap});
  final Values total;
  final Values norms;
  final String? title;
  final DayBudget? budget; // dzień: pokazujemy cel i utrzymanie
  final VoidCallback? onTap;
  final bool average; // statystyki: w środku pierścienia średnia zamiast "zostało"

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final kcal = total['kcal']!, norm = norms['kcal']!;
    final pct = kcal / norm;
    final over = kcal > norm;
    Nutrient n(String k) => nutrients.firstWhere((x) => x.key == k);

    final b = budget;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (title != null) ...[Text(title!, style: t.titleSmall), const SizedBox(height: 16)],
            Row(children: [
              SizedBox.square(
                dimension: 116,
                child: Stack(fit: StackFit.expand, children: [
                  CircularProgressIndicator(
                    value: pct.clamp(0, 1).toDouble(),
                    strokeWidth: 9,
                    strokeCap: StrokeCap.round,
                    backgroundColor: track,
                    color: over ? overBar : blush,
                  ),
                  Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(fmtNum(average ? kcal : (norm - kcal).abs()), style: t.titleLarge?.copyWith(fontSize: 24)),
                      Text(average ? 'kcal średnio' : (over ? 'kcal ponad normę' : 'kcal zostało'),
                          style: t.labelSmall?.copyWith(color: over && !average ? overText : inkMuted)),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Stat(label: average ? 'Średnio dziennie' : 'Zjedzone', value: '${fmtNum(kcal)} kcal'),
                  const SizedBox(height: 12),
                  _Stat(label: b == null ? 'Dzienna norma' : 'Cel na dziś', value: '${fmtNum(norm)} kcal'),
                  const SizedBox(height: 12),
                  if (b == null)
                    _Stat(label: 'Realizacja', value: '${(pct * 100).round()}%', color: over ? overText : null)
                  else
                    _Stat(
                      label: b.activity > 0 ? 'Utrzymanie (z treningiem)' : 'Utrzymanie',
                      value: '${fmtNum(b.maintenance)} kcal',
                    ),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              for (final k in ['protein', 'fat', 'carbs']) ...[
                if (k != 'protein') const SizedBox(width: 14),
                Expanded(child: _Macro(n: n(k), value: total[k]!, norm: norms[k]!)),
              ],
            ]),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Wrap(runSpacing: 10, children: [
              for (final k in ['sat_fat', 'sugars', 'fiber', 'salt'])
                FractionallySizedBox(widthFactor: .5, child: _MiniRow(n: n(k), value: total[k]!, norm: norms[k]!)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label, value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: t.labelSmall),
      Text(value, style: t.titleSmall?.copyWith(color: color)),
    ]);
  }
}

class _Macro extends StatelessWidget {
  const _Macro({required this.n, required this.value, required this.norm});
  final Nutrient n;
  final double value, norm;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pct = value / norm;
    final over = n.limit && pct > 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(n.label, style: t.labelSmall),
      const SizedBox(height: 2),
      Text.rich(TextSpan(children: [
        TextSpan(text: fmtNum(value), style: t.titleMedium),
        TextSpan(text: ' / ${fmtNum(norm)} ${n.unit}', style: t.labelSmall),
      ])),
      const SizedBox(height: 6),
      LinearProgressIndicator(
        value: pct.clamp(0, 1).toDouble(),
        minHeight: 6,
        borderRadius: BorderRadius.circular(6),
        backgroundColor: track,
        color: over ? overBar : n.color,
      ),
      const SizedBox(height: 4),
      Text('${(pct * 100).round()}%', style: t.labelSmall?.copyWith(color: over ? overText : null)),
    ]);
  }
}

class _MiniRow extends StatelessWidget {
  const _MiniRow({required this.n, required this.value, required this.norm});
  final Nutrient n;
  final double value, norm;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pct = value / norm;
    final over = n.limit && pct > 1;
    final label = switch (n.key) { 'sat_fat' => 'Tł. nasycone', 'sugars' => 'Cukry', _ => n.label };
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label, style: t.bodySmall?.copyWith(color: ink)),
          const Spacer(),
          Text('${fmtNum(value)}/${fmtNum(norm)} ${n.unit}',
              style: t.labelSmall?.copyWith(color: over ? overText : null)),
        ]),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: pct.clamp(0, 1).toDouble(),
          minHeight: 4,
          borderRadius: BorderRadius.circular(4),
          backgroundColor: track,
          color: over ? overBar : n.color,
        ),
      ]),
    );
  }
}
