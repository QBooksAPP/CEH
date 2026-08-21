import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/internal_navigation.dart';
import '../models/calibration_record.dart';
import '../models/session.dart';

class CalibrationHistoryScreen extends StatefulWidget {
  const CalibrationHistoryScreen({
    super.key,
    required this.session,
    required this.record,
  });

  final CehSession session;
  final CalibrationRecord record;

  @override
  State<CalibrationHistoryScreen> createState() =>
      _CalibrationHistoryScreenState();
}

class _CalibrationHistoryScreenState extends State<CalibrationHistoryScreen> {
  final _api = const CehApiClient();
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.calibrationHistory(
        widget.session,
        widget.record.id,
      );
      if (mounted) setState(() => _data = data);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  String _pretty(Object? value) {
    if (value == null) return 'Not recorded';
    return const JsonEncoder.withIndent('  ').convert(value);
  }

  @override
  Widget build(BuildContext context) {
    final history = (_data?['history'] as List?)?.cast<Map>() ?? const [];
    final item =
        history.isEmpty ? null : Map<String, dynamic>.from(history.first);
    final snapshots = (item?['revision_snapshots'] as List?) ?? const [];
    final audit = (item?['audit'] as List?) ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text('Calibration #${widget.record.id} History'),
        actions: cehHomeAction(context),
      ),
      body: _error != null
          ? Center(child: Text('Could not load history: $_error'))
          : item == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.radio_button_checked,
                          color: Colors.green,
                        ),
                        title: Text(
                          'Rev ${item['revision_no']} — ${item['status']} — Current',
                        ),
                        subtitle: Text(
                          'Reviewed: ${item['reviewed_at'] ?? 'Not yet reviewed'}\n'
                          'Current values are the operational record.',
                        ),
                        isThreeLine: true,
                      ),
                    ),
                    for (final raw in snapshots)
                      _SnapshotCard(
                        snapshot: Map<String, dynamic>.from(raw as Map),
                        pretty: _pretty,
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'Audit trail',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    if (audit.isEmpty) const Text('No audit events recorded.'),
                    for (final raw in audit)
                      Card(
                        child: ListTile(
                          title: Text('${raw['event_type']}'),
                          subtitle: Text(
                            '${raw['created_at']} • ${raw['user_name']}\n${_pretty(raw['details'])}',
                          ),
                          isThreeLine: true,
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({required this.snapshot, required this.pretty});
  final Map<String, dynamic> snapshot;
  final String Function(Object?) pretty;

  @override
  Widget build(BuildContext context) {
    final evidence = snapshot['evidence'] as Map?;
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.history),
        title: Text(
          'Rev ${snapshot['revision_no']} — ${snapshot['status']} — Superseded',
        ),
        subtitle: Text(
          '${snapshot['captured_at']} • ${snapshot['captured_by_name']}\n'
          '${snapshot['reason'] ?? 'No reason recorded'}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Immutable revision evidence',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          SelectableText(pretty(evidence)),
        ],
      ),
    );
  }
}
