import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/internal_navigation.dart';
import '../core/view_mode.dart';
import '../models/session.dart';
import '../models/calibration_record.dart';
import '../models/mixer_context.dart';
import '../widgets/mixer_context_header.dart';
import 'calibration_field_sheet_screen.dart';
import 'calibration_history_screen.dart';

class CalibrationRecordsScreen extends StatefulWidget {
  const CalibrationRecordsScreen(
      {super.key, required this.session, this.mixerContext});
  final CehSession session;
  final MixerContext? mixerContext;
  @override
  State<CalibrationRecordsScreen> createState() =>
      _CalibrationRecordsScreenState();
}

class _CalibrationRecordsScreenState extends State<CalibrationRecordsScreen> {
  final _api = const CehApiClient();
  List<CalibrationRecord> _records = [];
  bool _loading = true;
  String? _error;
  String _lifecycle = 'ACTIVE';
  String _stoneFilter = 'ALL';

  bool get _admin => isUiAdmin(context, widget.session);
  List<CalibrationRecord> get _visibleRecords => _stoneFilter == 'ALL'
      ? _records
      : _records.where((record) => record.stoneSize == _stoneFilter).toList();

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
      final records = await _api.calibrationRecords(
        widget.session,
        lifecycle: _admin ? _lifecycle : 'ACTIVE',
        includeAllOperators: _admin,
        mixerId: widget.mixerContext?.id,
        clientId: widget.mixerContext?.assignment?.clientId,
        projectId: widget.mixerContext?.assignment?.projectId,
      );
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
          session: widget.session,
          calibration: record,
          mixerContext: widget.mixerContext,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _revise(CalibrationRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create calibration revision?'),
        content: const Text(
          'This calibration is approved. Editing it will create a new '
          'revision. The previous approved revision will remain preserved '
          'in History.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Create Revision'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final result = await _api.reopenCalibration(
        widget.session,
        calibrationId: record.id,
        reason: 'Admin created a correction revision',
      );
      if (!mounted) return;
      final revision =
          (result['new_revision_no'] as num? ?? record.revisionNo + 1).toInt();
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CalibrationFieldSheetScreen(
            session: widget.session,
            calibration: record.asRevision(revision),
            mixerContext: widget.mixerContext,
          ),
        ),
      );
      if (mounted) _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create revision: ${error.code}')),
        );
      }
    }
  }

  Future<void> _history(CalibrationRecord record) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CalibrationHistoryScreen(session: widget.session, record: record),
        ),
      );

  Future<void> _archive(CalibrationRecord record) async {
    final action = record.isArchived ? 'RESTORE' : 'ARCHIVE';
    await _api.updateRecordLifecycle(
      widget.session,
      recordType: 'CALIBRATION',
      recordId: record.id,
      action: action,
    );
    if (mounted) _load();
  }

  Color _statusColor(String status) => switch (status) {
        'APPROVED' => Colors.green,
        'REJECTED' => Colors.red,
        'SUBMITTED' => Colors.orange,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_admin ? 'Calibration Records' : 'My Calibrations'),
          actions: [
            ...cehHomeAction(context),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_admin)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ACTIVE', label: Text('Active')),
                    ButtonSegment(value: 'ARCHIVED', label: Text('Archived')),
                    ButtonSegment(value: 'ALL', label: Text('All')),
                  ],
                  selected: {_lifecycle},
                  onSelectionChanged: (value) {
                    setState(() => _lifecycle = value.first);
                    _load();
                  },
                ),
              ),
            if (widget.mixerContext != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: MixerContextHeader(context: widget.mixerContext!),
              ),
            if (widget.mixerContext != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: DropdownButtonFormField<String>(
                  initialValue: _stoneFilter,
                  decoration:
                      const InputDecoration(labelText: 'Stone Size Filter'),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('All')),
                    DropdownMenuItem(value: '3/8"', child: Text('3/8"')),
                    DropdownMenuItem(value: '1/2"', child: Text('1/2"')),
                    DropdownMenuItem(
                        value: '3/4 Down', child: Text('3/4 Down')),
                  ],
                  onChanged: (value) =>
                      setState(() => _stoneFilter = value ?? 'ALL'),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Text('Could not load calibrations: $_error'))
                      : _visibleRecords.isEmpty
                          ? const Center(
                              child: Text('No calibration records yet.'))
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _visibleRecords.length,
                                itemBuilder: (_, index) {
                                  final record = _visibleRecords[index];
                                  final mixer = record.mixer;
                                  final status = record.status;
                                  final editable = record.canEdit ||
                                      (_admin && status == 'SUBMITTED');
                                  return Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  record.clientName.isEmpty
                                                      ? 'Calibration #${record.id}'
                                                      : record.clientName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                              Chip(
                                                label: Text(status),
                                                labelStyle: TextStyle(
                                                  color: _statusColor(status),
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            '${record.projectName.isEmpty ? 'Historical context' : record.projectName} • Mixer ${mixer['code']} • ${record.stoneSize.isEmpty ? 'Stone size not recorded' : record.stoneSize}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                              '$status • Rev ${record.revisionNo}'),
                                          if (_admin &&
                                              record.enteredByName.isNotEmpty)
                                            Text(
                                                'Operator: ${record.enteredByName}'),
                                          Text(
                                            'Calibration date: ${record.calibrationDate}',
                                          ),
                                          if (record.notes.isNotEmpty)
                                            Text('Notes: ${record.notes}'),
                                          if (status == 'REJECTED') ...[
                                            const Divider(),
                                            Text(
                                              'Rejection reason: ${record.rejectionReason ?? 'Not recorded'}',
                                              style: const TextStyle(
                                                color: Colors.red,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            Text(
                                              'Rejected: ${record.reviewedAt ?? 'Date unavailable'}',
                                            ),
                                          ],
                                          if (_admin &&
                                              status == 'APPROVED') ...[
                                            const SizedBox(height: 12),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                FilledButton.icon(
                                                  onPressed: record.isArchived
                                                      ? null
                                                      : () => _revise(record),
                                                  icon: const Icon(
                                                      Icons.edit_note),
                                                  label: const Text(
                                                      'Edit / Revise'),
                                                ),
                                                OutlinedButton.icon(
                                                  onPressed: () =>
                                                      _history(record),
                                                  icon:
                                                      const Icon(Icons.history),
                                                  label: const Text('History'),
                                                ),
                                                OutlinedButton.icon(
                                                  onPressed: () =>
                                                      _archive(record),
                                                  icon: Icon(
                                                    record.isArchived
                                                        ? Icons.unarchive
                                                        : Icons
                                                            .archive_outlined,
                                                  ),
                                                  label: Text(
                                                    record.isArchived
                                                        ? 'Restore'
                                                        : 'Archive',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ] else if (editable) ...[
                                            const SizedBox(height: 12),
                                            FilledButton.icon(
                                              onPressed: () => _edit(record),
                                              icon: const Icon(
                                                  Icons.edit_outlined),
                                              label: Text(
                                                status == 'REJECTED'
                                                    ? 'Edit & Resubmit'
                                                    : 'Continue Editing',
                                              ),
                                            ),
                                          ] else
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 10),
                                              child: Text(
                                                '$status — Locked',
                                                textAlign: TextAlign.right,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      );
}
