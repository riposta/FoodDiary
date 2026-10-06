import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../models.dart';
import '../prefs.dart';
import '../theme.dart';
import 'entry_edit.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  DateTime _day = dayOf(DateTime.now());
  List<Entry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final e = await Db.day(_day);
    if (mounted) setState(() => _entries = e);
  }

  void _shift(int days) {
    _day = DateTime(_day.year, _day.month, _day.day + days);
    _load();
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2020), lastDate: DateTime.now());
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
                    tooltip: 'Poprzedni dzień', icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _shift(-1)),
                IconButton(
                    tooltip: 'Następny dzień',
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: isToday ? null : () => _shift(1)),
              ]),
            ),
            SummaryCard(total: sumValues(_entries.map((e) => e.values)), norms: prefs.norms),
            if (_entries.isEmpty) const _EmptyDay(),
            for (final m in MealType.values)
              if (groups[m] != null) _MealGroup(meal: m, entries: groups[m]!, onOpen: (e) => _open(entry: e), onDeleted: _load),
          ],
        ),
      ),
    );
  }
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
                width: size, height: size, fit: BoxFit.cover, cacheWidth: (size * 3).round(), errorBuilder: (_, __, ___) => _icon())
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
  const SummaryCard({super.key, required this.total, required this.norms, this.title, this.average = false});
  final Values total;
  final Values norms;
  final String? title;
  final bool average; // statystyki: w środku pierścienia średnia zamiast "zostało"

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final kcal = total['kcal']!, norm = norms['kcal']!;
    final pct = kcal / norm;
    final over = kcal > norm;
    Nutrient n(String k) => nutrients.firstWhere((x) => x.key == k);

    return Card(
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
                _Stat(label: 'Dzienna norma', value: '${fmtNum(norm)} kcal'),
                const SizedBox(height: 12),
                _Stat(label: 'Realizacja', value: '${(pct * 100).round()}%', color: over ? overText : null),
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
