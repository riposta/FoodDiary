import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../ai.dart';
import '../db.dart';
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
  File? _photo; // zapisane lub świeżo wybrane zdjęcie
  bool _photoChanged = false;
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
    if (e?.photo != null) _photo = Db.photoFile(e!.photo!);
    _draft = e;
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pick(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
    if (x != null) setState(() => (_photo = File(x.path), _photoChanged = true));
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
    if (_photo == null && _desc.trim().isEmpty) return _snack('Dodaj zdjęcie lub opis');
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final r = await analyze(photo: _photo, description: _desc, eatenAt: _eatenAt);
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
      if (_photoChanged) {
        final old = d.photo;
        if (_photo != null) {
          final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
          await _photo!.copy(Db.photoFile(name).path);
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
    final norms = prefs.norms;
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: const Icon(Icons.schedule),
            title: Text(DateFormat('EEEE, d MMMM y, HH:mm').format(_eatenAt)),
            onTap: _pickDateTime,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _analyze,
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(_draft == null ? 'Analizuj z AI' : 'Analizuj ponownie'),
          ),
          if (_draft == null) TextButton(onPressed: _busy ? null : _manual, child: const Text('Wpisz ręcznie')),
          if (_draft != null) ..._form(_draft!, norms),
        ],
      ),
    );
  }

  Widget _photoBox() {
    final buttons = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      FilledButton.tonalIcon(onPressed: () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera), label: const Text('Aparat')),
      const SizedBox(width: 12),
      FilledButton.tonalIcon(onPressed: () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('Galeria')),
    ]);
    if (_photo == null) {
      return Container(
        height: 160,
        decoration: BoxDecoration(color: mint.withOpacity(.35), borderRadius: BorderRadius.circular(24)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.restaurant, size: 40, color: ink),
          const SizedBox(height: 12),
          buttons,
        ]),
      );
    }
    return Column(children: [
      Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Image.file(_photo!, height: 240, width: double.infinity, fit: BoxFit.cover),
        ),
        Positioned(
          right: 8,
          top: 8,
          child: IconButton.filledTonal(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => (_photo = null, _photoChanged = true)),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      buttons,
    ]);
  }

  List<Widget> _form(Entry d, Values norms) => [
        const SizedBox(height: 20),
        if (d.aiNotes?.isNotEmpty ?? false)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: lavender.withOpacity(.4), borderRadius: BorderRadius.circular(16)),
            child: Text('🤖 ${d.aiNotes}'),
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
              value: d.mealType,
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
                    initialValue: fmtNum(d.values[n.key]!),
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
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF5FA58F), minimumSize: const Size.fromHeight(52)),
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
