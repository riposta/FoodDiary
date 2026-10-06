import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../ai.dart';
import '../db.dart';
import '../energy.dart';
import '../models.dart';
import '../prefs.dart';
import '../theme.dart';

class EntryEditScreen extends StatefulWidget {
  const EntryEditScreen({super.key, this.entry, this.day});
  final Entry? entry; // null = nowy wpis
  final DateTime? day; // dzień, do którego dodajemy nowy wpis

  @override
  State<EntryEditScreen> createState() => _EntryEditScreenState();
}

class _EntryEditScreenState extends State<EntryEditScreen> {
  late DateTime _eatenAt;
  static const _maxPhotos = 3;
  final List<File> _photos = []; // [0] = główne (trafia do historii), reszta tylko do analizy
  bool _photoChanged = false;
  Values? _norms; // normy dnia wpisu (z aktywnościami i celem)
  late String _desc;
  Entry? _draft; // formularz widoczny po analizie / przy edycji
  int _formVersion = 0; // odświeża pola formularza po ponownej analizie
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    final now = DateTime.now();
    final d = widget.day ?? now;
    _eatenAt = e?.eatenAt ?? DateTime(d.year, d.month, d.day, now.hour, now.minute);
    _desc = e?.description ?? '';
    if (e?.photo != null) _photos.add(Db.photoFile(e!.photo!));
    _draft = e;
    _loadNorms();
  }

  Future<void> _loadNorms() async {
    final b = await Db.budget(_eatenAt, await Db.estimate());
    if (mounted) setState(() => _norms = dayNorms(prefs.profile, prefs.overrides, b.goal));
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pick(ImageSource src) async {
    final left = _maxPhotos - _photos.length;
    if (left <= 0) return;
    final picker = ImagePicker();
    final List<XFile> picked;
    if (src == ImageSource.camera) {
      final x = await picker.pickImage(source: src, maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
      picked = x == null ? [] : [x];
    } else {
      picked = await picker.pickMultiImage(limit: left, maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
    }
    if (picked.isEmpty) return;
    setState(() {
      _photos.addAll(picked.take(left).map((x) => File(x.path)));
      _photoChanged = true;
    });
  }

  Future<void> _photoMenu(int i) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (i > 0)
            ListTile(
              leading: const Icon(Icons.star_outline_rounded),
              title: const Text('Ustaw jako główne'),
              subtitle: const Text('To zdjęcie zostanie w historii'),
              onTap: () => Navigator.pop(c, 'main'),
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: const Text('Usuń zdjęcie'),
            onTap: () => Navigator.pop(c, 'delete'),
          ),
        ]),
      ),
    );
    if (action == null) return;
    setState(() {
      final f = _photos.removeAt(i);
      if (action == 'main') _photos.insert(0, f);
      _photoChanged = true;
    });
  }

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(
        context: context, initialDate: _eatenAt, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_eatenAt));
    if (t == null) return;
    setState(() => _eatenAt = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _analyze() async {
    if (_photos.isEmpty && _desc.trim().isEmpty) return _snack('Dodaj zdjęcie lub opis');
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final r = await analyze(photos: _photos, description: _desc, eatenAt: _eatenAt);
      setState(() {
        final d = _draft ??= Entry(eatenAt: _eatenAt, mealType: r.mealType, name: r.name);
        d
          ..mealType = r.mealType
          ..name = r.name
          ..portion = r.portion
          ..aiNotes = r.aiNotes
          ..values = r.values;
        _formVersion++;
      });
    } on AiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _manual() => setState(() => _draft = Entry(eatenAt: _eatenAt, mealType: MealType.forTime(_eatenAt), name: ''));

  Future<void> _save() async {
    final d = _draft!;
    if (d.name.trim().isEmpty) return _snack('Podaj nazwę');
    setState(() => _busy = true);
    try {
      // do historii trafia tylko zdjęcie główne; pozostałe służyły wyłącznie analizie
      final main = _photos.firstOrNull;
      final old = d.photo;
      if (_photoChanged && main?.path != (old == null ? null : Db.photoFile(old).path)) {
        if (main != null) {
          final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
          await main.copy(Db.photoFile(name).path);
          d.photo = name;
        } else {
          d.photo = null;
        }
        if (old != null && await Db.photoFile(old).exists()) await Db.photoFile(old).delete();
      }
      d
        ..eatenAt = _eatenAt
        ..description = _desc.trim().isEmpty ? null : _desc.trim()
        ..name = d.name.trim();
      await Db.save(d);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _snack('Nie udało się zapisać: $e');
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDelete(context, widget.entry!);
    if (ok && mounted) {
      await Db.delete(widget.entry!);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final norms = _norms ?? prefs.norms;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry == null ? 'Nowy wpis' : 'Edycja wpisu'),
        actions: [
          if (widget.entry != null) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _busy ? null : _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _photoBox(),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _desc,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Opis (opcjonalny)', hintText: 'np. kawa z mlekiem 2%, 250 ml; owsianka z bananem'),
            onChanged: (s) => _desc = s,
          ),
          const SizedBox(height: 12),
          ListTile(
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: line)),
            leading: const Icon(Icons.schedule_rounded, color: heather),
            title: Text(DateFormat('EEEE, d MMMM, HH:mm').format(_eatenAt), style: Theme.of(context).textTheme.titleSmall),
            trailing: const Icon(Icons.edit_outlined, size: 18, color: inkMuted),
            onTap: _pickDateTime,
          ),
          const SizedBox(height: 16),
          if (_draft == null)
            FilledButton.icon(
              onPressed: _busy ? null : _analyze,
              icon: _busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: const Text('Analizuj z AI'),
            )
          else
            OutlinedButton.icon(
              onPressed: _busy ? null : _analyze,
              icon: _busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_outlined, color: heather),
              label: const Text('Analizuj ponownie'),
            ),
          if (_draft == null) TextButton(onPressed: _busy ? null : _manual, child: const Text('Wpisz ręcznie')),
          if (_draft != null) ..._form(_draft!, norms),
        ],
      ),
    );
  }

  static final _compact = FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 18));

  Widget _photoBox() {
    final t = Theme.of(context).textTheme;
    final full = _photos.length >= _maxPhotos;
    final buttons = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      FilledButton.tonalIcon(
          style: _compact,
          onPressed: full ? null : () => _pick(ImageSource.camera),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Aparat')),
      const SizedBox(width: 12),
      FilledButton.tonalIcon(
          style: _compact,
          onPressed: full ? null : () => _pick(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Galeria')),
    ]);
    if (_photos.isEmpty) {
      return Container(
        height: 172,
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: line), borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Dodaj zdjęcie posiłku', style: t.titleSmall),
          const SizedBox(height: 4),
          Text('Do 3 zdjęć, np. potrawa i etykieta ze składem', style: t.bodySmall),
          const SizedBox(height: 16),
          buttons,
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GestureDetector(
        onTap: () => _photoMenu(0),
        child: Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.file(_photos.first, height: 240, width: double.infinity, fit: BoxFit.cover),
          ),
          if (_photos.length > 1)
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .9), borderRadius: BorderRadius.circular(10)),
                child: Text('Główne, zostaje w historii', style: t.labelSmall?.copyWith(color: ink)),
              ),
            ),
        ]),
      ),
      if (_photos.length > 1) ...[
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 1; i < _photos.length; i++) ...[
            GestureDetector(
              onTap: () => _photoMenu(i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_photos[i], width: 72, height: 72, fit: BoxFit.cover, cacheWidth: 216),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text('Dodatkowe zdjęcia idą tylko do analizy. Stuknij, aby zmienić.', style: t.bodySmall)),
        ]),
      ],
      const SizedBox(height: 10),
      if (full) Center(child: Text('Masz już 3 zdjęcia', style: t.bodySmall)) else buttons,
    ]);
  }

  List<Widget> _form(Entry d, Values norms) => [
        const SizedBox(height: 20),
        if (d.aiNotes?.isNotEmpty ?? false)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: heatherSoft, borderRadius: BorderRadius.circular(14)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.auto_awesome_outlined, size: 18, color: heather),
              const SizedBox(width: 10),
              Expanded(child: Text(d.aiNotes!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ink))),
            ]),
          ),
        TextFormField(
          key: ValueKey('name$_formVersion'),
          initialValue: d.name,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nazwa'),
          onChanged: (s) => d.name = s,
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextFormField(
              key: ValueKey('portion$_formVersion'),
              initialValue: d.portion,
              decoration: const InputDecoration(labelText: 'Porcja'),
              onChanged: (s) => d.portion = s,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<MealType>(
              key: ValueKey('meal$_formVersion'),
              initialValue: d.mealType,
              decoration: const InputDecoration(labelText: 'Posiłek'),
              items: [for (final m in MealType.values) DropdownMenuItem(value: m, child: Text(m.label))],
              onChanged: (m) => d.mealType = m!,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: 8,
            runSpacing: 12,
            children: [
              for (final n in nutrients)
                SizedBox(
                  width: (c.maxWidth - 8) / 2,
                  child: TextFormField(
                    key: ValueKey('${n.key}$_formVersion'),
                    initialValue: fmtExact(d.values[n.key]!),
                    decoration: InputDecoration(
                      labelText: n.label,
                      suffixText: n.unit,
                      helperText: '${(d.values[n.key]! / norms[n.key]! * 100).round()}% normy',
                      prefixIcon: Icon(Icons.circle, color: n.color, size: 14),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (s) => setState(() => d.values[n.key] = parseNum(s) ?? 0),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.check),
          label: const Text('Zapisz'),
        ),
      ];
}

Future<bool> confirmDelete(BuildContext context, Entry e) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Usunąć wpis?'),
        content: Text(e.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Usuń')),
        ],
      ),
    ) ??
    false;
