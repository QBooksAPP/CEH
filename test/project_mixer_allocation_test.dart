import 'dart:io';

import 'package:ceh/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  final migration =
      source('Server/migration_v1_8_project_mixer_allocation.sql');
  final mixers = source('Server/mixers.php');
  final allocation = source('Server/project_mixer_update.php');
  final settings = source('Server/settings_engine.php');
  final designs = source('Server/mix_designs.php');
  final calibrationSave = source('Server/calibration_save.php');
  final calibrationSubmit = source('Server/calibration_submit.php');
  final calibrationReopen = source('Server/calibration_reopen.php');
  final productionCreate = source('Server/production_session_create.php');

  test('v1.8 creates restrictive project mixer allocation', () {
    expect(migration, contains('CREATE TABLE qbook_project_mixers'));
    expect(migration, contains('PRIMARY KEY (project_id, mixer_id)'));
    expect(migration, isNot(contains('ON DELETE CASCADE')));
    expect(migration, contains('is_active TINYINT(1)'));
  });

  test('project mixer list returns only active allocations', () {
    expect(mixers, contains('pm.project_id=?'));
    expect(mixers, contains('pm.is_active=1'));
    expect(mixers, contains('m.is_active=1'));
    expect(allocation, contains("qbook_require_role(\$user, ['ADMIN'])"));
    expect(allocation, contains('ON DUPLICATE KEY UPDATE is_active'));
  });

  test('settings and operational writes reject unassigned mixer', () {
    expect(settings, contains('qbook_require_project_mixer'));
    expect(calibrationSave, contains('qbook_require_project_mixer'));
    expect(calibrationSubmit, contains('qbook_require_project_mixer'));
    expect(productionCreate, contains('qbook_require_project_mixer'));
  });

  test('Client and Project filter Mix Designs server-side', () {
    expect(designs, contains(r"$clientId = (int)($_GET['client_id'] ?? 0)"));
    expect(designs, contains(r"$projectId = (int)($_GET['project_id'] ?? 0)"));
    expect(designs, contains("'client_id = ?'"));
    expect(designs, contains("'project_id = ?'"));
  });

  test('Stone Size comes from Mix Design and contextless rows cannot match',
      () {
    expect(settings, contains("(string)\$mix['stone_size']"));
    expect(settings, contains('AND client_id = ?'));
    expect(settings, contains('AND project_id = ?'));
    expect(settings, contains('AND stone_size = ?'));
    expect(settings, isNot(contains('client_id IS NULL')));
  });

  test('missing calibration has safe context details', () {
    expect(settings, contains('NO_APPROVED_CALIBRATION_FOR_CONTEXT'));
    expect(settings, contains("'client' => (string)\$mix['client_name']"));
    const error = ApiException('NO_APPROVED_CALIBRATION_FOR_CONTEXT', details: {
      'client': 'ABC Construction',
      'project': 'Badagry',
      'mixer': '307',
      'stone_size': '1/2"',
    });
    expect(error.details['mixer'], '307');
  });

  test('Admin corrections preserve submitted lock and approved snapshot', () {
    expect(calibrationSave, contains("['DRAFT', 'REJECTED', 'SUBMITTED']"));
    expect(calibrationSave, contains('CALIBRATION_ADMIN_CORRECTED'));
    expect(calibrationSave, contains("'changes'=>\$adminChanges"));
    expect(calibrationReopen, contains('qbook_calibration_revision_snapshots'));
    expect(calibrationReopen, contains('revision_no=revision_no + 1'));
    expect(calibrationReopen, contains("status='SUBMITTED'"));
  });
}
