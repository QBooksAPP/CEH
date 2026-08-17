import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/session.dart';

class CalibrationReviewScreen extends StatefulWidget {
  const CalibrationReviewScreen({super.key, required this.session});
  final CehSession session;

  @override
  State<CalibrationReviewScreen> createState() =>
      _CalibrationReviewScreenState();
}

class _CalibrationReviewScreenState extends State<CalibrationReviewScreen> {
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
      final items = await _api.adminCalibrations(widget.session);
      if (!mounted) return;
      setState(() => _items = items);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.code);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _number(dynamic value, {int decimals = 2}) {
    final n = double.tryParse(value?.toString() ?? '');
    return n == null ? '—' : n.toStringAsFixed(decimals);
  }

  String _resultName(Map<String, dynamic> r) {
    final material = (r['material'] ?? '').toString();
    if (material == 'CEMENT_FULL') return 'Cement FULL';
    if (material == 'CEMENT_HALF') return 'Cement HALF';
    final label = material == 'STONE' ? 'Stone' : 'Sand';
    return '$label ${_number(r['gate_cm'], decimals: 0)} cm';
  }

  List<Map<String, dynamic>> _maps(dynamic raw) =>
      (raw as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  Future<void> _review(Map<String, dynamic> item, String action) async {
    var reason = '';

    if (action == 'REJECT') {
      final controller = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reject calibration'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Tell the operator what must be corrected',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) Navigator.pop(context, text);
              },
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (result == null || result.isEmpty) return;
      reason = result;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Approve calibration?'),
          content: Text(
            'You are approving calibration #${item['id']} for '
            'mixer ${item['mixer_code']} after reviewing its results.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Approve'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    try {
      await _api.reviewCalibration(
        widget.session,
        calibrationId: (item['id'] as num).toInt(),
        action: action,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'APPROVE'
                ? 'Calibration approved.'
                : 'Calibration rejected.',
          ),
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Review failed: ${e.code}')),
      );
    }
  }

  Future<void> _reopen(Map<String, dynamic> item) async {
    final controller = TextEditingController(
      text: 'Approval reopened for further review',
    );
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reopen approved calibration?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Calibration #${item['id']} will return to SUBMITTED '
              'and appear in Waiting for Approval.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(context, text);
            },
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;

    try {
      await _api.reopenCalibration(
        widget.session,
        calibrationId: (item['id'] as num).toInt(),
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Approval reopened. Calibration is SUBMITTED again.'),
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reopen: ${e.code}')),
      );
    }
  }

  Widget _metadata(Map<String, dynamic> c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Date: ${c['calibration_date']}'),
        Text('Operator: ${c['entered_by_name']}'),
        if ((c['calibration_notes'] ?? '').toString().isNotEmpty)
          Text('Site / notes: ${c['calibration_notes']}'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 18,
          runSpacing: 5,
          children: [
            Text('Container: ${_number(c['container_weight_kg'])} kg'),
            Text('Stone moisture: ${_number(c['stone_moisture_pct'])}%'),
            Text('Sand moisture: ${_number(c['sand_moisture_pct'])}%'),
            Text(
              'Cement safety: ${_number(c['cement_safety_factor_pct'])}%',
            ),
            Text('Revision: ${c['revision_no']}'),
          ],
        ),
      ],
    );
  }

  Widget _resultCard(
    Map<String, dynamic> result,
    List<Map<String, dynamic>> trials,
  ) {
    final material = result['material']?.toString();
    final gate = double.tryParse(result['gate_cm']?.toString() ?? '');
    final matching = trials.where((t) {
      if (t['material']?.toString() != material) return false;
      final tg = double.tryParse(t['gate_cm']?.toString() ?? '');
      if (gate == null && tg == null) return true;
      if (gate == null || tg == null) return false;
      return (gate - tg).abs() < 0.01;
    }).toList()
      ..sort((a, b) =>
          (a['trial_no'] as num).toInt().compareTo((b['trial_no'] as num).toInt()));

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        title: Text(
          _resultName(result),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          'Result: ${_number(result['kg_per_count'], decimals: 6)} kg/count',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Avg weight\n${_number(result['avg_total_weight_kg'])} kg',
                ),
              ),
              Expanded(
                child: Text(
                  'Avg counts\n${_number(result['avg_counts'])}',
                ),
              ),
              Expanded(
                child: Text(
                  'Net dry\n${_number(result['net_dry_weight_kg'])} kg',
                ),
              ),
            ],
          ),
          if (matching.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Individual trials',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 6),
            for (final t in matching)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text('Trial ${t['trial_no']}'),
                    ),
                    Expanded(
                      child: Text(
                        '${_number(t['total_weight_kg'])} kg',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${_number(t['counts'])} counts',
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _calibrationCard(Map<String, dynamic> c) {
    final status = (c['status'] ?? '').toString();
    final results = _maps(c['results']);
    final trials = _maps(c['trials']);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: status == 'SUBMITTED',
        title: Text(
          'Mixer ${c['mixer_code']} • Calibration #${c['id']}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(status),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _metadata(c),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Calculated Calibration Results',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
          if (results.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('No calculated results found.'),
              ),
            )
          else
            for (final r in results) _resultCard(r, trials),
          const SizedBox(height: 16),
          if (status == 'SUBMITTED')
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _review(c, 'REJECT'),
                    icon: const Icon(Icons.close),
                    label: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _review(c, 'APPROVE'),
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                  ),
                ),
              ],
            )
          else if (status == 'APPROVED')
            OutlinedButton.icon(
              onPressed: () => _reopen(c),
              icon: const Icon(Icons.undo),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Reopen Approval'),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final waiting =
        _items.where((c) => c['status']?.toString() == 'SUBMITTED').toList();
    final approved =
        _items.where((c) => c['status']?.toString() == 'APPROVED').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Calibration Review',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load: $_error'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Waiting for Approval (${waiting.length})',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (waiting.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'No calibrations are waiting for approval.',
                            ),
                          ),
                        )
                      else
                        for (final c in waiting) _calibrationCard(c),
                      const SizedBox(height: 18),
                      Text(
                        'Approved (${approved.length})',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (approved.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No approved calibrations yet.'),
                          ),
                        )
                      else
                        for (final c in approved) _calibrationCard(c),
                    ],
                  ),
                ),
    );
  }
}
