import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  final migration = source('Server/migration_v1_7_job_context.sql');
  final calibrationSave = source('Server/calibration_save.php');
  final calibrationSubmit = source('Server/calibration_submit.php');
  final mixCreate = source('Server/mix_design_create.php');
  final mixUpdate = source('Server/mix_design_update.php');
  final mixValidate = source('Server/mix_design_validate.php');
  final mixList = source('Server/mix_designs.php');
  final settings = source('Server/settings_engine.php');
  final productionCreate = source('Server/production_session_create.php');

  test('v1.7 adds restrictive nullable historical context links', () {
    expect(migration, contains('CREATE TABLE qbook_projects'));
    expect(migration, contains('client_id BIGINT UNSIGNED NOT NULL'));
    expect(migration, contains('ADD COLUMN project_id BIGINT UNSIGNED NULL'));
    expect(migration, contains('ON DELETE RESTRICT'));
    expect(migration, isNot(contains('ON DELETE CASCADE')));
    expect(migration, contains('No historical context is guessed'));
  });

  test('stone sizes are restricted to the approved three values', () {
    for (final size in ['3/8"', '1/2"', '3/4 Down']) {
      expect(migration, contains("'$size'"));
    }
    expect(calibrationSave, contains('qbook_stone_size'));
    expect(mixCreate, contains('qbook_stone_size'));
    expect(mixUpdate, contains('qbook_stone_size'));
  });

  test('operator calibration safety and moisture limits are server-side', () {
    expect(calibrationSave, contains(": 2.0;"));
    expect(calibrationSave, contains(r'$stoneMoisture > 10'));
    expect(calibrationSave, contains(r'$sandMoisture > 10'));
    expect(calibrationSubmit, contains('MOISTURE_MUST_BE_0_TO_10_PERCENT'));
  });

  test('CLIENT validation is manual, audited and required for operators', () {
    expect(mixCreate, contains("? 'PENDING_VALIDATION' : null"));
    expect(mixValidate, contains("['VALIDATED','REQUIRES_REVISION']"));
    expect(mixValidate, contains('CLIENT_MIX_VALIDATION_CHANGED'));
    expect(mixUpdate, contains('old_client_validation_status'));
    expect(mixUpdate, contains('client_validation_reset'));
    expect(mixList, contains("client_validation_status = 'VALIDATED'"));
    expect(settings, contains('CLIENT_MIX_NOT_VALIDATED'));
  });

  test('CLIENT materials are preserved and CALCULATED sand is balanced', () {
    expect(mixCreate, contains(r"$sandKg = (float)$input['sand_kg']"));
    expect(mixUpdate, contains(r"? (float)$input['sand_kg']"));
    expect(mixCreate, contains(r'$sandVolume ='));
    expect(mixCreate, contains(r'$sandKg = $sandVolume * $sandSg * 1000'));
    expect(mixUpdate, contains(r'$sandKg ='));
    expect(mixUpdate, contains(r'$sandVolume * $sandSg * 1000'));
  });

  test('settings require exact Client Project Mixer and Stone compatibility',
      () {
    expect(settings, contains('WHERE mixer_id = ?'));
    expect(settings, contains('AND client_id = ?'));
    expect(settings, contains('AND project_id = ?'));
    expect(settings, contains('AND stone_size = ?'));
    expect(settings, contains('NO_APPROVED_CALIBRATION_FOR_CONTEXT'));
  });

  test('production requires an active project belonging to the client', () {
    expect(productionCreate,
        contains('WHERE id=? AND client_id=? AND is_active=1'));
    expect(productionCreate, contains('ACTIVE_CLIENT_PROJECT_REQUIRED'));
    expect(productionCreate, contains(r"$project['name']"));
    expect(productionCreate, contains('project_id'));
  });
}
