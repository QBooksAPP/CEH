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
  });
  final int userId;
  final String name;
  final String role;
  final double fundsReceived;
  final double accounted;
  final double pending;
  final double balance;
  final double available;

  factory PettyCashCustodianBalance.fromJson(Map<String, dynamic> json) {
    final balance = Map<String, dynamic>.from(json['balance'] as Map? ?? {});
    return PettyCashCustodianBalance(
      userId: _int(json['user_id']),
      name: '${json['name'] ?? ''}',
      role: '${json['role'] ?? ''}',
      fundsReceived: _double(balance['funds_received']),
      accounted: _double(balance['accounted']),
      pending: _double(balance['pending']),
      balance: _double(balance['balance']),
      available: _double(balance['available']),
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
        totalPettyCash: _double(json['total_petty_cash']),
        custodians: (json['custodians'] as List? ?? const [])
            .map((item) => PettyCashCustodianBalance.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
}

int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;
double _double(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('${value ?? ''}') ?? 0;
bool _bool(dynamic value) =>
    value == true || value == 1 || value?.toString() == '1';
