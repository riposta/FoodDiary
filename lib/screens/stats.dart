import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../models.dart';
import '../prefs.dart';
import '../theme.dart';
import 'today.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _month = false;
  late DateTime _from;
  List<Entry> _entries = [];

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    final t = dayOf(DateTime.now());
    _from = _month ? DateTime(t.year, t.month) : DateTime(t.year, t.month, t.day - (t.weekday - 1));
    _load();
  }

  DateTime get _to => _month ? DateTime(_from.year, _from.month + 1, 0) : DateTime(_from.year, _from.month, _from.day + 6);

  void _shift(int dir) {
    _from = _month ? DateTime(_from.year, _from.month + dir) : DateTime(_from.year, _from.month, _from.day + 7 * dir);
    _load();
  }

  Future<void> _load() async {
    final e = await Db.range(_from, _to);
    if (mounted) setState(() => _entries = e);
  }

  @override
  Widget build(BuildContext context) {
    final norms = prefs.norms;
    final days = byDay(_entries);
    final n = _month ? _to.day : 7;
    final dates = [for (var i = 0; i < n; i++) DateTime(_from.year, _from.month, _from.day + i)];
    final kcal = [for (final d in dates) sumValues((days[d] ?? []).map((e) => e.values))['kcal']!];
    final label = _month
        ? DateFormat('LLLL y').format(_from)
        : '${DateFormat('d MMM').format(_from)} – ${DateFormat('d MMM y').format(_to)}';
    final canNext = _to.isBefore(dayOf(DateTime.now()));

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const PageHeader('Statystyki'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('Tydzień')), ButtonSegment(value: true, label: Text('Miesiąc'))],
            selected: {_month},
            onSelectionChanged: (s) {
              _month = s.first;
              _reset();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 12, 4),
          child: Row(children: [
            Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
            IconButton(tooltip: 'Wcześniej', icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _shift(-1)),
            IconButton(
                tooltip: 'Później', icon: const Icon(Icons.chevron_right_rounded), onPressed: canNext ? () => _shift(1) : null),
          ]),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 16),
                child: Text('Kalorie dziennie', style: Theme.of(context).textTheme.titleSmall),
              ),
              SizedBox(height: 220, child: _chart(dates, kcal, norms['kcal']!)),
            ]),
          ),
        ),
        SummaryCard(
          title: days.isEmpty ? 'Brak wpisów w tym okresie' : 'Średnia z dni z wpisami (${days.length})',
          average: true,
          total: dailyAverage(_entries),
          norms: norms,
        ),
      ],
    );
  }

  Widget _chart(List<DateTime> dates, List<double> kcal, double norm) {
    final maxY = max(norm, kcal.fold(0.0, max)) * 1.15;
    return BarChart(BarChartData(
      maxY: maxY,
      barGroups: [
        for (var i = 0; i < dates.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: kcal[i],
              width: _month ? 6 : 22,
              color: lilac,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ]),
      ],
      extraLinesData: ExtraLinesData(horizontalLines: [
        HorizontalLine(
          y: norm,
          color: overBar,
          strokeWidth: 1.2,
          dashArray: [6, 4],
          label: HorizontalLineLabel(
            show: true,
            alignment: Alignment.topRight,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: overText),
            labelResolver: (_) => 'norma ${fmtNum(norm)}',
          ),
        ),
      ]),
      gridData: FlGridData(
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => const FlLine(color: track, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (v, meta) => v == meta.max
                ? const SizedBox()
                : Text(fmtNum(v), style: const TextStyle(fontSize: 10, color: inkMuted)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, meta) {
              final d = dates[v.toInt()];
              final show = !_month || d.day == 1 || d.day % 5 == 0;
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(show ? (_month ? '${d.day}' : DateFormat('EEE').format(d)) : '',
                    style: const TextStyle(fontSize: 10, color: inkMuted)),
              );
            },
          ),
        ),
      ),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => ink,
          getTooltipItem: (g, _, rod, __) => BarTooltipItem(
            '${DateFormat('EEE d MMM').format(dates[g.x])}\n${fmtNum(rod.toY)} kcal (${(rod.toY / norm * 100).round()}%)',
            const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ),
    ));
  }
}
