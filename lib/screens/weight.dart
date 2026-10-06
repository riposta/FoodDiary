import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../energy.dart';
import '../models.dart';
import '../notifications.dart';
import '../prefs.dart';
import '../theme.dart';

class WeightScreen extends StatefulWidget {
  const WeightScreen({super.key});

  @override
  State<WeightScreen> createState() => _WeightScreenState();
}

class _WeightScreenState extends State<WeightScreen> {
  List<WeightEntry> _weights = [];
  EnergyEstimate? _energy;
  int _rangeDays = 30; // 0 = całość

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await Db.weights();
    final e = await Db.estimate();
    if (mounted) setState(() => (_weights = w, _energy = e));
  }

  Future<void> _add() async {
    if (await addWeight(context)) await _load();
  }

  Future<void> _delete(WeightEntry w) async {
    await Db.deleteWeight(w);
    await _load();
  }

  Future<void> _editGoal() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: porcelain,
      showDragHandle: true,
      builder: (_) => const _GoalSheet(),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final e = _energy;
    final pts = [for (final w in _weights) (day: w.day, kg: w.kg)];
    final trend = weightTrend(withoutOutliers(pts));
    final goal = prefs.goalWeight;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Dodaj wagę'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 104),
          children: [
            PageHeader('Waga',
                subtitle:
                    goal == null ? 'Ustaw cel, żeby zobaczyć prognozę' : 'Cel: ${fmtExact(goal)} kg, ${_rateLabel()}'),
            if (trend.isEmpty)
              _empty(t)
            else ...[
              _hero(t, trend, e),
              _chartCard(t, pts, trend),
            ],
            if (e != null) _energyCard(t, e),
            _goalCard(t),
            if (_weights.isNotEmpty) ..._history(t),
          ],
        ),
      ),
    );
  }

  String _rateLabel() => prefs.rateKgWeek == 0 ? 'utrzymanie' : '${fmtExact(prefs.rateKgWeek)} kg/tydz.';

  Widget _empty(TextTheme t) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: heatherSoft, shape: BoxShape.circle),
              child: const Icon(Icons.monitor_weight_outlined, color: heather),
            ),
            const SizedBox(height: 12),
            Text('Brak ważeń', style: t.titleMedium),
            const SizedBox(height: 4),
            Text(
                'Waż się rano, przed śniadaniem. Na podstawie wagi i jedzenia aplikacja zmierzy Twoje prawdziwe zapotrzebowanie.',
                textAlign: TextAlign.center,
                style: t.bodySmall),
          ]),
        ),
      );

  Widget _hero(TextTheme t, List<WeighIn> trend, EnergyEstimate? e) {
    final now = trend.last.kg;
    final today = dayOf(DateTime.now());
    final weekAgo = trendAt(trend, DateTime(today.year, today.month, today.day - 7));
    final week = weekAgo == null ? null : now - weekAgo;
    final goal = prefs.goalWeight;
    // tempo: zmierzone, gdy pomiar jest pewny i waga spada; inaczej zaplanowane
    final measuredLoss = e?.slopeKgWeek == null ? null : -e!.slopeKgWeek!;
    final rate = (e?.confidence ?? 0) > .3 && (measuredLoss ?? 0) > .05 ? measuredLoss! : prefs.rateKgWeek;
    final eta = goal == null ? null : etaToGoal(now, goal, rate, today);
    final last = _weights.last;

    Widget stat(String label, String value) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: t.labelSmall),
            const SizedBox(height: 2),
            Text(value, style: t.titleSmall),
          ]),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Trend wagi', style: t.labelSmall),
          Text.rich(TextSpan(children: [
            TextSpan(
                text: fmtExact(double.parse(now.toStringAsFixed(1))), style: t.headlineMedium?.copyWith(fontSize: 40)),
            TextSpan(text: ' kg', style: t.titleMedium?.copyWith(color: inkMuted)),
          ])),
          Text('Ostatnie ważenie ${fmtExact(last.kg)} kg, ${_ago(last.day)}', style: t.bodySmall),
          const SizedBox(height: 16),
          Row(children: [
            stat('Ten tydzień',
                week == null ? '–' : '${week > 0 ? '+' : ''}${fmtExact(double.parse(week.toStringAsFixed(1)))} kg'),
            stat(
                'Do celu',
                goal == null
                    ? '–'
                    : now <= goal
                        ? 'osiągnięty'
                        : '${fmtExact(double.parse((now - goal).toStringAsFixed(1)))} kg'),
            stat('Prognoza', eta == null ? '–' : DateFormat('d MMM y').format(eta)),
          ]),
        ]),
      ),
    );
  }

  String _ago(DateTime d) {
    final n = daysBetween(d, DateTime.now());
    return switch (n) { 0 => 'dziś', 1 => 'wczoraj', _ => '$n dni temu' };
  }

  Widget _chartCard(TextTheme t, List<WeighIn> pts, List<WeighIn> trend) {
    final today = dayOf(DateTime.now());
    final start = _rangeDays == 0 ? pts.first.day : DateTime(today.year, today.month, today.day - _rangeDays);
    double x(DateTime d) => daysBetween(start, d).toDouble();
    final raw = [
      for (final p in pts)
        if (!p.day.isBefore(start)) FlSpot(x(p.day), p.kg)
    ];
    final tr = [
      for (final p in trend)
        if (!p.day.isBefore(start)) FlSpot(x(p.day), p.kg)
    ];
    final goal = prefs.goalWeight;

    // prognoza: od ostatniego trendu w stronę celu, najwyżej 30 dni do przodu
    final proj = <FlSpot>[];
    if (goal != null && tr.isNotEmpty && trend.last.kg > goal && prefs.rateKgWeek > 0) {
      final perDay = prefs.rateKgWeek / 7;
      final days = min(30.0, (trend.last.kg - goal) / perDay);
      proj.addAll([tr.last, FlSpot(tr.last.x + days, trend.last.kg - perDay * days)]);
    }
    final ys = [...raw.map((s) => s.y), ...tr.map((s) => s.y), ...proj.map((s) => s.y), if (goal != null) goal];
    final minY = (ys.reduce(min) - 1).floorToDouble(), maxY = (ys.reduce(max) + 1).ceilToDouble();
    final maxX = max(x(today), proj.isEmpty ? 0.0 : proj.last.x);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(children: [
              Expanded(child: Text('Przebieg', style: t.titleSmall)),
              for (final (label, d) in [('1M', 30), ('3M', 90), ('Całość', 0)])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _rangeDays == d,
                    selectedColor: heatherSoft,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _rangeDays = d),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: raw.isEmpty
                ? Center(child: Text('Brak ważeń w tym okresie', style: t.bodySmall))
                : LineChart(LineChartData(
                    minX: 0,
                    maxX: max(maxX, 1),
                    minY: minY,
                    maxY: maxY,
                    lineBarsData: [
                      // surowe ważenia: same kropki
                      LineChartBarData(
                        spots: raw,
                        barWidth: 0,
                        color: Colors.transparent,
                        dotData: FlDotData(
                          getDotPainter: (_, __, ___, ____) =>
                              FlDotCirclePainter(radius: 3, color: lilac, strokeWidth: 0),
                        ),
                      ),
                      LineChartBarData(
                          spots: tr,
                          isCurved: true,
                          barWidth: 2.5,
                          color: heather,
                          dotData: const FlDotData(show: false)),
                      if (proj.isNotEmpty)
                        LineChartBarData(
                          spots: proj,
                          barWidth: 2,
                          color: heather.withValues(alpha: .45),
                          dashArray: [3, 5],
                          dotData: const FlDotData(show: false),
                        ),
                    ],
                    extraLinesData: ExtraLinesData(horizontalLines: [
                      if (goal != null)
                        HorizontalLine(
                          y: goal,
                          color: const Color(0xFF5E9C86),
                          strokeWidth: 1.2,
                          dashArray: [6, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF4F8B76)),
                            labelResolver: (_) => 'cel ${fmtExact(goal)} kg',
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
                          reservedSize: 36,
                          getTitlesWidget: (v, meta) => v == meta.max || v == meta.min
                              ? const SizedBox()
                              : Text(fmtNum(v), style: const TextStyle(fontSize: 10, color: inkMuted)),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: max(1, (maxX / 4).roundToDouble()),
                          getTitlesWidget: (v, meta) => v == meta.max
                              ? const SizedBox()
                              : Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                      DateFormat('d MMM')
                                          .format(DateTime(start.year, start.month, start.day + v.round())),
                                      style: const TextStyle(fontSize: 10, color: inkMuted)),
                                ),
                        ),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => ink,
                        getTooltipItems: (spots) => [
                          for (final s in spots)
                            LineTooltipItem(
                              s.barIndex == 0
                                  ? '${DateFormat('d MMM').format(DateTime(start.year, start.month, start.day + s.x.round()))}: ${fmtExact(s.y)} kg'
                                  : s.barIndex == 1
                                      ? 'trend ${fmtExact(double.parse(s.y.toStringAsFixed(1)))} kg'
                                      : 'prognoza ${fmtExact(double.parse(s.y.toStringAsFixed(1)))} kg',
                              const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  )),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text('Kropki to ważenia, linia to trend (wygładza wahania wody i soli).', style: t.bodySmall),
          ),
        ]),
      ),
    );
  }

  Widget _energyCard(TextTheme t, EnergyEstimate e) {
    final budget = dayBudget(e, 0,
        rateKgWeek: prefs.rateKgWeek, goalWeight: prefs.goalWeight, kcalOverride: prefs.overrides['kcal']);
    final source = e.confidence < .05
        ? 'Na razie z wzoru. Waż się i zapisuj posiłki przez 2–4 tygodnie, a aplikacja zmierzy Twoje prawdziwe zapotrzebowanie.'
        : 'Pomiar z ${e.okDays} pełnych dni${e.slopeKgWeek == null ? '' : ', waga ${e.slopeKgWeek! <= 0 ? '' : '+'}${fmtExact(double.parse(e.slopeKgWeek!.toStringAsFixed(2)))} kg/tydz.'} '
            '(wzór dawałby ${fmtNum(e.formula)} kcal).';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Zapotrzebowanie', style: t.titleSmall),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Utrzymanie bez treningów', style: t.labelSmall),
                Text('${fmtNum(e.base)} kcal', style: t.titleLarge),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Cel w dzień bez treningu', style: t.labelSmall),
                Text('${fmtNum(budget.goal)} kcal', style: t.titleLarge),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Text('Pewność pomiaru', style: t.labelSmall),
            const Spacer(),
            Text('${(e.confidence * 100).round()}%', style: t.labelSmall),
          ]),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: e.confidence,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
            backgroundColor: track,
            color: heather,
          ),
          const SizedBox(height: 10),
          Text(source, style: t.bodySmall),
        ]),
      ),
    );
  }

  Widget _goalCard(TextTheme t) => Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: const Color(0xFFE9F3EF), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.flag_outlined, color: Color(0xFF5E9C86)),
          ),
          title: Text(prefs.goalWeight == null ? 'Ustaw cel' : 'Cel ${fmtExact(prefs.goalWeight!)} kg',
              style: t.titleSmall),
          subtitle: Text('Tempo: ${_rateLabel()}', style: t.bodySmall),
          trailing: const Icon(Icons.edit_outlined, size: 18, color: inkMuted),
          onTap: _editGoal,
        ),
      );

  List<Widget> _history(TextTheme t) => [
        Padding(padding: const EdgeInsets.fromLTRB(24, 20, 24, 8), child: Text('Ważenia', style: t.titleSmall)),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final (i, w) in _weights.reversed.take(14).indexed) ...[
              if (i > 0) const Divider(indent: 20),
              Dismissible(
                key: ValueKey('w${w.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: const Color(0xFFF6E3E7),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Icon(Icons.delete_outline_rounded, color: overText),
                ),
                onDismissed: (_) => _delete(w),
                child: ListTile(
                  title: Text(DateFormat('EEEE, d MMMM').format(w.day), style: t.bodyMedium),
                  subtitle: w.source == manualSource ? null : Text('z ${w.source}', style: t.bodySmall),
                  trailing: Text('${fmtExact(w.kg)} kg', style: t.titleSmall),
                ),
              ),
            ],
          ]),
        ),
      ];
}

