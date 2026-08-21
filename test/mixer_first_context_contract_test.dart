import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  final contexts = source('Server/mixer_contexts.php');
  final allocations = source('Server/project_mixer_update.php');
  final calibrationRecords = source('Server/calibration_records.php');
  final calibrationReview = source('Server/calibration_admin_list.php');
  final settings = source('Server/settings_engine.php');
  final productionCreate = source('Server/production_session_create.php');
  final mixDesigns = source('Server/mix_designs.php');
  final settingsScreen = source('lib/screens/mix_design_settings_screen.dart');
  final productionScreen = source('lib/screens/production_log_screen.dart');
  final navigation = source('lib/screens/concrete_operations_screen.dart');

  test('Operators receive only active project-allocated mixers', () {
    expect(contexts,
        contains("qbook_require_role(\$user, ['ADMIN', 'OPERATOR'])"));
    expect(contexts,
        contains("if(\$user['role']!=='ADMIN' && \$active===[])continue"));
    expect(contexts, contains('project_archived'));
    expect(contexts, contains('client_archived'));
  });

  test('current assignment change retains inactive history', () {
    expect(allocations,
        contains('WHERE mixer_id=? AND project_id<>? AND is_active=1'));
    expect(allocations, contains('SET is_active=0'));
    expect(allocations, contains('FOR UPDATE'));
    expect(allocations, isNot(contains('DELETE FROM qbook_project_mixers')));
  });

  test('calibration lists filter by selected job context server-side', () {
    for (final field in ['mixer_id', 'client_id', 'project_id']) {
      expect(calibrationRecords, contains(field));
      expect(calibrationReview, contains(field));
    }
  });

  test('authoritative compatibility remains server-side', () {
    expect(settings, contains('qbook_require_project_mixer'));
    expect(settings, contains('NO_APPROVED_CALIBRATION_FOR_CONTEXT'));
    expect(productionCreate, contains('qbook_require_project_mixer'));
    expect(mixDesigns, contains("client_validation_status = 'VALIDATED'"));
  });

  test('same named designs stay distinct by Client and Project IDs', () {
    expect(mixDesigns, contains('client_id = ?'));
    expect(mixDesigns, contains('project_id = ?'));
    expect(mixDesigns, isNot(contains('WHERE name = ?')));
  });

  test('contextual child flows suppress redundant selectors', () {
    expect(settingsScreen, contains('if (widget.mixerContext == null)'));
    expect(settingsScreen, contains('stoneSize: _selectedDesign?.stoneSize'));
    expect(productionScreen, contains('mixerContext: widget.mixerContext'));
    expect(productionScreen, contains('!widget.mixerContext!.isOperational'));
    expect(navigation, contains('mixerContext: _mixer'));
    expect(navigation, contains('if (!_mixer.isOperational)'));
  });
}
