import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/internal_navigation.dart';
import '../models/session.dart';

class CalibrationDataScreen extends StatefulWidget {
  const CalibrationDataScreen({super.key, required this.session});
  final CehSession session;

  @override
  State<CalibrationDataScreen> createState() => _CalibrationDataScreenState();
}

class _CalibrationDataScreenState extends State<CalibrationDataScreen> {
  final _api = const CehApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.approvedCalibrations(widget.session);
      if (!mounted) return;
      setState(() => _items = items);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.code);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _n(dynamic value, {int decimals = 2}) {
    final number = double.tryParse(value?.toString() ?? '');
    return number == null ? '—' : number.toStringAsFixed(decimals);
  }

  List<Map<String, dynamic>> _results(Map<String, dynamic> c) =>
      (c['results'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  String _name(Map<String, dynamic> r) {
    final m = (r['material'] ?? '').toString();
    if (m == 'CEMENT_FULL') return 'Cement FULL';
    if (m == 'CEMENT_HALF') return 'Cement HALF';
    final gate = double.tryParse(r['gate_cm']?.toString() ?? '');
    final suffix = gate == null ? '' : ' ${gate.toStringAsFixed(0)} cm';
    if (m == 'STONE') return 'Stone$suffix';
    if (m == 'SAND') return 'Sand$suffix';
    return m;
  }

  Map<String, List<Map<String, dynamic>>> _grouped() {
    final g = <String, List<Map<String, dynamic>>>{};
    for (final c in _items) {
      final mixer = (c['mixer_code'] ?? 'Unknown').toString();
      g.putIfAbsent(mixer, () => []).add(c);
    }
    return g;
  }

  Widget _card(Map<String, dynamic> c, bool latest) {
    final results = _results(c);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: latest,
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Calibration #${c['id']}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            if (latest)
              const Chip(
                label: Text('CURRENT'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        subtitle: Text(
          '${c['calibration_date']}'
          '${(c['calibration_notes'] ?? '').toString().isEmpty ? '' : ' • ${c['calibration_notes']}'}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              Text('Container: ${_n(c['container_weight_kg'])} kg'),
              Text('Stone moisture: ${_n(c['stone_moisture_pct'])}%'),
              Text('Sand moisture: ${_n(c['sand_moisture_pct'])}%'),
              Text('Cement safety: ${_n(c['cement_safety_factor_pct'])}%'),
            ],
          ),
          const SizedBox(height: 12),
          for (final r in results)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _name(r),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${_n(r['kg_per_count'], decimals: 4)} kg/count',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          const Divider(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Entered by: ${c['entered_by_name']}'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Approved by: ${c['reviewed_by_name'] ?? 'CEH Admin'}',
            ),
          ),
          if ((c['reviewed_at'] ?? '').toString().isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Approved: ${c['reviewed_at']}'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped();
    final mixers = grouped.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Calibration Data',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          ...cehHomeAction(context),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load calibration data: $_error'))
              : _items.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No approved calibrations yet.\n\n'
                          'Only Admin-approved calibration data appears here.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        children: [
                          const Text(
                            'Approved calibration records',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'The newest approved calibration for each mixer is '
                            'marked CURRENT. These values are read-only.',
                          ),
                          const SizedBox(height: 18),
                          for (final mixer in mixers) ...[
                            Text(
                              'Mixer $mixer',
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (var i = 0; i < grouped[mixer]!.length; i++)
                              _card(grouped[mixer]![i], i == 0),
                            const SizedBox(height: 14),
                          ],
                        ],
                      ),
                    ),
    );
  }
}
