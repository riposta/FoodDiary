import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../energy.dart';
import '../models.dart';
import '../prefs.dart';
import '../theme.dart';

/// Arkusz dodawania/edycji aktywności. Zwraca zapisaną aktywność albo null (anulowano / usunięto).
Future<Activity?> showActivitySheet(BuildContext context,
        {Activity? activity, required DateTime day, required double weightKg}) =>
    showModalBottomSheet<Activity>(
      context: context,
      isScrollControlled: true,
      backgroundColor: porcelain,
      showDragHandle: true,
      builder: (_) => _ActivitySheet(activity: activity, day: day, weightKg: weightKg),
    );

class _ActivitySheet extends StatefulWidget {
  const _ActivitySheet({this.activity, required this.day, required this.weightKg});
  final Activity? activity;
  final DateTime day;
  final double weightKg;

  @override
  State<_ActivitySheet> createState() => _ActivitySheetState();
}

class _ActivitySheetState extends State<_ActivitySheet> {
  static const _quick = [15, 30, 45, 60, 90, 120];
  late final Activity _a;
  late final TextEditingController _minutes;
  late final TextEditingController _watch;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final d = widget.day;
    final a = widget.activity;
    _a = a == null
        ? Activity(startedAt: DateTime(d.year, d.month, d.day, now.hour, now.minute), type: 'walk', minutes: 30)
        : Activity.fromMap(a.toMap()); // kopia: anulowanie nie zmienia oryginału
    _minutes = TextEditingController(text: '${_a.minutes}');
    _watch = TextEditingController(text: _a.kcalSource == 'met' ? '' : fmtExact(_a.kcal));
  }

  @override
  void dispose() {
    _minutes.dispose();
    _watch.dispose();
    super.dispose();
  }

  double get _metKcal => metKcal(_a.type, _a.intensity, _a.minutes, widget.weightKg);
  double? get _watchKcal => parseNum(_watch.text);

  Future<void> _save() async {
    if (_a.minutes <= 0) return;
    final watch = _watchKcal;
    if (watch != null && watch > 0) {
      _a
        ..kcal = watch
        ..kcalSource = _a.kcalSource == 'device' ? 'device' : 'manual';
    } else {
      _a
        ..kcal = _metKcal
        ..kcalSource = 'met';
    }
    await Db.saveActivity(_a);
    if (mounted) Navigator.pop(context, _a);
  }

  Future<void> _delete() async {
    await Db.deleteActivity(widget.activity!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final watch = _watchKcal;
    final kcal = watch != null && watch > 0 ? watch : _metKcal;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(widget.activity == null ? 'Nowa aktywność' : 'Edycja aktywności', style: t.titleLarge)),
            if (widget.activity != null)
              IconButton(tooltip: 'Usuń', icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final type in activityTypes)
              ChoiceChip(
                avatar: Icon(type.icon, size: 18, color: _a.type == type.key ? heather : inkMuted),
                label: Text(type.label),
                selected: _a.type == type.key,
                selectedColor: heatherSoft,
                showCheckmark: false,
                onSelected: (_) => setState(() => _a.type = type.key),
              ),
          ]),
          const SizedBox(height: 20),
          Text('Czas trwania', style: t.titleSmall),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in _quick)
                  ChoiceChip(
                    label: Text(m < 60 ? '$m min' : '${fmtNum(m / 60)} h'),
                    selected: _a.minutes == m,
                    selectedColor: heatherSoft,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      _a.minutes = m;
                      _minutes.text = '$m';
                    }),
                  ),
              ]),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: TextField(
                controller: _minutes,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(suffixText: 'min'),
                onChanged: (s) => setState(() => _a.minutes = int.tryParse(s.trim()) ?? 0),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          Text('Intensywność', style: t.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<Intensity>(
            segments: [for (final i in Intensity.values) ButtonSegment(value: i, label: Text(i.label))],
            selected: {_a.intensity},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _a.intensity = s.first),
          ),
          const SizedBox(height: 12),
          ListTile(
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: line)),
            leading: const Icon(Icons.schedule_rounded, color: heather),
            title: Text('Start ${DateFormat('HH:mm').format(_a.startedAt)}', style: t.titleSmall),
            trailing: const Icon(Icons.edit_outlined, size: 18, color: inkMuted),
            onTap: () async {
              final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_a.startedAt));
              if (tm != null) {
                final s = _a.startedAt;
                setState(() => _a.startedAt = DateTime(s.year, s.month, s.day, tm.hour, tm.minute));
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _watch,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Kalorie z zegarka (opcjonalnie)',
              helperText: 'Aktywne kalorie z opaski mają pierwszeństwo przed wyliczeniem',
              suffixText: 'kcal',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: heatherSoft, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Dodatkowo do limitu', style: t.labelSmall),
                  Text('+${fmtNum(kcal)} kcal', style: t.titleLarge),
                ]),
              ),
              Text(
                watch != null && watch > 0 ? 'z zegarka' : 'wg MET, ${fmtNum(widget.weightKg)} kg',
                style: t.bodySmall,
              ),
            ]),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _a.minutes > 0 ? _save : null,
            icon: const Icon(Icons.check),
            label: const Text('Zapisz aktywność'),
          ),
        ]),
      ),
    );
  }
}
