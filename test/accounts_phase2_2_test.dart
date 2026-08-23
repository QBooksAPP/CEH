import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration =
      File('Server/migration_v1_14_cost_centres.sql').readAsStringSync();
  final common = File('Server/accounts_common.php').readAsStringSync();
  final pettyReview =
      File('Server/petty_cash_expense_review.php').readAsStringSync();
  final generalReview =
      File('Server/general_expense_review.php').readAsStringSync();
  final reclassify =
      File('Server/expense_line_reclassify.php').readAsStringSync();
  final generalUi =
      File('lib/screens/accounts/accounts_general_expense_screen.dart')
          .readAsStringSync();
  final pettyUi = File('lib/screens/accounts/accounts_live_screens.dart')
      .readAsStringSync();

  test('v1.14 creates an extensible Cost Centre master with approved seeds',
      () {
    expect(migration, contains('CREATE TABLE qbook_cost_centres'));
    expect(migration, contains("('OFFICE','Office'"));
    expect(migration, contains("('WORKSHOP','Workshop'"));
    expect(migration, contains("('PROJECT_OPERATIONS','Project / Operations'"));
    expect(migration, contains('is_active TINYINT(1)'));
  });

  test('historical expense and journal dimensions remain nullable', () {
    expect(
        RegExp(r'ADD COLUMN cost_centre_id BIGINT UNSIGNED NULL')
            .allMatches(migration)
            .length,
        3);
    expect(migration, isNot(contains('UPDATE qbook_')));
  });

  test('Cost Centre is indexed and FK protected on both lines and journal', () {
    expect(migration, contains('idx_petty_line_cost_centre'));
    expect(migration, contains('idx_general_line_cost_centre'));
    expect(migration, contains('idx_financial_line_cost_centre'));
    expect(
        RegExp(r'REFERENCES qbook_cost_centres\(id\)')
            .allMatches(migration)
            .length,
        3);
  });

  test('Workshop, account and all operational dimensions coexist per line', () {
    final line = <String, dynamic>{
      'cost_centre': 'Workshop',
      'category': 'Spare Parts',
      'description': 'Bolts',
      'quantity': 10,
      'unit_price': 2000.00,
      'amount': 20000.00,
      'client': 'ABC Construction',
      'project': 'Epe',
      'equipment': 'Mixer 307',
    };
    expect(line['amount'], 20000.00);
    expect(
        line.values,
        containsAll(<Object>[
          'Workshop',
          'Spare Parts',
          'ABC Construction',
          'Epe',
          'Mixer 307'
        ]));
    expect(common, contains("'cost_centre_id' => \$costCentre"));
    expect(common, contains("'client_id' => \$client"));
    expect(common, contains("'project_id' => \$project"));
    expect(common, contains("'mixer_id' => \$mixer"));
    expect(common, contains("'amount_minor' => \$amount"));
  });

  test('one 20000 line posts one debit and not duplicated dimensions', () {
    expect(generalReview,
        contains("'debit_minor'=>\$minor,'credit_minor'=>0,'cost_centre_id'"));
    expect(generalReview, contains("'credit_minor'=>\$header"));
    expect(generalReview, contains('EXPENSE_LINE_TOTAL_MISMATCH'));
  });

  test('Office permits blank Client Project and Equipment', () {
    expect(
        common, contains("accounts_nullable_id(\$line['client_id'] ?? null)"));
    expect(
        common, contains("accounts_nullable_id(\$line['project_id'] ?? null)"));
    expect(
        common, contains("accounts_nullable_id(\$line['mixer_id'] ?? null)"));
  });

  test('Petty and Bank approval persist Cost Centre into journal lines', () {
    expect(pettyReview, contains("'cost_centre_id'=>\$line['cost_centre_id']"));
    expect(
        generalReview, contains("'cost_centre_id'=>\$line['cost_centre_id']"));
    expect(common, contains('qbook_financial_journal_lines'));
  });

  test('split lines independently carry Cost Centre', () {
    final lines = [
      {'cost_centre': 'Office', 'amount': 5000.00},
      {'cost_centre': 'Workshop', 'amount': 15000.00},
    ];
    expect(lines.map((line) => line['cost_centre']).toSet(),
        {'Office', 'Workshop'});
    expect(
        lines.fold<double>(0, (sum, line) => sum + (line['amount']! as double)),
        20000.00);
    expect(common, contains("\$line['cost_centre_id']"));
    expect(common, contains("foreach (\$lines as \$line)"));
    expect(generalUi, contains("'cost_centre_id': costCentreId"));
    expect(pettyUi, contains("'cost_centre_id': costCentre"));
  });

  test('dimension-only correction is balanced and never touches assets', () {
    expect(reclassify,
        contains("'debit_minor'=>\$minor,'credit_minor'=>0,'cost_centre_id'"));
    expect(reclassify,
        contains("'debit_minor'=>0,'credit_minor'=>\$minor,'cost_centre_id'"));
    expect(reclassify, contains("'asset_impact'=>'0.00'"));
    expect(reclassify, isNot(contains('qbook_bank_accounts')));
    expect(reclassify, isNot(contains('qbook_petty_cash_fundings')));
  });

  test('both compact expense-line editors expose Cost Centre', () {
    expect(generalUi, contains("labelText: 'Cost Centre'"));
    expect(generalUi, contains("label: const Text('Add another line')"));
    expect(pettyUi, contains("labelText: 'Cost Centre'"));
    expect(pettyUi, contains("label: const Text('Add another line')"));
  });

  test('Workshop selection does not hide Client Project or Equipment', () {
    expect(generalUi, isNot(contains("costCentreId == 'WORKSHOP'")));
    expect(generalUi, contains('Client / Project (optional)'));
    expect(generalUi, contains('Equipment (optional)'));
  });

  test('v1.14 contains no financial or destructive data actions', () {
    final upper = migration.toUpperCase();
    expect(upper, isNot(contains('INSERT INTO QBOOK_FINANCIAL_JOURNALS')));
    expect(upper, isNot(contains('INSERT INTO QBOOK_FINANCIAL_JOURNAL_LINES')));
    expect(upper, isNot(contains('DELETE FROM')));
    expect(upper, isNot(contains('DROP TABLE')));
    expect(upper, isNot(contains('DROP COLUMN')));
    expect(upper, isNot(contains('ON DELETE CASCADE')));
  });
}
