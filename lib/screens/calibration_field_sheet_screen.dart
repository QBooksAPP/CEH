import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/internal_navigation.dart';
import '../core/calibration_math.dart';
import '../models/session.dart';

class CalibrationFieldSheetScreen extends StatefulWidget {
  const CalibrationFieldSheetScreen({super.key, required this.session});
  final CehSession session;

  @override
  State<CalibrationFieldSheetScreen> createState() =>
      _CalibrationFieldSheetScreenState();
}

class _CalibrationFieldSheetScreenState
    extends State<CalibrationFieldSheetScreen> {
  final _api = const CehApiClient();
  final _mixer = TextEditingController(text: '307');
  final _notes = TextEditingController();
  final _container = TextEditingController();
  final _stoneMoisture = TextEditingController(text: '0.00');
  final _sandMoisture = TextEditingController(text: '0.00');
  final _cementSafety = TextEditingController(text: '2.00');
  late DateTime _date;
  int? _calibrationId;
  bool _saving = false;
  bool _submitting = false;
  bool _submitted = false;
  bool _loadingMixers = false;
  List<Map<String, dynamic>> _mixers = [];

  final Map<String, List<_Trial>> trials = {
    'Cement FULL': List.generate(6, (_) => _Trial()),
    'Cement HALF': List.generate(6, (_) => _Trial()),
    'Stone 5 cm': List.generate(6, (_) => _Trial()),
    'Stone 8 cm': List.generate(6, (_) => _Trial()),
    'Stone 11 cm': List.generate(6, (_) => _Trial()),
    'Sand 5 cm': List.generate(6, (_) => _Trial()),
    'Sand 8 cm': List.generate(6, (_) => _Trial()),
    'Sand 11 cm': List.generate(6, (_) => _Trial()),
  };

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    _loadMixers();
  }

  @override
  void dispose() {
    for (final c in [
      _mixer,
      _notes,
      _container,
      _stoneMoisture,
      _sandMoisture,
      _cementSafety
    ]) {
      c.dispose();
    }
    for (final group in trials.values) {
      for (final t in group) {
        t.dispose();
      }
    }
    super.dispose();
  }

  String get dateText => '${_date.day.toString().padLeft(2, '0')}/'
      '${_date.month.toString().padLeft(2, '0')}/'
      '${_date.year}';

  double n(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  Future<void> _loadMixers() async {
    if (mounted) setState(() => _loadingMixers = true);
    try {
      final items = await _api.mixers(widget.session);
      if (!mounted) return;
      setState(() {
        _mixers = items;
        if (items.isNotEmpty &&
            !items.any((m) => m['code'].toString() == _mixer.text.trim())) {
          _mixer.text = items.first['code'].toString();
        }
      });
    } catch (_) {
      // Manual mixer entry remains available as a fallback.
    } finally {
      if (mounted) setState(() => _loadingMixers = false);
    }
  }

  Future<void> pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  Map<String, double> resultFor(String name) {
    final valid = trials[name]!
        .where((t) =>
            t.weight.text.isNotEmpty &&
            t.counts.text.isNotEmpty &&
            n(t.counts) > 0)
        .toList();
    final isStone = name.startsWith('Stone');
    final isSand = name.startsWith('Sand');
    final result = calculateCalibrationResult(
      trials: valid.map(
        (trial) => CalibrationTrialValue(
          totalWeightKg: n(trial.weight),
          counts: n(trial.counts),
        ),
      ),
      containerWeightKg: n(_container),
      moisturePct: isStone
          ? n(_stoneMoisture)
          : isSand
              ? n(_sandMoisture)
              : 0,
      cementSafetyFactorPct: n(_cementSafety),
      applyMoistureCorrection: isStone || isSand,
      applyCementSafetyFactor: name.startsWith('Cement'),
    );

    return {
      'trials': result.validTrials.toDouble(),
      'kgpc': result.kgPerCount,
    };
  }

  Map<String, dynamic> _draftPayload() {
    final rows = <Map<String, dynamic>>[];

    void addGroup(String uiName, String material, int? gate) {
      final group = trials[uiName]!;
      for (var i = 0; i < group.length; i++) {
        final weight = group[i].weight.text.trim();
        final counts = group[i].counts.text.trim();
        if (weight.isEmpty && counts.isEmpty) continue;
        rows.add({
          'material': material,
          if (gate != null) 'gate_cm': gate,
          'trial_no': i + 1,
          'total_weight_kg': weight.isEmpty ? null : double.tryParse(weight),
          'counts': counts.isEmpty ? null : double.tryParse(counts),
        });
      }
    }

    addGroup('Cement FULL', 'CEMENT_FULL', null);
    addGroup('Cement HALF', 'CEMENT_HALF', null);
    addGroup('Stone 5 cm', 'STONE', 5);
    addGroup('Stone 8 cm', 'STONE', 8);
    addGroup('Stone 11 cm', 'STONE', 11);
    addGroup('Sand 5 cm', 'SAND', 5);
    addGroup('Sand 8 cm', 'SAND', 8);
    addGroup('Sand 11 cm', 'SAND', 11);

    return {
      if (_calibrationId != null) 'calibration_id': _calibrationId,
      'mixer_code': _mixer.text.trim(),
      'calibration_date': '${_date.year.toString().padLeft(4, '0')}-'
          '${_date.month.toString().padLeft(2, '0')}-'
          '${_date.day.toString().padLeft(2, '0')}',
      'calibration_notes': _notes.text.trim(),
      'container_weight_kg': n(_container),
      'stone_moisture_pct': n(_stoneMoisture),
      'sand_moisture_pct': n(_sandMoisture),
      'cement_safety_factor_pct': n(_cementSafety),
      'trials': rows,
    };
  }

  Future<void> _saveDraft() async {
    if (_mixer.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select or enter a mixer first.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final data =
          await _api.saveCalibrationDraft(widget.session, _draftPayload());
      if (!mounted) return;
      setState(() => _calibrationId = (data['calibration_id'] as num).toInt());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Draft #$_calibrationId saved to CEH server.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save draft: ${e.code}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save draft.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitCalibration() async {
    if (_calibrationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save the calibration draft first.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit calibration?'),
        content: const Text(
          'After submission the operator cannot edit this calibration. '
          'It will be sent to CEH Admin for approval.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      await _api.submitCalibration(widget.session, _calibrationId!);
      if (!mounted) return;
      setState(() => _submitted = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Calibration submitted for Admin approval.'),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit: ${e.code}')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void preview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .8,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Calibration Data Preview',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            Text('Mixer ${_mixer.text} • $dateText'),
            const SizedBox(height: 14),
            ...trials.keys.map((name) {
              final r = resultFor(name);
              final blank = r['trials']!.toInt() == 0;
              return Card(
                child: ListTile(
                  title: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(blank
                      ? (name == 'Cement HALF'
                          ? 'Not used — optional'
                          : 'No trials entered')
                      : '${r['trials']!.toInt()} valid trial(s)'),
                  trailing: blank
                      ? const Text('—')
                      : Text('${r['kgpc']!.toStringAsFixed(6)} kg/count'),
                ),
              );
            }),
            const SizedBox(height: 10),
            const Text(
              'Cement HALF is optional. Blank optional sections are ignored, not treated as zero calibration values.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget numField(TextEditingController c, String label,
          {String? suffix, bool enabled = true}) =>
      TextField(
        controller: c,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: suffix),
      );

  Widget trialCard(String name) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ExpansionTile(
          title:
              Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(name == 'Cement HALF'
              ? 'Optional • up to 6 trials'
              : 'Up to 6 trials'),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            for (int i = 0; i < 6; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  SizedBox(
                      width: 34,
                      child: Text('${i + 1}', textAlign: TextAlign.center)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: numField(trials[name]![i].weight, 'Total weight',
                          suffix: 'kg')),
                  const SizedBox(width: 8),
                  Expanded(child: numField(trials[name]![i].counts, 'Counts')),
                ]),
              )
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final canEditSafetyFactor = widget.session.user.isAdmin;
    return Scaffold(
      appBar: AppBar(
        actions: cehHomeAction(context),
        title: const Text('Calibration Field Sheet',
            style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                if (_mixers.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _mixers.any(
                            (m) => m['code'].toString() == _mixer.text.trim())
                        ? _mixer.text.trim()
                        : null,
                    decoration: const InputDecoration(labelText: 'Mixer'),
                    items: _mixers
                        .map((m) => DropdownMenuItem<String>(
                              value: m['code'].toString(),
                              child: Text('${m['code']} — ${m['name']}'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _mixer.text = v);
                    },
                  )
                else
                  TextField(
                    controller: _mixer,
                    decoration: InputDecoration(
                      labelText: 'Mixer',
                      hintText: 'e.g. 307',
                      suffixIcon: _loadingMixers
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)))
                          : IconButton(
                              onPressed: _loadMixers,
                              icon: const Icon(Icons.refresh)),
                    ),
                  ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Calibration date'),
                  subtitle: Text(dateText),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: pickDate,
                ),
                InputDecorator(
                  decoration:
                      const InputDecoration(labelText: 'Operator / Entrant'),
                  child: Text(widget.session.user.fullName),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Calibration notes / site',
                    hintText: 'e.g. Koton Karfi',
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ExpansionTile(
              initiallyExpanded: true,
              title: const Text('Weights & Moisture',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                numField(_container, 'Container weight', suffix: 'kg'),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: numField(_stoneMoisture, 'Stone moisture',
                          suffix: '%')),
                  const SizedBox(width: 10),
                  Expanded(
                      child: numField(_sandMoisture, 'Sand moisture',
                          suffix: '%')),
                ]),
                const SizedBox(height: 10),
                numField(_cementSafety, 'Cement safety factor',
                    suffix: '%', enabled: canEditSafetyFactor),
                if (!canEditSafetyFactor)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Set by CEH Admin',
                          style:
                              TextStyle(color: Colors.black54, fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Cement Calibration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          trialCard('Cement FULL'),
          trialCard('Cement HALF'),
          const SizedBox(height: 10),
          const Text('Granite / Stone Calibration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          trialCard('Stone 5 cm'),
          trialCard('Stone 8 cm'),
          trialCard('Stone 11 cm'),
          const SizedBox(height: 10),
          const Text('Sand Calibration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          trialCard('Sand 5 cm'),
          trialCard('Sand 8 cm'),
          trialCard('Sand 11 cm'),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: (_saving || _submitted) ? null : _saveDraft,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(_calibrationId == null
                  ? 'Save Draft'
                  : 'Save Draft #$_calibrationId'),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: (_calibrationId == null || _submitting || _submitted)
                ? null
                : _submitCalibration,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_submitted ? Icons.lock : Icons.send_outlined),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                _submitted ? 'Submitted — Locked' : 'Submit Calibration',
              ),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: preview,
            icon: const Icon(Icons.analytics_outlined),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Preview Calibration Data'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Trial {
  final weight = TextEditingController();
  final counts = TextEditingController();

  void dispose() {
    weight.dispose();
    counts.dispose();
  }
}
