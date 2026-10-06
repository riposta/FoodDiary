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

  Future<void> _open({Entry? entry}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => EntryEditScreen(entry: entry, day: _day)));
    _load(); // zawsze, bo edycja mogła zmienić obiekt nawet bez zapisu
  }

  String get _dayLabel {
    final today = dayOf(DateTime.now());
    if (_day == today) return 'Dziś';
    if (_day == DateTime(today.year, today.month, today.day - 1)) return 'Wczoraj';
    return DateFormat('EEE, d MMMM', 'pl_PL').format(_day);
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _day == dayOf(DateTime.now());
    final groups = <MealType, List<Entry>>{};
    for (final e in _entries) {
      (groups[e.mealType] ??= []).add(e);
    }
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add_a_photo),
        label: const Text('Dodaj'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      final d = await showDatePicker(
                          context: context, initialDate: _day, firstDate: DateTime(2020), lastDate: DateTime.now());
                      if (d != null) {
                        _day = dayOf(d);
                        _load();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_dayLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: ink)),
                    ),
                  ),
                ),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: isToday ? null : () => _shift(1)),
              ]),
            ),
            SummaryCard(total: sumValues(_entries.map((e) => e.values)), norms: prefs.norms),
            if (_entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Text('Brak wpisów. Dodaj posiłek lub napój przyciskiem poniżej 📸',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
              ),
            for (final m in MealType.values)
              if (groups[m] != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
                  child: Row(children: [
                    Text(m.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: ink)),
                    const Spacer(),
                    Text('${fmtNum(sumValues(groups[m]!.map((e) => e.values))['kcal']!)} kcal',
                        style: const TextStyle(color: Colors.black54)),
                  ]),
                ),
                for (final e in groups[m]!) _tile(e),
              ],
          ],
        ),
      ),
    );
  }

  Widget _tile(Entry e) => Dismissible(
        key: ValueKey(e.id),
        direction: DismissDirection.endToStart,
        background: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: rose, borderRadius: BorderRadius.circular(24)),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: const Icon(Icons.delete_outline, color: ink),
        ),
        confirmDismiss: (_) => confirmDelete(context, e),
        onDismissed: (_) async {
          setState(() => _entries.remove(e));
          await Db.delete(e);
        },
        child: Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            onTap: () => _open(entry: e),
            leading: Thumb(entry: e),
            title: Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text([DateFormat('HH:mm').format(e.eatenAt), if (e.portion.isNotEmpty) e.portion].join(' · ')),
            trailing: Text('${fmtNum(e.values['kcal']!)}\nkcal',
                textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600, color: ink)),
          ),
        ),
      );
}

class Thumb extends StatelessWidget {
  const Thumb({super.key, required this.entry, this.size = 56});
  final Entry entry;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: entry.photo != null
            ? Image.file(Db.photoFile(entry.photo!),
                width: size, height: size, fit: BoxFit.cover, cacheWidth: (size * 3).round(), errorBuilder: (_, __, ___) => _icon())
            : _icon(),
      );

  Widget _icon() => Container(
        width: size,
        height: size,
        color: entry.mealType == MealType.drink ? sky : peach,
        child: Icon(entry.mealType == MealType.drink ? Icons.local_cafe : Icons.restaurant, color: ink),
      );
}

/// Pierścień kcal + paski pozostałych składników z % normy.
class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.total, required this.norms, this.title});
  final Values total;
  final Values norms;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final kcalPct = total['kcal']! / norms['kcal']!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(title!, style: const TextStyle(fontWeight: FontWeight.w600, color: ink)),
            ),
          Row(children: [
            SizedBox.square(
              dimension: 120,
              child: Stack(fit: StackFit.expand, children: [
                CircularProgressIndicator(
                  value: kcalPct.clamp(0, 1).toDouble(),
                  strokeWidth: 12,
                  strokeCap: StrokeCap.round,
                  backgroundColor: cream,
                  color: kcalPct > 1 ? const Color(0xFFE8919D) : mint,
                ),
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(fmtNum(total['kcal']!), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: ink)),
                    Text('z ${fmtNum(norms['kcal']!)} kcal', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                    Text('${(kcalPct * 100).round()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(children: [
                for (final n in nutrients.skip(1)) NutrientBar(n: n, value: total[n.key]!, norm: norms[n.key]!),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }
}

class NutrientBar extends StatelessWidget {
  const NutrientBar({super.key, required this.n, required this.value, required this.norm});
  final Nutrient n;
  final double value;
  final double norm;

  @override
  Widget build(BuildContext context) {
    final pct = value / norm;
    final over = n.limit && pct > 1;
    final sub = n.label.startsWith('w tym');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(n.label, style: TextStyle(fontSize: 12, color: sub ? Colors.black54 : ink)),
          const Spacer(),
          Text('${fmtNum(value)}/${fmtNum(norm)} ${n.unit} · ${(pct * 100).round()}%',
              style: TextStyle(fontSize: 11, color: over ? const Color(0xFFC0566A) : Colors.black54)),
        ]),
        const SizedBox(height: 2),
        LinearProgressIndicator(
          value: pct.clamp(0, 1).toDouble(),
          minHeight: sub ? 4 : 7,
          borderRadius: BorderRadius.circular(8),
          backgroundColor: cream,
          color: over ? const Color(0xFFE8919D) : n.color,
        ),
      ]),
    );
  }
}
