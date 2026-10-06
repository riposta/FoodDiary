import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../db.dart';
import '../energy.dart';
import '../models.dart';
import '../pdf_report.dart';
import '../prefs.dart';
import '../theme.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late DateTimeRange _range;
  bool _busy = false;
  (int entries, int days)? _count;

  @override
  void initState() {
    super.initState();
    _setLast(7);
  }

  void _setLast(int days) {
    final t = dayOf(DateTime.now());
    _setRange(DateTimeRange(start: DateTime(t.year, t.month, t.day - days + 1), end: t));
  }

  Future<void> _setRange(DateTimeRange r) async {
    setState(() => (_range = r, _count = null));
    final e = await Db.range(r.start, r.end);
    if (mounted && _range == r) setState(() => _count = (e.length, byDay(e).length));
  }

  int get _rangeDays => DateUtils.dateOnly(_range.end).difference(DateUtils.dateOnly(_range.start)).inHours ~/ 24 + 1;

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String get _fileName =>
      'dzienniczek_${DateFormat('yyyy-MM-dd').format(_range.start)}_${DateFormat('yyyy-MM-dd').format(_range.end)}.pdf';

  Future<void> _run(Future<void> Function(Uint8List pdf) action) async {
    setState(() => _busy = true);
    try {
      final from = _range.start, to = _range.end;
      final entries = await Db.range(from, to);
      final activities = await Db.activities(from, to);
      final energy = await Db.estimate();
      final actKcal = <DateTime, double>{};
      for (final a in activities) {
        actKcal.update(dayOf(a.startedAt), (v) => v + a.kcal, ifAbsent: () => a.kcal);
      }
      Values normsFor(DateTime d) => dayNorms(
            prefs.profile,
            prefs.overrides,
            dayBudget(energy, actKcal[d] ?? 0,
                    rateKgWeek: prefs.rateKgWeek, goalWeight: prefs.goalWeight, kcalOverride: prefs.overrides['kcal'])
                .goal,
          );
      final pdf = await buildReport(from, to, entries, normsFor, activities: activities, weights: await Db.weights());
      await action(pdf);
    } catch (e) {
      _snack('Nie udało się przygotować PDF: ${e is PlatformException ? e.message : e}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final f = DateFormat('d MMM y');
    final c = _count;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const PageHeader('Dzienniczek', subtitle: 'Rozpiska posiłków dzień po dniu dla dietetyczki'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () async {
              final r = await showDateRangePicker(
                  context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: _range);
              if (r != null) _setRange(r);
            },
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: heatherSoft, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.date_range_outlined, color: heather),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${f.format(_range.start)} – ${f.format(_range.end)}', style: t.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      c == null
                          ? 'Liczenie wpisów…'
                          : c.$1 == 0
                              ? 'Brak wpisów w tym okresie'
                              : '${c.$1} ${plural(c.$1, 'wpis', 'wpisy', 'wpisów')} w ${c.$2} z $_rangeDays dni',
                      style: t.bodySmall,
                    ),
                  ]),
                ),
                const Icon(Icons.edit_outlined, size: 18, color: inkMuted),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Wrap(spacing: 8, children: [
            for (final days in [7, 14, 30])
              ChoiceChip(
                label: Text('$days dni'),
                selected: _rangeDays == days && DateUtils.isSameDay(_range.end, DateTime.now()),
                selectedColor: heatherSoft,
                showCheckmark: false,
                onSelected: (_) => _setLast(days),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run((pdf) async {
                        if (!await printOrShare(pdf, _fileName)) {
                          _snack('To urządzenie nie ma usługi drukowania, więc otwieram udostępnianie. '
                              'Wybierz aplikację, z której wydrukujesz PDF, albo wyślij go mailem.');
                        }
                      }),
              icon: _busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.print_outlined),
              label: const Text('Drukuj dzienniczek'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy ? null : () => _run((pdf) => Printing.sharePdf(bytes: pdf, filename: _fileName)),
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Wyślij PDF'),
            ),
            const SizedBox(height: 16),
            Text(
              'PDF zawiera każdy dzień z godzinami i zdjęciami posiłków, sumy dzienne, % normy oraz średnie z całego okresu.',
              style: t.bodySmall,
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      ],
    );
  }
}