/// Okno ważenia + zapis + kamień milowy. Wspólne dla ekranów „Waga” i „Dziś”. Zwraca true po zapisie.
Future<bool> addWeight(BuildContext context) async {
  final weights = await Db.weights();
  if (!context.mounted) return false;
  final r =
      await showDialog<WeightEntry>(context: context, builder: (_) => _WeightDialog(initialKg: weights.lastOrNull?.kg));
  if (r == null) return false;
  final before = weightTrend(withoutOutliers([for (final w in weights) (day: w.day, kg: w.kg)])).lastOrNull?.kg;
  await Db.saveWeight(r);
  final all = await Db.weights();
  final after = weightTrend(withoutOutliers([for (final w in all) (day: w.day, kg: w.kg)])).last.kg;
  final m =
      before == null ? null : milestone(start: all.first.kg, before: before, after: after, goal: prefs.goalWeight);
  if (m != null) {
    await Notifications.show(
        NotifKind.milestone, m, 'Trend wagi: ${fmtExact(double.parse(after.toStringAsFixed(1)))} kg',
        payload: 'weight');
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
  if (weights.every((w) => !w.day.isAfter(r.day))) {
    prefs.profile.weight = r.kg; // profil śledzi ostatnie ważenie (wzór, gdy brak trendu)
    await prefs.save();
  }
  return true;
}

class _WeightDialog extends StatefulWidget {
  const _WeightDialog({this.initialKg});
  final double? initialKg;

  @override
  State<_WeightDialog> createState() => _WeightDialogState();
}

class _WeightDialogState extends State<_WeightDialog> {
  late final TextEditingController _kg =
      TextEditingController(text: widget.initialKg == null ? '' : fmtExact(widget.initialKg!));
  DateTime _day = dayOf(DateTime.now());

  @override
  void dispose() {
    _kg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kg = parseNum(_kg.text);
    final valid = kg != null && kg >= 25 && kg <= 350;
    return AlertDialog(
      title: const Text('Dodaj wagę'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _kg,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            suffixText: 'kg',
            hintText: 'np. 92,4',
            helperText: kg != null && widget.initialKg != null && (kg - widget.initialKg!).abs() > 3
                ? 'Duża różnica od ostatniego ważenia (${fmtExact(widget.initialKg!)} kg). Sprawdź, czy nie ma literówki.'
                : null,
            helperMaxLines: 2,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined, color: heather),
          title: Text(DateFormat('EEEE, d MMMM').format(_day)),
          onTap: () async {
            final d = await showDatePicker(
                context: context, initialDate: _day, firstDate: DateTime(2020), lastDate: DateTime.now());
            if (d != null) setState(() => _day = dayOf(d));
          },
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: valid ? () => Navigator.pop(context, WeightEntry(day: _day, kg: kg)) : null,
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}

class _GoalSheet extends StatefulWidget {
  const _GoalSheet();

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late final TextEditingController _goal =
      TextEditingController(text: prefs.goalWeight == null ? '' : fmtExact(prefs.goalWeight!));
  double _rate = prefs.rateKgWeek;

  @override
  void dispose() {
    _goal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Cel', style: t.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _goal,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Waga docelowa', suffixText: 'kg'),
        ),
        const SizedBox(height: 20),
        Text('Tempo', style: t.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in [0.0, 0.25, 0.5, 0.75, 1.0])
            ChoiceChip(
              label: Text(r == 0 ? 'Utrzymanie' : '${fmtExact(r)} kg/tydz.'),
              selected: _rate == r,
              selectedColor: heatherSoft,
              showCheckmark: false,
              onSelected: (_) => setState(() => _rate = r),
            ),
        ]),
        const SizedBox(height: 8),
        Text(
          _rate == 0
              ? 'Bez deficytu: cel dnia równa się utrzymaniu.'
              : 'Deficyt ok. ${fmtNum(_rate * kcalPerKg / 7)} kcal dziennie. Bezpieczne tempo to zwykle 0,5–1% masy ciała tygodniowo.',
          style: t.bodySmall,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () async {
            final g = parseNum(_goal.text);
            prefs
              ..goalWeight = g != null && g > 25 ? g : null
              ..rateKgWeek = _rate;
            await prefs.save();
            if (context.mounted) Navigator.pop(context, true);
          },
          child: const Text('Zapisz cel'),
        ),
      ]),
    );
  }
}
