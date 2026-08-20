import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  final migration = source('Server/migration_v1_9_record_lifecycle.sql');
  final lifecycle = source('Server/record_lifecycle.php');
  final clients = source('Server/clients.php');
  final projects = source('Server/projects.php');
  final calibrations = source('Server/calibration_admin_list.php');
  final calibrationRecords = source('Server/calibration_records.php');
  final designs = source('Server/mix_designs.php');
  final settings = source('Server/settings_engine.php');
  final productionSessions = source('Server/production_sessions.php');

  test('v1.9 adds reversible archive metadata without destructive backfill',
      () {
    expect(migration, contains('ALTER TABLE qbook_clients'));
    expect(migration, contains('ALTER TABLE qbook_projects'));
    expect(migration, contains('ALTER TABLE qbook_calibrations'));
    expect(migration, contains('ALTER TABLE qbook_mix_designs'));
    expect(migration, isNot(contains('ON DELETE CASCADE')));
    expect(migration, isNot(contains('UPDATE qbook_')));
  });

  test('all lifecycle mutations are Admin-only and audited transactionally',
      () {
    expect(lifecycle, contains("qbook_require_role(\$user, ['ADMIN'])"));
    expect(lifecycle, contains('lifecycle_audit'));
    expect(lifecycle, contains('beginTransaction'));
    expect(lifecycle, contains('UTC_TIMESTAMP()'));
  });

  test('permanent deletion checks operational and future FK references', () {
    expect(lifecycle, contains('DELETE_BLOCKED_BY_REFERENCE'));
    expect(lifecycle, contains('DELETE_BLOCKED_BY_AUDIT_EVIDENCE'));
    expect(lifecycle, contains('qbook_production_sessions'));
    expect(lifecycle, contains('qbook_production_settings'));
    expect(lifecycle, contains('qbook_calibration_revision_snapshots'));
    expect(lifecycle, contains('information_schema.KEY_COLUMN_USAGE'));
  });

  test('Operators receive only active Client Project and calibration records',
      () {
    expect(clients, contains('archived_at IS NULL'));
    expect(projects, contains('p.archived_at IS NULL'));
    expect(projects, contains('c.archived_at IS NULL'));
    expect(calibrationRecords, contains('c.archived_at IS NULL'));
    expect(calibrationRecords, contains('p.archived_at IS NULL'));
    expect(designs, contains('p.archived_at IS NULL'));
    expect(productionSessions, contains('p.archived_at IS NULL'));
  });

  test('Admin lifecycle lists support Active Archived and All', () {
    for (final endpoint in [clients, projects, calibrations, designs]) {
      expect(endpoint, contains('ARCHIVED'));
      expect(endpoint, contains('ALL'));
    }
  });

  test('archived calibration and Mix Design cannot feed new Settings', () {
    expect(settings, contains('AND archived_at IS NULL'));
    expect(settings, contains("status = 'APPROVED'"));
  });

  test('only an untouched Draft calibration can reach deletion cleanup', () {
    expect(lifecycle, contains("(string)\$record['status']!=='DRAFT'"));
    expect(lifecycle, contains("\$record['submitted_at']!==null"));
    expect(lifecycle, contains("\$record['reviewed_at']!==null"));
  });
}
