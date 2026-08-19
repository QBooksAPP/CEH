import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  final common = source('Server/production_report_common.php');
  final endpoint = source('Server/production_report_pdf.php');
  final sign = source('Server/production_session_sign.php');
  final migration = source('Server/migration_v1_6_production_reports.sql');
  final tcpdfStatic = source('Server/vendor/tcpdf/include/tcpdf_static.php');
  final webConfig = source('Server/web.config');
  final runtimeHtaccess = source('Server/runtime/.htaccess');

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
    expect(endpoint, contains("'PDF_SIGNATURE_MISSING'"));
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
    expect(
      endpoint,
      contains("production_report_blob_bytes(\$signoff['signature_data'])"),
    );
    expect(endpoint, contains('production_report_normalize_png'));
    expect(endpoint, contains('embedRequiredPng(\$signaturePng'));
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
    expect(endpoint, contains("'PDF_ENGINE_UNAVAILABLE'"));
    expect(endpoint, isNot(contains("extension_loaded('curl')")));
    expect(endpoint, isNot(contains("extension_loaded('mbstring')")));
    expect(tcpdfStatic, contains('getCurlDefaultOptions()'));
    expect(tcpdfStatic, isNot(contains('protected const CURLOPT_DEFAULT')));
  });

  test('required evidentiary images are validated and embedded or fail', () {
    expect(common, contains('production_report_cache_directory('));
    expect(common, contains('production_report_normalize_png'));
    expect(endpoint,
        contains("hash_equals((string)\$signoff['signature_sha256']"));
    expect(endpoint, contains('embedRequiredPng(\$logoPng'));
    expect(endpoint, contains('embedRequiredPng(\$signaturePng'));
    expect(endpoint, contains("'PDF_IMAGE_EMBED_FAILED'"));
    expect(endpoint, contains("'PDF_REQUIRED_IMAGES_MISSING'"));
  });

  test('temporary diagnostics expose fixed safe codes to Admin only', () {
    expect(common, contains('production_report_safe_diagnostic'));
    expect(common, contains("'diagnostic_code'"));
    expect(common, contains("(\$user['role'] ?? '') === 'ADMIN'"));
    expect(common, contains("'error' => 'PRODUCTION_REPORT_FAILED'"));
    expect(common, contains("\$response['error'] = \$code"));
    expect(common, isNot(contains("'message' => \$exception")));
    expect(common, isNot(contains("'detail' => \$exception")));
    for (final code in [
      'PDF_CACHE_UNAVAILABLE',
      'PDF_LOGO_UNREADABLE',
      'PDF_LOGO_INVALID',
      'PDF_SIGNATURE_MISSING',
      'PDF_SIGNATURE_HASH_MISMATCH',
      'PDF_SIGNATURE_INVALID',
      'PDF_IMAGE_EMBED_FAILED',
      'PDF_OUTPUT_IMAGES_MISSING',
    ]) {
      expect(common, contains(code));
    }
  });

  test('cache capability failure is inside the safe diagnostic boundary', () {
    expect(endpoint, contains('try {'));
    expect(endpoint, contains('production_report_cache_directory()'));
    expect(endpoint, contains('production_report_fail(\$user, \$exception)'));
  });

  test('IONOS cache fallback is private, writable-tested and HTTP blocked', () {
    expect(common, contains("__DIR__ . '/runtime/pdf-cache'"));
    expect(common, contains("mkdir(\$runtimeCache, 0700, true)"));
    expect(common, contains('production_report_prove_writable_directory'));
    expect(common, contains('production_report_create_request_cache'));
    expect(common, contains("tempnam(\$resolved, 'ceh_pdf_probe_')"));
    expect(webConfig, contains('<add segment="runtime" />'));
    expect(webConfig, contains('<directoryBrowse enabled="false" />'));
    expect(runtimeHtaccess, contains('Require all denied'));
    expect(runtimeHtaccess, contains('Options -Indexes'));
  });

  test('TCPDF temporary files are cleaned up on success and failure', () {
    expect(endpoint, contains('unset(\$pdf);'));
    expect(endpoint, contains('TCPDF destructor removes its temp files'));
    expect(common, contains('production_report_cleanup_cache_directory'));
    expect(common, contains("basename(\$resolved), 'ceh_pdf_'"));
    expect(
        endpoint,
        contains(
            'production_report_cleanup_cache_directory(\$cacheDirectory)'));
  });

  test('client report disables TCPDF attribution footer and link', () {
    expect(endpoint, contains('disableTcpdfAttribution()'));
    expect(endpoint, contains('\$this->tcpdflink = false;'));
  });

  test('report uses the supplied logo prominently without duplicate branding',
      () {
    expect(endpoint, contains('embedRequiredPng(\$logoPng, 15, 12, 78)'));
    expect(endpoint, contains("'DAILY PRODUCTION REPORT'"));
    expect(
      endpoint,
      isNot(contains("Cell(137, 7, 'Concrete Equipment Hire Limited'")),
    );
  });

  test('report palette is sampled from the monochrome CEH logo', () {
    expect(endpoint, contains('\$black = [0, 0, 0]'));
    expect(endpoint, contains('\$darkGray = [89, 89, 89]'));
    expect(endpoint, contains('\$midGray = [165, 165, 165]'));
    expect(endpoint, isNot(contains('\$navy =')));
    expect(endpoint, isNot(contains('\$blue =')));
  });

  test('signature display preserves its source aspect ratio', () {
    expect(endpoint, contains('getimagesizefromstring(\$signaturePng)'));
    expect(endpoint, contains('\$signatureWidth'));
    expect(endpoint, contains('\$signatureHeight'));
    expect(endpoint,
        contains("throw new RuntimeException('PDF_SIGNATURE_INVALID')"));
  });
}
