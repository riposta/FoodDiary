import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../ai.dart';
import '../db.dart';
import '../energy.dart';
import '../models.dart';
import '../prefs.dart';
import '../theme.dart';

/// Arkusz dodawania/edycji aktywności. Zwraca zapisaną aktywność albo null (anulowano / usunięto).
Future<Activity?> showActivitySheet(BuildContext context,
        {Activity? activity, required DateTime day, required double weightKg, required double bmr}) =>
    showModalBottomSheet<Activity>(
      context: context,
      isScrollControlled: true,
      backgroundColor: porcelain,
      showDragHandle: true,
      builder: (_) => _ActivitySheet(activity: activity, day: day, weightKg: weightKg, bmr: bmr),
    );

class _ActivitySheet extends StatefulWidget {
  const _ActivitySheet({this.activity, required this.day, required this.weightKg, required this.bmr});
  final Activity? activity;
  final DateTime day;
  final double weightKg;
  final double bmr;

  @override
  State<_ActivitySheet> createState() => _ActivitySheetState();
}

class _ActivitySheetState extends State<_ActivitySheet> {
  static const _quick = [15, 30, 45, 60, 90, 120];
  late final Activity _a;
  late final TextEditingController _minutes;
  late final TextEditingController _watch;

  // tryb AI: zrzuty / zdjęcia maszyn, plik z danymi, wklejony tekst
  bool _aiMode = false;
  bool _busy = false;
  final List<File> _aiPhotos = [];
  final _aiText = TextEditingController();
  String? _fileName;
  String? _fileText;

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
    _aiText.dispose();
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

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickPhotos(ImageSource src) async {
    final left = 3 - _aiPhotos.length;
    if (left <= 0) return;
    final picker = ImagePicker();
    final List<XFile> picked;
    if (src == ImageSource.camera) {
      final x = await picker.pickImage(source: src, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      picked = x == null ? [] : [x];
    } else {
      // zrzuty ekranu: wyższa rozdzielczość, żeby liczby były czytelne
      picked = await picker.pickMultiImage(limit: left, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    }
    setState(() => _aiPhotos.addAll(picked.take(left).map((x) => File(x.path))));
  }

  Future<void> _pickFile() async {
    final f = (await FilePicker.pickFiles()).firstOrNull;
    if (f?.path == null) return;
    final file = File(f!.path!);
    if (await file.length() > 5 * 1024 * 1024) return _snack('Plik jest za duży (maks. 5 MB)');
    final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    if (text.contains('\u0000')) return _snack('To nie wygląda na plik tekstowy. Zrób zrzut ekranu zamiast tego.');
    setState(() => (_fileName = f.name, _fileText = text));
  }

  Future<void> _analyze() async {
    if (_aiPhotos.isEmpty && _aiText.text.trim().isEmpty && _fileText == null) {
      return _snack('Dodaj zrzut, plik albo opis aktywności');
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final g = await analyzeActivity(
        photos: _aiPhotos,
        text: _aiText.text,
        fileName: _fileName,
        fileText: _fileText,
        day: widget.day,
        bmr: widget.bmr,
        weightKg: widget.weightKg,
      );
      final r = g.activity;
      setState(() {
        _a
          ..type = r.type
          ..minutes = r.minutes > 0 ? r.minutes : _a.minutes
          ..intensity = r.intensity
          ..startedAt = r.startedAt
          ..note = r.note;
        _minutes.text = '${_a.minutes}';
        _watch.text = g.hasKcal ? fmtExact(double.parse(r.kcal.toStringAsFixed(0))) : '';
        _aiMode = false; // pokaż wypełniony formularz do sprawdzenia
      });
    } on AiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _aiSection(TextTheme t) {
    final compact =
        FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 16));
    return [
      const SizedBox(height: 16),
      Text(
          'Zrzut z aplikacji (Strava, Garmin, Fitbit…), zdjęcie wyświetlacza maszyny, raport albo surowe dane z urządzenia. '
          'AI odczyta typ, czas, intensywność i kalorie.',
          style: t.bodySmall),
      const SizedBox(height: 12),
      if (_aiPhotos.isNotEmpty) ...[
        Row(children: [
          for (final (i, f) in _aiPhotos.indexed) ...[
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(f, width: 84, height: 84, fit: BoxFit.cover, cacheWidth: 252),
              ),
              Positioned(
                right: 2,
                top: 2,
                child: GestureDetector(
                  onTap: () => setState(() => _aiPhotos.removeAt(i)),
                  child: const CircleAvatar(
                      radius: 12, backgroundColor: Colors.white, child: Icon(Icons.close, size: 14, color: ink)),
                ),
              ),
            ]),
            const SizedBox(width: 8),
          ],
        ]),
        const SizedBox(height: 10),
      ],
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonalIcon(
            style: compact,
            onPressed: _aiPhotos.length >= 3 ? null : () => _pickPhotos(ImageSource.gallery),
            icon: const Icon(Icons.screenshot_outlined),
            label: const Text('Zrzut / zdjęcie')),
        FilledButton.tonalIcon(
            style: compact,
            onPressed: _aiPhotos.length >= 3 ? null : () => _pickPhotos(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Aparat')),
        FilledButton.tonalIcon(
            style: compact,
            onPressed: _pickFile,
            icon: const Icon(Icons.description_outlined),
            label: const Text('Plik z danymi')),
      ]),
      if (_fileName != null) ...[
        const SizedBox(height: 8),
        InputChip(
          avatar: const Icon(Icons.insert_drive_file_outlined, size: 18),
          label: Text(_fileName!, overflow: TextOverflow.ellipsis),
          onDeleted: () => setState(() => (_fileName = null, _fileText = null)),
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _aiText,
        minLines: 2,
        maxLines: 8,
        decoration: const InputDecoration(
          labelText: 'Opis albo wklejone dane (opcjonalnie)',
          hintText: 'np. orbitrek 40 min, na liczniku 420 kcal',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _busy ? null : _analyze,
        icon: _busy
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.auto_awesome),
        label: const Text('Analizuj z AI'),
      ),
    ];
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
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.tune_rounded), label: Text('Ręcznie')),
              ButtonSegment(value: true, icon: Icon(Icons.auto_awesome_outlined), label: Text('Z AI')),
            ],
            selected: {_aiMode},
            onSelectionChanged: (v) => setState(() => _aiMode = v.first),
          ),
          if (_aiMode)
            ..._aiSection(t)
          else ...[
            if (_a.note != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: heatherSoft, borderRadius: BorderRadius.circular(14)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.auto_awesome_outlined, size: 18, color: heather),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_a.note!, style: t.bodySmall?.copyWith(color: ink))),
                ]),
              ),
            ],
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
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: line)),
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
                labelText: 'Kalorie z zegarka / urządzenia (opcjonalnie)',
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
                  watch != null && watch > 0 ? 'z urządzenia' : 'wg MET, ${fmtNum(widget.weightKg)} kg',
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
          ],
        ]),
      ),
    );
  }
}
