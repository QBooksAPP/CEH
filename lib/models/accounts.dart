class FinancialAccount {
  const FinancialAccount({
    required this.id,
    required this.code,
    required this.name,
    required this.accountType,
    required this.isPostable,
    required this.isActive,
  });
  final int id;
  final String code;
  final String name;
  final String accountType;
  final bool isPostable;
  final bool isActive;

  factory FinancialAccount.fromJson(Map<String, dynamic> json) =>
      FinancialAccount(
        id: _int(json['id']),
        code: '${json['code'] ?? ''}',
        name: '${json['name'] ?? ''}',
        accountType: '${json['account_type'] ?? ''}',
        isPostable: _bool(json['is_postable']),
        isActive: _bool(json['is_active']),
      );
}

class CehBankAccount {
  const CehBankAccount({
    required this.id,
    required this.name,
    required this.currency,
    required this.currentBalance,
    required this.statementBalance,
    required this.unreconciledCount,
  });
  final int id;
  final String name;
  final String currency;
  final double currentBalance;
  final double? statementBalance;
  final int unreconciledCount;

  factory CehBankAccount.fromJson(Map<String, dynamic> json) => CehBankAccount(
        id: _int(json['id']),
        name: '${json['name'] ?? ''}',
        currency: '${json['currency'] ?? 'NGN'}',
        currentBalance: _double(json['current_balance']),
        statementBalance: json['statement_balance'] == null
            ? null
            : _double(json['statement_balance']),
        unreconciledCount: _int(json['unreconciled_count']),
      );
}

class CehBankTransaction {
  const CehBankTransaction({
    required this.id,
    required this.date,
    required this.amount,
    required this.reference,
    required this.narration,
    required this.status,
    this.potentialSourceType,
    this.potentialSourceId,
  });
  final int id;
  final String date;
  final double amount;
  final String reference;
  final String narration;
  final String status;
  final String? potentialSourceType;
  final int? potentialSourceId;

  factory CehBankTransaction.fromJson(Map<String, dynamic> json) =>
      CehBankTransaction(
        id: _int(json['id']),
        date: '${json['transaction_date'] ?? ''}',
        amount: _double(json['amount']),
        reference: '${json['bank_reference'] ?? ''}',
        narration: '${json['narration'] ?? ''}',
        status: '${json['status'] ?? ''}',
        potentialSourceType: json['potential_source_type']?.toString(),
        potentialSourceId: json['potential_source_id'] == null
            ? null
            : _int(json['potential_source_id']),
      );
}

class PettyCashCustodianBalance {
  const PettyCashCustodianBalance({
    required this.userId,
    required this.name,
    required this.role,
    required this.fundsReceived,
    required this.accounted,
    required this.pending,
    required this.balance,
    required this.available,
    required this.thisMonthFundsReceived,
    required this.thisMonthAccounted,
  });
  final int userId;
  final String name;
  final String role;
  final double fundsReceived;
  final double accounted;
  final double pending;
  final double balance;
  final double available;
  final double thisMonthFundsReceived;
  final double thisMonthAccounted;

  factory PettyCashCustodianBalance.fromJson(Map<String, dynamic> json) {
    final balance = Map<String, dynamic>.from(json['balance'] as Map? ?? {});
    final thisMonth =
        Map<String, dynamic>.from(json['this_month'] as Map? ?? {});
    return PettyCashCustodianBalance(
      userId: _int(json['user_id']),
      name: '${json['name'] ?? ''}',
      role: '${json['role'] ?? ''}',
      fundsReceived: _double(balance['funds_received']),
      accounted: _double(balance['accounted']),
      pending: _double(balance['pending']),
      balance: _double(balance['balance']),
      available: _double(balance['available']),
      thisMonthFundsReceived: _double(thisMonth['funds_received']),
      thisMonthAccounted: _double(thisMonth['accounted']),
    );
  }
}

class PettyCashOverview {
  const PettyCashOverview({
    required this.totalPettyCash,
    required this.custodians,
  });
  final double totalPettyCash;
  final List<PettyCashCustodianBalance> custodians;

