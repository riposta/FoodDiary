import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../db.dart';
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

  @override
  void initState() {
    super.initState();
    final t = dayOf(DateTime.now());
    _range = DateTimeRange(start: DateTime(t.year, t.month, t.day - 6), end: t);
  }

  String get _fileName =>
      'dzienniczek_${DateFormat('yyyy-MM-dd').format(_range.start)}_${DateFormat('yyyy-MM-dd').format(_range.end)}.pdf';

  Future<void> _run(Future<void> Function(Uint8List pdf) action) async {
    setState(() => _busy = true);
    try {
      final entries = await Db.range(_range.start, _range.end);
      final pdf = await buildReport(_range.start, _range.end, entries, prefs.norms);
      await action(pdf);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nie udało się wygenerować PDF: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('d MMMM y');
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text('Dzienniczek PDF', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: ink)),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('Rozpiska posiłków dzień po dniu ze zdjęciami, sumami i % normy — do wydruku lub wysłania dietetyczce.',
              style: TextStyle(color: Colors.black54)),
        ),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: const Icon(Icons.date_range),
            title: const Text('Okres'),
            subtitle: Text('${f.format(_range.start)} – ${f.format(_range.end)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ink)),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () async {
              final r = await showDateRangePicker(
                  context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: _range);
              if (r != null) setState(() => _range = r);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(spacing: 8, children: [
            for (final (label, days) in [('Ostatnie 7 dni', 7), ('Ostatnie 14 dni', 14), ('Ostatnie 30 dni', 30)])
              ActionChip(
                label: Text(label),
                backgroundColor: lavender.withOpacity(.4),
                onPressed: () {
                  final t = dayOf(DateTime.now());
                  setState(() => _range = DateTimeRange(start: DateTime(t.year, t.month, t.day - days + 1), end: t));
                },
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy ? null : () => _run((pdf) => Printing.layoutPdf(onLayout: (_) async => pdf, name: _fileName)),
              icon: _busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.print),
              label: const Text('Generuj i drukuj'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy ? null : () => _run((pdf) => Printing.sharePdf(bytes: pdf, filename: _fileName)),
              icon: const Icon(Icons.share),
              label: const Text('Udostępnij PDF (e-mail, komunikator…)'),
            ),
          ]),
        ),
      ],
    );
  }
}
