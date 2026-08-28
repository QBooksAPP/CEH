import 'dart:io';

import 'package:ceh/core/accounts_formatters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;

String source(String path) => File(path).readAsStringSync();

void main() {
  setUpAll(tz.initializeTimeZones);

  test('CEH date and date-time presentation is consistent', () {
    expect(displayCehDate('2026-08-28'), '28-08-2026');
    expect(displayCehDateTime('2026-08-28 14:30:59'), '28-08-2026 14:30');
    expect(displayCehDateTime('2026-08-28T14:30:59Z'), '28-08-2026 15:30');
    expect(displayAccountsDate('2026-08-28'), '28-08-2026');
    expect(canonicalAccountsDate(DateTime(2026, 8, 28)), '2026-08-28');
  });

  test('invalid and technical values are not silently rewritten', () {
    expect(displayCehDate('CEH-INV-2026-08-28'), 'CEH-INV-2026-08-28');
    expect(displayCehDateTime('Not recorded'), 'Not recorded');
    expect(parseCanonicalCehDate('28-08-2026'), isNull);
    expect(parseCanonicalCehDate('2026-02-30'), isNull);
  });

  test('representative UI surfaces use CEH formatters', () {
    for (final path in [
      'lib/screens/accounts/accounts_reports_screen.dart',
      'lib/screens/accounts/accounts_phase1_screens.dart',
      'lib/screens/accounts/accounts_detail_screens.dart',
      'lib/screens/calibration_data_screen.dart',
      'lib/screens/calibration_history_screen.dart',
      'lib/screens/calibration_records_screen.dart',
      'lib/screens/calibration_review_screen.dart',
      'lib/screens/production_log_screen.dart',
      'lib/screens/concrete_operations_screen.dart',
      'lib/screens/settings_history_screen.dart',
    ]) {
      final contents = source(path);
      expect(contents,
          anyOf(contains('displayAccountsDate'), contains('displayCehDate')),
          reason: path);
    }
  });

  test('report filters retain canonical API serialization', () {
    final screen = source('lib/screens/accounts/accounts_reports_screen.dart');
    expect(screen, contains("add('date_from', _fromDate)"));
    expect(screen, contains("add('date_to', _toDate)"));
    expect(screen, contains("add('as_of', _toDate)"));
    expect(screen, contains('canonicalAccountsDate(picked)'));
    expect(screen, isNot(contains('hintText: \'YYYY-MM-DD\'')));
  });

  test('editable date surfaces use calendar selection', () {
    final reports = source('lib/screens/accounts/accounts_reports_screen.dart');
    final accounts = source('lib/core/accounts_formatters.dart');
    final calibration =
        source('lib/screens/calibration_field_sheet_screen.dart');
    final estimates =
        source('lib/screens/accounts/accounts_estimates_screen.dart');
    for (final contents in [reports, accounts, calibration, estimates]) {
      expect(contents, contains('showDatePicker'));
    }
  });
}