  factory PettyCashOverview.fromJson(Map<String, dynamic> json) =>
      PettyCashOverview(
        totalPettyCash: _double(
            json['total_petty_cash_outstanding'] ?? json['total_petty_cash']),
        custodians: (json['custodians'] as List? ?? const [])
            .map((item) => PettyCashCustodianBalance.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
}

class CreatedPettyCashExpense {
  const CreatedPettyCashExpense({required this.id, required this.reference});
  final int id;
  final String reference;

  factory CreatedPettyCashExpense.fromJson(Map<String, dynamic> json) =>
      CreatedPettyCashExpense(
        id: _int(json['id']),
        reference: '${json['reference_no'] ?? ''}',
      );
}

class ExpenseSupplier {
  const ExpenseSupplier(
      {required this.id, required this.name, required this.isActive});
  final int id;
  final String name;
  final bool isActive;
  factory ExpenseSupplier.fromJson(Map<String, dynamic> json) =>
      ExpenseSupplier(
          id: _int(json['id']),
          name: '${json['canonical_name'] ?? ''}',
          isActive: _bool(json['is_active']));
}

class CostCentre {
  const CostCentre(
      {required this.id,
      required this.code,
      required this.name,
      required this.isActive});
  final int id;
  final String code;
  final String name;
  final bool isActive;
  factory CostCentre.fromJson(Map<String, dynamic> json) => CostCentre(
      id: _int(json['id']),
      code: '${json['code'] ?? ''}',
      name: '${json['name'] ?? ''}',
      isActive: _bool(json['is_active']));
}

class BillingInvoice {
  const BillingInvoice(
      {required this.id,
      required this.reference,
      required this.client,
      required this.status,
      required this.total,
      required this.outstanding,
      this.invoiceDate,
      this.dueDate});
  final int id;
  final String reference;
  final String client;
  final String status;
  final double total;
  final double outstanding;
  final String? invoiceDate;
  final String? dueDate;
  factory BillingInvoice.fromJson(Map<String, dynamic> json) => BillingInvoice(
      id: _int(json['id']),
      reference: '${json['reference'] ?? ''}',
      client: '${json['client_name_snapshot'] ?? ''}',
      status: '${json['display_status'] ?? json['status'] ?? ''}',
      total: _double(json['total_amount']),
      outstanding: _double(json['outstanding']),
      invoiceDate: json['invoice_date']?.toString(),
      dueDate: json['due_date']?.toString());
}

class BillableProductionReport {
  const BillableProductionReport(
      {required this.sessionId,
      required this.reference,
      required this.projectId,
      required this.project,
      required this.mixer,
      required this.signedM3,
      required this.billedM3,
      required this.availableM3});
  final int sessionId;
  final String reference;
  final int? projectId;
  final String project;
  final String mixer;
  final double signedM3;
  final double billedM3;
  final double availableM3;
  factory BillableProductionReport.fromJson(Map<String, dynamic> json) =>
      BillableProductionReport(
          sessionId: _int(json['production_session_id']),
          reference: '${json['reference'] ?? ''}',
          projectId:
              json['project_id'] == null ? null : _int(json['project_id']),
          project: '${json['project_site'] ?? ''}',
          mixer: '${json['mixer'] ?? ''}',
          signedM3: _double(json['signed_m3']),
          billedM3: _double(json['billed_m3']),
          availableM3: _double(json['available_m3']));
}

class ExpenseLine {
  const ExpenseLine(
      {required this.id,
      required this.lineNo,
      required this.description,
      required this.amount,
      required this.category,
      required this.expenseAccountId,
      this.costCentre,
      this.costCentreId,
      this.client,
      this.clientId,
      this.project,
      this.projectId,
      this.equipment,
      this.equipmentId});
  final int? id;
  final int lineNo;
  final String description;
  final double amount;
  final String category;
  final int expenseAccountId;
  final String? costCentre;
  final int? costCentreId;
  final String? client;
  final int? clientId;
  final String? project;
  final int? projectId;
  final String? equipment;
  final int? equipmentId;
  factory ExpenseLine.fromJson(Map<String, dynamic> json) => ExpenseLine(
      id: json['id'] == null ? null : _int(json['id']),
      lineNo: _int(json['line_no']),
      description: '${json['item_description'] ?? ''}',
      amount: _double(json['amount']),
      category: '${json['category'] ?? ''}',
      expenseAccountId: _int(json['expense_account_id']),
      costCentre: json['cost_centre_name']?.toString(),
      costCentreId:
          json['cost_centre_id'] == null ? null : _int(json['cost_centre_id']),
      client: json['client_name']?.toString(),
      clientId: json['client_id'] == null ? null : _int(json['client_id']),
      project: json['project_name']?.toString(),
      projectId: json['project_id'] == null ? null : _int(json['project_id']),
      equipment: json['mixer_code']?.toString(),
      equipmentId: json['mixer_id'] == null ? null : _int(json['mixer_id']));
}

class ConsolidatedExpense {
  const ConsolidatedExpense({
    required this.sourceRecordId,
    required this.reference,
    required this.date,
    required this.amount,
    required this.category,
    required this.expenseAccountId,
    required this.supplier,
    required this.description,
    required this.client,
    required this.project,
    required this.equipment,
    required this.sourceType,
    required this.sourceName,
    required this.status,
    required this.hasEvidence,
    required this.lifecycleStatus,
    required this.originalJournalId,
    required this.originalJournalReference,
    required this.reversalJournalId,
    required this.reversalJournalReference,
    required this.voidReason,
    required this.voidedBy,
    required this.voidedAt,
    this.reclassificationJournalReference,
    this.reclassificationReason,
    this.reclassifiedBy,
    this.reclassifiedAt,
    this.lines = const [],
  });

  final int sourceRecordId;
  final String reference;
  final String date;
  final double amount;
  final String category;
  final int expenseAccountId;
  final String supplier;
  final String description;
  final String? client;
  final String? project;
  final String? equipment;
  final String sourceType;
  final String sourceName;
  final String status;
  final bool hasEvidence;
  final String lifecycleStatus;
  final int? originalJournalId;
  final String? originalJournalReference;
  final int? reversalJournalId;
  final String? reversalJournalReference;
  final String? voidReason;
  final String? voidedBy;
  final String? voidedAt;
  final String? reclassificationJournalReference;
  final String? reclassificationReason;
  final String? reclassifiedBy;
  final String? reclassifiedAt;
  final List<ExpenseLine> lines;

  factory ConsolidatedExpense.fromJson(Map<String, dynamic> json) =>
      ConsolidatedExpense(
        sourceRecordId: _int(json['source_record_id'] ?? json['id']),
        reference: '${json['reference_no'] ?? 'Reference pending'}',
        date: '${json['expense_date'] ?? ''}',
        amount: _double(json['amount']),
        category: '${json['category'] ?? ''}',
        expenseAccountId: _int(json['expense_account_id']),
        supplier: '${json['supplier_paid_to'] ?? ''}',
        description: '${json['description'] ?? ''}',
        client: json['client_name']?.toString(),
        project: json['project_name']?.toString(),
        equipment: json['mixer_code']?.toString(),
        sourceType: '${json['source_type'] ?? ''}',
        sourceName: '${json['source_name'] ?? ''}',
        status: '${json['posting_status'] ?? ''}',
        hasEvidence: _int(json['evidence_count']) > 0,
        lifecycleStatus: '${json['lifecycle_status'] ?? ''}',
        originalJournalId:
            json['journal_id'] == null ? null : _int(json['journal_id']),
        originalJournalReference:
            json['original_journal_reference']?.toString(),
        reversalJournalId: json['reversal_journal_id'] == null
            ? null
            : _int(json['reversal_journal_id']),
        reversalJournalReference:
            json['reversal_journal_reference']?.toString(),
        voidReason: json['void_reason']?.toString(),
        voidedBy: json['voided_by_name']?.toString(),
        voidedAt: json['voided_at']?.toString(),
        reclassificationJournalReference:
            json['reclassification_journal_reference']?.toString(),
        reclassificationReason: json['reclassification_reason']?.toString(),
        reclassifiedBy: json['reclassified_by_name']?.toString(),
        reclassifiedAt: json['reclassified_at']?.toString(),
        lines: (json['lines'] as List? ?? const [])
            .map((line) =>
                ExpenseLine.fromJson(Map<String, dynamic>.from(line as Map)))
            .toList(),
      );
}

int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;
double _double(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('${value ?? ''}') ?? 0;
bool _bool(dynamic value) =>
    value == true || value == 1 || value?.toString() == '1';
