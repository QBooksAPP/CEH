import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('candidate workflow is manual private artifact-only and read-token', () {
    final workflow =
        File('.github/workflows/production-candidate.yml').readAsStringSync();
    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, contains('contents: read'));
    expect(workflow, contains('github.event.repository.private == true'));
    expect(workflow, contains('inputs.confirm_candidate_only == true'));
    expect(workflow, contains('default: false'));
    expect(workflow, contains('persist-credentials: false'));
    expect(workflow, contains('approved_commit:'));
    expect(workflow, contains('actions/upload-artifact@v4'));
    for (final forbidden in [
      'push:',
      'pull_request:',
      'workflow_run:',
      'contents: write',
      'gh release',
      'scp ',
      'ssh ',
      'build-apk.yml'
    ]) {
      expect(workflow, isNot(contains(forbidden)));
    }
  });
  test('candidate verifies identity before preparing its private artifact', () {
    final helper = File('tools/production_candidate.py').readAsStringSync();
    expect(helper, contains("CODE = 97"));
    expect(helper, contains("VERSION = '0.4.0'"));
    expect(
        helper,
        contains(
            'f859045aba784241fd33f6df182a484d716012350ac9de64c88c9799cb79a30e'));
    expect(helper, contains('--dart-define=CEH_ENVIRONMENT=production'));
    expect(helper, contains('--dart-define=CEH_UPDATE_CHECKS=true'));
    expect(helper, contains('STOP: signer mismatch'));
    expect(helper.indexOf("isolation = inspect_apk_trust(apk, 'production')"),
        lessThan(helper.indexOf('output.mkdir()')));
    expect(helper.indexOf('STOP: signer mismatch'),
        lessThan(helper.indexOf('output.mkdir()')));
    expect(helper, contains('TemporaryDirectory'));
    expect(helper, isNot(contains('key.properties')));
  });
}
