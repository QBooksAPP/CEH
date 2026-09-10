int bankInt(Object? value) => int.tryParse('$value') ?? 0;
String bankText(Object? value) => value?.toString() ?? '';
String bankAccountLabel(Map<String, dynamic> bank) {
  final masked = bankText(bank['masked_account_reference']).trim();
  final suffix = RegExp(r'^•••• [0-9]{4}$').hasMatch(masked)
      ? masked
      : bankText(bank['currency']);
  return '${bank['name']} • $suffix';
}
Map<String, dynamic> bankMap(Object? value) =>
    Map<String, dynamic>.from(value as Map? ?? {});
const bankUsageLabels = <String, String>{
  'ALL': 'All usage',
  'AVAILABLE': 'Available',
  'RESERVED_EXPENSE': 'Reserved for Expense',
  'EXPENSE': 'Linked to Expense',
  'REFUND': 'Linked as Refund',
  'PAYMENT': 'Linked to Client Payment',
  'RECONCILED': 'Reconciled',
};

class BankingPage {
  BankingPage.fromJson(Map<String, dynamic> json, {bool imports = false})
      : rows = (json[imports ? 'imports' : 'transactions'] as List? ?? [])
            .map(bankMap)
            .toList(growable: false),
        summary = bankMap(json['summary']),
        total = bankInt(json['total']),
        page = bankInt(json['page']),
        hasMore = json['has_more'] == true;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> summary;
  final int total, page;
  final bool hasMore;
}
