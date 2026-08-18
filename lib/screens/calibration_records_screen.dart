import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/internal_navigation.dart';
import '../models/session.dart';
import '../models/calibration_record.dart';
import 'calibration_field_sheet_screen.dart';

class CalibrationRecordsScreen extends StatefulWidget {
  const CalibrationRecordsScreen({super.key, required this.session});
  final CehSession session;
  @override
  State<CalibrationRecordsScreen> createState() =>
      _CalibrationRecordsScreenState();
}

class _CalibrationRecordsScreenState extends State<CalibrationRecordsScreen> {
  final _api = const CehApiClient();
  List<CalibrationRecord> _records = [];
  bool _loading = true;
  String? _error;

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
      final records = await _api.calibrationRecords(widget.session);
      if (mounted) {
        setState(() {
          _records = records;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit(CalibrationRecord record) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CalibrationFieldSheetScreen(
                session: widget.session, calibration: record)));
    if (mounted) _load();
  }

  Color _statusColor(String status) => switch (status) {
        'APPROVED' => Colors.green,
        'REJECTED' => Colors.red,
        'SUBMITTED' => Colors.orange,
        _ => Colors.blue,
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My Calibrations'), actions: [
          ...cehHomeAction(context),
          IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
        ]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('Could not load calibrations: $_error'))
                : _records.isEmpty
                    ? const Center(child: Text('No calibration records yet.'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _records.length,
                          itemBuilder: (_, index) {
                            final record = _records[index];
                            final mixer = record.mixer;
                            final status = record.status;
                            final editable = record.canEdit;
                            return Card(
                                child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(children: [
                                          Expanded(
                                              child: Text(
                                                  '${mixer['code']} — ${mixer['name']}',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: 16))),
                                          Chip(
                                              label: Text(status),
                                              labelStyle: TextStyle(
                                                  color: _statusColor(status),
                                                  fontWeight: FontWeight.w900)),
                                        ]),
                                        Text(
                                            'Calibration date: ${record.calibrationDate}'),
                                        Text(
                                            'Site / notes: ${record.notes.isEmpty ? '—' : record.notes}'),
                                        if (status == 'REJECTED') ...[
                                          const Divider(),
                                          Text(
                                              'Rejection reason: ${record.rejectionReason ?? 'Not recorded'}',
                                              style: const TextStyle(
                                                  color: Colors.red,
                                                  fontWeight: FontWeight.w800)),
                                          Text(
                                              'Rejected: ${record.reviewedAt ?? 'Date unavailable'}'),
                                        ],
                                        if (editable) ...[
                                          const SizedBox(height: 12),
                                          FilledButton.icon(
                                              onPressed: () => _edit(record),
                                              icon: const Icon(
                                                  Icons.edit_outlined),
                                              label: Text(status == 'REJECTED'
                                                  ? 'Edit & Resubmit'
                                                  : 'Continue Editing')),
                                        ] else
                                          const Padding(
                                              padding: EdgeInsets.only(top: 10),
                                              child: Text('Locked — read only',
                                                  textAlign: TextAlign.right)),
                                      ],
                                    )));
                          },
                        )),
      );
}
