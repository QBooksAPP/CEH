import 'package:flutter/material.dart';
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
  final _mixer = TextEditingController(text: '307');
  final _notes = TextEditingController();
  final _container = TextEditingController();
  final _stoneMoisture = TextEditingController(text: '0.00');
  final _sandMoisture = TextEditingController(text: '0.00');
  final _cementSafety = TextEditingController(text: '2.00');
  late DateTime _date;

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

  String get dateText =>
      '${_date.day.toString().padLeft(2, '0')}/'
      '${_date.month.toString().padLeft(2, '0')}/'
      '${_date.year}';

  Future<void> pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  double n(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  Map<String, double> resultFor(String name) {
    final valid = trials[name]!
        .where(
          (t) =>
              t.weight.text.isNotEmpty &&
              t.counts.text.isNotEmpty &&
              n(t.counts) > 0,
        )
        .toList();

    if (valid.isEmpty) return {'trials': 0, 'kgpc': 0};

    final aw =
        valid.map((t) => n(t.weight)).reduce((a, b) => a + b) /
            valid.length;
    final ac =
        valid.map((t) => n(t.counts)).reduce((a, b) => a + b) /
            valid.length;

    double net = aw;
    if (name.startsWith('Stone')) {
      net = (aw - n(_container)) / (1 + n(_stoneMoisture) / 100);
    }
    if (name.startsWith('Sand')) {
      net = (aw - n(_container)) / (1 + n(_sandMoisture) / 100);
    }

    return {
      'trials': valid.length.toDouble(),
      'kgpc': ac > 0 ? net / ac : 0,
    };
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
            const Text(
              'Calibration Data Preview',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text('Mixer ${_mixer.text} • $dateText'),
            const SizedBox(height: 14),
            ...trials.keys.map((name) {
              final r = resultFor(name);
              final blank = r['trials']!.toInt() == 0;
              return Card(
                child: ListTile(
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    blank
                        ? (name == 'Cement HALF'
                            ? 'Not used — optional'
                            : 'No trials entered')
                        : '${r['trials']!.toInt()} valid trial(s)',
                  ),
                  trailing: blank
                      ? const Text('—')
                      : Text('${r['kgpc']!.toStringAsFixed(6)} kg/count'),
                ),
              );
            }),
            const SizedBox(height: 10),
            const Text(
              'Cement HALF is optional. Blank optional sections are ignored, '
              'not treated as zero calibration values.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Preview only. Save Draft and Submit will be connected to the '
              'CEH server next.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget numField(
    TextEditingController c,
    String label, {
    String? suffix,
    bool enabled = true,
  }) =>
      TextField(
        controller: c,
        enabled: enabled,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
        ),
      );

  Widget trialCard(String name) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ExpansionTile(
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            name == 'Cement HALF'
                ? 'Optional • up to 6 trials'
                : 'Up to 6 trials',
          ),
          childrenPadding:
              const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            for (int i = 0; i < 6; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${i + 1}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: numField(
                        trials[name]![i].weight,
                        'Total weight',
                        suffix: 'kg',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: numField(
                        trials[name]![i].counts,
                        'Counts',
                      ),
                    ),
                  ],
                ),
              )
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final canEditSafetyFactor = widget.session.user.isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Calibration Field Sheet',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _mixer,
                    decoration: const InputDecoration(
                      labelText: 'Mixer',
                      hintText: 'e.g. 307',
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Calibration date'),
                    subtitle: Text(dateText),
                    trailing:
                        const Icon(Icons.calendar_today),
                    onTap: pickDate,
                  ),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Operator / Entrant',
                    ),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ExpansionTile(
              initiallyExpanded: true,
              title: const Text(
                'Weights & Moisture',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              childrenPadding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                numField(
                  _container,
                  'Container weight',
                  suffix: 'kg',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: numField(
                        _stoneMoisture,
                        'Stone moisture',
                        suffix: '%',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: numField(
                        _sandMoisture,
                        'Sand moisture',
                        suffix: '%',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                numField(
                  _cementSafety,
                  'Cement safety factor',
                  suffix: '%',
                  enabled: canEditSafetyFactor,
                ),
                if (!canEditSafetyFactor)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Set by CEH Admin',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Cement Calibration',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          trialCard('Cement FULL'),
          trialCard('Cement HALF'),
          const SizedBox(height: 10),
          const Text(
            'Granite / Stone Calibration',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          trialCard('Stone 5 cm'),
          trialCard('Stone 8 cm'),
          trialCard('Stone 11 cm'),
          const SizedBox(height: 10),
          const Text(
            'Sand Calibration',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          trialCard('Sand 5 cm'),
          trialCard('Sand 8 cm'),
          trialCard('Sand 11 cm'),
          const SizedBox(height: 16),
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
