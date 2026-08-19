import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  final common = source('Server/production_report_common.php');
  final endpoint = source('Server/production_report_pdf.php');
  final sign = source('Server/production_session_sign.php');
  final migration = source('Server/migration_v1_6_production_reports.sql');
  final tcpdfStatic = source('Server/vendor/tcpdf/include/tcpdf_static.php');

  test('report references use an independent permanent sequence', () {
    expect(common, contains("'CEH-PR-' . str_pad"));
    expect(migration,
        contains('report_no BIGINT UNSIGNED NOT NULL AUTO_INCREMENT'));
    expect(
        migration,
        contains(
            'UNIQUE KEY uq_production_report_session (production_session_id)'));
    expect(migration, isNot(contains('ON DELETE CASCADE')));
  });

  test('one report number is issued during sign-off and reused', () {
    expect(sign, contains('production_report_issue(\$db, \$sessionId);'));
    expect(common, contains('WHERE production_session_id = ?'));
    expect(common, contains("if (!\$report)"));
  });

  test('official reports require signed status and existing sign-off evidence',
      () {
    expect(endpoint, contains("!== 'SIGNED'"));
    expect(endpoint, contains("'SIGNED_SESSION_REQUIRED'"));
    expect(endpoint, contains('FROM qbook_production_signoffs'));
    expect(endpoint, contains("'SIGNED_EVIDENCE_MISSING'"));
  });

  test('operator ownership and admin access use the production authorization',
      () {
    expect(endpoint, contains('production_can_access(\$user, \$session)'));
    expect(endpoint,
        contains("qbook_require_role(\$user, ['ADMIN', 'OPERATOR'])"));
    expect(endpoint, contains("'FORBIDDEN'"));
  });

  test('PDF uses authoritative signed totals and session snapshots', () {
    expect(endpoint, contains("\$signoff['load_count']"));
    expect(endpoint, contains("\$signoff['total_m3']"));
    for (final field in [
      'client_name',
      'project_site',
      'mixer_code_snapshot',
      'mixer_name_snapshot',
      'operator_name_snapshot',
    ]) {
      expect(endpoint, contains("\$session['$field']"));
    }
  });

  test('representative and original PNG signature are embedded', () {
    expect(endpoint, contains('representative_name'));
    expect(endpoint, contains('signature_data'));
    expect(endpoint, contains("'@' . \$signoff['signature_data']"));
    expect(endpoint, contains("signature_mime'] !== 'image/png'"));
  });

  test('PDF is streamed from memory without a public file', () {
    expect(endpoint, contains("->Output(\$reference . '.pdf', 'S')"));
    expect(endpoint, contains("header('Content-Type: application/pdf')"));
    expect(endpoint, isNot(contains("->Output(\$reference . '.pdf', 'F')")));
    expect(endpoint, isNot(contains('file_put_contents')));
  });

  test('PDF engine checks only capabilities required by the local path', () {
    expect(
        endpoint.indexOf(r'$user = qbook_require_user();'),
        lessThan(endpoint
            .indexOf("require_once __DIR__ . '/vendor/tcpdf/tcpdf.php';")));
    expect(endpoint, contains("extension_loaded('zlib')"));
    expect(endpoint, contains("extension_loaded('gd')"));
    expect(endpoint, contains("extension_loaded('imagick')"));
    expect(endpoint, contains("'PDF_ENGINE_UNAVAILABLE'"));
    expect(endpoint, isNot(contains("extension_loaded('curl')")));
    expect(endpoint, isNot(contains("extension_loaded('mbstring')")));
    expect(tcpdfStatic, contains('getCurlDefaultOptions()'));
    expect(tcpdfStatic, isNot(contains('protected const CURLOPT_DEFAULT')));
  });
}
