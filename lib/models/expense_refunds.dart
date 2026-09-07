class ExpenseRefundEntry {
  ExpenseRefundEntry.fromJson(Map<String, dynamic> j)
      : statementRowId = int.parse('${j['statement_row_id']}'),
        amount = double.parse('${j['amount']}'),
        date = '${j['transaction_date']}',
        reference = '${j['bank_reference'] ?? 'Reference not recorded'}',
        narration = '${j['narration'] ?? ''}',
        statementStatus = '${j['statement_status'] ?? ''}',
        linkedAt = j['linked_at']?.toString(),
        linkedBy = j['linked_by_name']?.toString();
  final int statementRowId;
  final double amount;
  final String date, reference, narration, statementStatus;
  final String? linkedAt, linkedBy;
}

class ExpenseRefundPage {
  ExpenseRefundPage.fromJson(Map<String, dynamic> j)
      : reference = '${j['expense']['reference_no'] ?? 'Reference pending'}',
        bank = '${j['expense']['bank_name'] ?? 'Bank not recorded'}',
        original = double.parse('${j['expense']['amount']}'),
        linked = double.parse('${j['expense']['linked_amount']}'),
        remaining = double.parse('${j['expense']['remaining_amount']}'),
        status = '${j['expense']['refund_status']}',
        canLink = j['expense']['can_link'] == true,
        page = int.parse('${j['page']}'),
        totalPages = int.parse('${j['total_pages']}'),
        total = int.parse('${j['total']}'),
        rows = (j['rows'] as List)
            .map((r) => ExpenseRefundEntry.fromJson(
                Map<String, dynamic>.from(r as Map)))
            .toList();
  final String reference, bank, status;
  final double original, linked, remaining;
  final bool canLink;
  final int page, totalPages, total;
  final List<ExpenseRefundEntry> rows;
  String get statusLabel => switch (status) {
        'FULL' => 'Fully Refunded',
        'PARTIAL' => 'Partially Refunded',
        _ => 'None',
      };
}
