import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production workflow has only explicit manual activation', () {
    final workflow = File('.github/workflows/build-apk.yml').readAsStringSync();
    final triggers = workflow.split(RegExp(r'^on:\s*$', multiLine: true)).last.split(RegExp(r'^permissions:', multiLine: true)).first;
    expect(triggers, contains('workflow_dispatch:'));
    for (final event in ['push', 'pull_request', 'workflow_run', 'schedule', 'repository_dispatch']) {
      expect(triggers, isNot(contains('$event:')));
    }
    expect(triggers, contains('default: false'));
    expect(workflow, contains("github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main' && inputs.confirm_production_release == true"));
    expect(workflow, contains('environment: production-android'));
    expect(workflow, contains('--flavor production'));
  });
}
