import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/internal_navigation.dart';
import '../core/view_mode.dart';
import '../models/mix_design.dart';
import '../models/calibration_source.dart';
import '../models/production_settings.dart';
import '../models/session.dart';
import 'settings_history_screen.dart';

class MixDesignSettingsScreen extends StatefulWidget {
  const MixDesignSettingsScreen({super.key, required this.session});
  final CehSession session;
  @override
  State<MixDesignSettingsScreen> createState() =>
      _MixDesignSettingsScreenState();
}

class _MixDesignSettingsScreenState extends State<MixDesignSettingsScreen> {
  final _api = const CehApiClient();
  final _speed = TextEditingController();
  List<Map<String, dynamic>> _mixers = [];
  List<MixDesign> _designs = [];
  List<CalibrationSource> _calibrations = [];
  int? _mixerId;
  int? _designId;
  int _calibrationId = 0;
  bool _busy = true;
  ProductionSettingsResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _speed.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        _api.mixers(widget.session),
        _api.mixDesigns(widget.session),
        _api.approvedCalibrationSources(widget.session),
      ]);
      if (!mounted) return;
      setState(() {
        _mixers = values[0] as List<Map<String, dynamic>>;
        _designs =
            (values[1] as List<MixDesign>).where((d) => d.isActive).toList();
        _calibrations = values[2] as List<CalibrationSource>;
        _busy = false;
      });
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _error(e);
    }
  }

  Future<void> _calculate(bool apply) async {
    final speed = double.tryParse(_speed.text.trim());
    if (_mixerId == null || _designId == null || speed == null || speed <= 0) {
      _error('Select a mixer, active Mix Design, and valid conveyor speed.');
      return;
    }
    setState(() => _busy = true);
    final overrideId = isUiAdmin(context, widget.session) && _calibrationId > 0
        ? _calibrationId
        : null;
    try {
      final value = apply
          ? await _api.applySettings(widget.session,
              mixerId: _mixerId!,
              mixDesignId: _designId!,
              conveyorSpeed: speed,
              calibrationId: overrideId)
          : await _api.previewSettings(widget.session,
              mixerId: _mixerId!,
              mixDesignId: _designId!,
              conveyorSpeed: speed,
              calibrationId: overrideId);
      if (!mounted) return;
      setState(() {
        _result = value;
        _busy = false;
      });
      if (apply) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Production settings applied successfully.')));
      }
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _error(e);
    }
  }

  void _error(Object e) {
    if (!mounted) return;
    final text = e.toString().contains('NO_APPROVED_CALIBRATION')
        ? 'This mixer requires a latest APPROVED calibration before settings can be calculated.'
        : e.toString().replaceFirst('ApiException: ', '');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _line(String label, dynamic value, [String suffix = '']) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text('$value$suffix',
              style: const TextStyle(fontWeight: FontWeight.w800))
        ]),
      );

  List<CalibrationSource> get _mixerCalibrations => _calibrations
      .where((calibration) => calibration.mixerId == _mixerId)
      .toList();

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Mix Design Settings'), actions: [
        if (isUiAdmin(context, widget.session))
          IconButton(
              tooltip: 'Settings History',
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          SettingsHistoryScreen(session: widget.session))),
              icon: const Icon(Icons.history)),
        ...cehHomeAction(context),
      ]),
      body: _busy && r == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<int>(
                    initialValue: _mixerId,
                    decoration: const InputDecoration(labelText: 'Mixer'),
                    items: _mixers
                        .map((m) => DropdownMenuItem(
                            value: int.tryParse('${m['id']}'),
                            child: Text('${m['code']} — ${m['name']}')))
                        .toList(),
                    onChanged: (v) => setState(() {
                          _mixerId = v;
                          _calibrationId = 0;
                          _result = null;
                        })),
                if (isUiAdmin(context, widget.session)) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: ValueKey('calibration-$_mixerId-$_calibrationId'),
                    initialValue: _calibrationId,
                    decoration:
                        const InputDecoration(labelText: 'Calibration Source'),
                    items: [
                      const DropdownMenuItem(
                        value: 0,
                        child: Text('Latest Approved'),
                      ),
                      for (var i = 0; i < _mixerCalibrations.length; i++)
                        DropdownMenuItem(
                          value: _mixerCalibrations[i].id,
                          child: Text(
                            '${_mixerCalibrations[i].optionLabel}'
                            '${i == 0 ? ' • Latest' : ''}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _calibrationId = value ?? 0;
                      _result = null;
                    }),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                    initialValue: _designId,
                    decoration:
                        const InputDecoration(labelText: 'Active Mix Design'),
                    items: _designs
                        .map((d) => DropdownMenuItem(
                            value: d.id,
                            child: Text('${d.name} (${d.mode.apiValue})')))
                        .toList(),
                    onChanged: (v) => setState(() {
                          _designId = v;
                          _result = null;
                        })),
                const SizedBox(height: 12),
                TextField(
                    controller: _speed,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Conveyor speed')),
                const SizedBox(height: 12),
                const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Batch volume'),
                    trailing: Text('1.000 m³',
                        style: TextStyle(fontWeight: FontWeight.w900))),
                FilledButton.icon(
                    onPressed: _busy ? null : () => _calculate(false),
                    icon: const Icon(Icons.calculate_outlined),
                    label: const Text('Preview Settings')),
                if (r != null) ...[
                  const SizedBox(height: 16),
                  if (isUiAdmin(context, widget.session)) ...[
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(children: [
                              _line('Mixer',
                                  r.mixer['code'] ?? r.mixer['name'] ?? ''),
                              _line('Mix Design', r.mixDesign['name'] ?? ''),
                              _line(
                                  'Calibration Source',
                                  '#${r.calibration['id']} • Rev '
                                      '${r.calibration['revision_no']}'),
                              _line('Mode', r.mixDesign['design_mode'] ?? ''),
                              _line(
                                  'Production rate',
                                  r.productionRate.toStringAsFixed(2),
                                  ' m³/min'),
                              _line('Approx. time per 1.0 m³',
                                  r.minutesPerM3.toStringAsFixed(2), ' min'),
                              _line('Cement target', r.mix['cement_kg'] ?? 0,
                                  ' kg/m³'),
                              _line(
                                  'Cement FULL calibration',
                                  r.settings['cement_kg_per_count'] ?? '—',
                                  ' kg/count'),
                              _line('Required cement counts',
                                  r.settings['counts_per_m3'] ?? '—', '/m³'),
                              _line('Sand target', r.mix['sand_kg'] ?? 0,
                                  ' kg/m³'),
                              _line(
                                  'Sand target/count',
                                  r.settings['sand_target_kg_per_count'] ?? '—',
                                  ' kg/count'),
                              _line('Sand gate',
                                  r.settings['sand_gate_cm'] ?? '—', ' cm'),
                              _line('Granite target', r.mix['granite_kg'] ?? 0,
                                  ' kg/m³'),
                              _line(
                                  'Granite target/count',
                                  r.settings['granite_target_kg_per_count'] ??
                                      '—',
                                  ' kg/count'),
                              _line('Granite gate',
                                  r.settings['granite_gate_cm'] ?? '—', ' cm'),
                              _line('Design water', r.mix['water_l'] ?? 0,
                                  ' L/m³'),
                              _line(
                                  'Additional water',
                                  r.settings['additional_water_l'] ?? '—',
                                  ' L/m³'),
                              _line(
                                  'Water flow',
                                  r.settings['water_flow_lpm'] ?? '—',
                                  ' L/min'),
                            ]))),
                    for (final a in r.admixtures)
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${a['name']}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900)),
                                    _line(
                                        'Dosage',
                                        a['dosage_l_per_100kg'] ?? '—',
                                        ' L/100 kg cement'),
                                    _line('Cement',
                                        a['cement_kg_per_m3'] ?? '—', ' kg/m³'),
                                    _line(
                                        'Admixture requirement',
                                        a['admixture_l_per_m3'] ?? '—',
                                        ' L/m³'),
                                    _line('Dilution factor',
                                        a['dilution_factor'] ?? '—'),
                                    _line('Pure flow',
                                        a['pure_flow_lpm'] ?? '—', ' L/min'),
                                    _line(
                                        'Metered flow',
                                        a['metered_flow_lpm'] ??
                                            a['flow_lpm'] ??
                                            '—',
                                        ' L/min')
                                  ]))),
                  ] else ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          _line('Mixer',
                              r.mixer['code'] ?? r.mixer['name'] ?? ''),
                          _line('Mix Design', r.mixDesign['name'] ?? ''),
                          _line('Production Rate',
                              r.productionRate.toStringAsFixed(2), ' m³/min'),
                          _line('Cement Target', r.mix['cement_kg'] ?? 0,
                              ' kg/m³'),
                          _line('Counts', r.settings['counts_per_m3'] ?? '—'),
                          _line('Sand Gate Opening',
                              r.settings['sand_gate_cm'] ?? '—', ' cm'),
                          _line('Stone / Granite Gate Opening',
                              r.settings['granite_gate_cm'] ?? '—', ' cm'),
                          _line('Water Flow Rate',
                              r.settings['water_flow_lpm'] ?? '—', ' L/min'),
                          for (final a in r.admixtures)
                            _line(
                              'Admixture Flow Rate — ${a['name']}',
                              a['metered_flow_lpm'] ?? a['flow_lpm'] ?? '—',
                              ' L/min',
                            ),
                        ]),
                      ),
                    ),
                  ],
                  FilledButton.icon(
                      onPressed:
                          _busy || r.saved ? null : () => _calculate(true),
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(
                          r.saved ? 'Settings Applied' : 'Apply Settings')),
                ],
              ],
            ),
    );
  }
}
