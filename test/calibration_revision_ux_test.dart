import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ceh/models/calibration_record.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  final recordsApi = source('Server/calibration_records.php');
  final reopenApi = source('Server/calibration_reopen.php');
  final historyApi = source('Server/calibration_history.php');
  final settingsEngine = source('Server/settings_engine.php');
  final recordsScreen = source('lib/screens/calibration_records_screen.dart');

  test('normal list is current calibration rows, never snapshot revisions', () {
    expect(recordsApi, contains('FROM qbook_calibrations c'));
    expect(
      recordsApi,
      isNot(contains('JOIN qbook_calibration_revision_snapshots')),
    );
    expect(recordsApi, contains("'revision_no' => (int)\$row['revision_no']"));
  });

  test(
    'Admin all-operator scope and operator ownership remain server-side',
    () {
      expect(recordsApi, contains("\$allOperators = \$isAdmin"));
      expect(recordsApi, contains("' AND c.entered_by = ?'"));
      expect(recordsScreen, contains('includeAllOperators: _admin'));
    },
  );

  test(
    'approved revision keeps id, increments revision and snapshots evidence',
    () {
      expect(reopenApi, contains('qbook_calibration_revision_snapshots'));
      expect(reopenApi, contains('revision_no=revision_no + 1'));
      expect(reopenApi, contains("'calibration_id' => \$id"));
      expect(recordsScreen, contains('Create Revision'));
      expect(recordsScreen, contains('record.asRevision(revision)'));
    },
  );

  test('history deliberately exposes immutable snapshots and audit', () {
    expect(historyApi, contains('snapshot_json'));
    expect(historyApi, contains("'evidence'=>"));
    expect(historyApi, contains('qbook_audit_log'));
    expect(recordsScreen, contains("label: const Text('History')"));
  });

  test('superseded or archived calibrations cannot feed settings', () {
    expect(settingsEngine, contains("status = 'APPROVED'"));
    expect(settingsEngine, contains('archived_at IS NULL'));
    expect(
      settingsEngine,
      isNot(contains('qbook_calibration_revision_snapshots')),
    );
  });

  test('revision model preserves same calibration identity', () {
    const record = CalibrationRecord(
      id: 14,
      mixer: {'code': '307'},
      calibrationDate: '2026-08-21',
      notes: '',
      containerWeightKg: 1,
      stoneMoisturePct: 2,
      sandMoisturePct: 3,
      cementSafetyFactorPct: 2,
      status: 'APPROVED',
      rejectionReason: null,
      reviewedAt: '2026-08-21',
      trials: [],
      revisionNo: 2,
    );
    final revision = record.asRevision(3);
    expect(revision.id, 14);
    expect(revision.revisionNo, 3);
    expect(revision.status, 'SUBMITTED');
  });
}
