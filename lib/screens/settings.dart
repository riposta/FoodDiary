import 'package:flutter/material.dart';

import '../ai.dart';
import '../models.dart';
import '../prefs.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _p = prefs;
  bool _obscureKey = true;
  bool _testing = false;

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      final e = await analyze(description: 'szklanka soku pomarańczowego 250 ml', eatenAt: DateTime.now());
      _snack('Działa ✓ ${e.name}: ${fmtNum(e.values['kcal']!)} kcal');
    } on AiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  void dispose() {
    _p.save(); // zmiany nie giną przy przejściu na inną zakładkę
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    await _p.save();
    if (mounted) _snack('Zapisano ustawienia');
  }

  Widget _numField(String label, num value, String suffix, void Function(double) onChanged) => TextFormField(
        initialValue: fmtNum(value.toDouble()),
        decoration: InputDecoration(labelText: label, suffixText: suffix),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (s) {
          final v = parseNum(s);
          if (v != null && v > 0) setState(() => onChanged(v));
        },
      );

  Widget _section(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              ...children.expand((w) => [w, const SizedBox(height: 12)]),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pr = _p.profile;
    final auto = defaultNorms(pr);
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text('Ustawienia', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: ink)),
        ),
        _section('Profil', [
          SegmentedButton<Sex>(
            segments: [for (final s in Sex.values) ButtonSegment(value: s, label: Text(s.label))],
            selected: {pr.sex},
            onSelectionChanged: (s) => setState(() => pr.sex = s.first),
          ),
          Row(children: [
            Expanded(child: _numField('Wiek', pr.age, 'lat', (v) => pr.age = v.round())),
            const SizedBox(width: 8),
            Expanded(child: _numField('Waga', pr.weight, 'kg', (v) => pr.weight = v)),
            const SizedBox(width: 8),
            Expanded(child: _numField('Wzrost', pr.height, 'cm', (v) => pr.height = v)),
          ]),
          DropdownButtonFormField<double>(
            value: activityLevels.containsKey(pr.activity) ? pr.activity : 1.375,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Aktywność'),
            items: [for (final e in activityLevels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => pr.activity = v!),
          ),
        ]),
        _section('Dzienne normy', [
          const Text('Puste pole = wyliczone z profilu. Wpisz wartość, aby nadpisać (np. zalecenie dietetyczki).',
              style: TextStyle(color: Colors.black54)),
          for (final n in nutrients)
            TextFormField(
              key: ValueKey('norm_${n.key}'),
              initialValue: _p.overrides[n.key] == null ? '' : fmtNum(_p.overrides[n.key]!),
              decoration: InputDecoration(
                labelText: n.label,
                hintText: 'auto: ${fmtNum(auto[n.key]!)}',
                floatingLabelBehavior: FloatingLabelBehavior.always,
                suffixText: n.unit,
                prefixIcon: Icon(Icons.circle, color: n.color, size: 14),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (s) {
                final v = parseNum(s);
                v == null || v <= 0 ? _p.overrides.remove(n.key) : _p.overrides[n.key] = v;
              },
            ),
        ]),
        _section('AI (API zgodne z OpenAI)', [
          TextFormField(
            initialValue: _p.baseUrl,
            decoration: const InputDecoration(labelText: 'Base URL'),
            keyboardType: TextInputType.url,
            onChanged: (s) => _p.baseUrl = s.trim(),
          ),
          TextFormField(
            initialValue: _p.apiKey,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              labelText: 'Klucz API',
              suffixIcon: IconButton(
                icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
            onChanged: (s) => _p.apiKey = s.trim(),
          ),
          TextFormField(
            initialValue: _p.model,
            decoration: const InputDecoration(labelText: 'Model (musi obsługiwać obraz)'),
            onChanged: (s) => _p.model = s.trim(),
          ),
          OutlinedButton.icon(
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering),
            label: const Text('Testuj połączenie'),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const Text('Zapisz ustawienia')),
        ),
      ],
    );
  }
}
