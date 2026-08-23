import 'dart:io';

import 'package:ceh/core/accounts_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  final bankForm =
      source('lib/screens/accounts/accounts_general_expense_screen.dart');
  final pettyForm = source('lib/screens/accounts/accounts_live_screens.dart');
  final common = source('Server/accounts_common.php');
  final supplierCreate = source('Server/supplier_create.php');
  final generalCreate = source('Server/general_expense_create.php');
  final generalSubmit = source('Server/general_expense_submit.php');

  test('simple one-line bank expense is the default presentation', () {
    expect(bankForm, contains(r"Text('Line ${widget.index + 1}'"));
    expect(bankForm, contains("labelText: 'Account / Category'"));
    expect(bankForm, contains("labelText: 'Description'"));
    expect(bankForm, isNot(contains('Split allocation')));
  });

  test('additional lines use the same compact line editor', () {
    expect(bankForm, contains("label: const Text('Add another line')"));
    expect(bankForm, contains('_CompactExpenseLine('));
    expect(bankForm, contains('_lines.add(_ExpenseLineDraft())'));
  });

  test('quantity times price calculates a currency-rounded total', () {
    expect(calculateExpenseLineTotal('3', '12,500.50'), 37501.50);
    expect(calculateExpenseLineTotal('0', '100'), isNull);
  });

  test('direct total remains valid when quantity and price are blank', () {
    expect(parseNgnInput('250,000.00'), 250000);
    expect(calculateExpenseLineTotal('', ''), isNull);
    expect(bankForm, contains('enabled: !calculated'));
  });

  test('header total is always the sum of line totals', () {
    expect(sumExpenseLineTotals([100000, 30000.25, null]), 130000.25);
    expect(bankForm, contains("'amount': total > 0 ? total : null"));
    expect(bankForm, isNot(contains("labelText: 'Header total (₦)'")));
  });

  test('supplier is created inline and automatically selected', () {
    expect(bankForm, contains("title: const Text('New Supplier')"));
    expect(bankForm, contains("'canonical_name': name.text.trim()"));
    expect(bankForm, contains('_supplier = result.id'));
    expect(bankForm, contains('Add optional details'));
    expect(supplierCreate, contains('SUPPLIER_NAME_OR_ALIAS_CONFLICT'));
  });

  test('supplier normalization tolerates hosts without mbstring', () {
    expect(common, contains("function_exists('mb_strtolower')"));
    expect(common, contains("'SERVER_ERROR'"));
    expect(common, contains('error_log('));
  });

  test('bank charge requires no supplier reference receipt or dimensions', () {
    expect(bankForm, contains('Bank Charge quick entry'));
    expect(generalCreate, contains("'is_bank_charge'"));
    expect(generalCreate, contains('BANK_CHARGE_PAYEE_NOT_ALLOWED'));
    expect(generalSubmit, contains(r'$bankCharge'));
    expect(generalSubmit, contains(r'if(!$bankCharge)'));
    expect(generalCreate, isNot(contains('FAKE_BANK_REFERENCE')));
  });

  test('petty cash uses calculated header and add-another-line language', () {
    expect(pettyForm, contains("labelText: 'Header Total (calculated)'"));
    expect(pettyForm, contains("label: const Text('Add another line')"));
    expect(pettyForm, contains('calculateExpenseLineTotal('));
    expect(pettyForm, contains('sumExpenseLineTotals('));
  });

  test('accounting endpoints and migrations remain untouched by UX tests', () {
    expect(generalSubmit, contains('EXPENSE_LINE_TOTAL_MISMATCH'));
    expect(generalSubmit, contains("status='SUBMITTED'"));
  });
}
