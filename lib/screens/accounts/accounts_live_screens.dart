import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/accounts_formatters.dart';
import '../../core/api_client.dart';
import '../../core/internal_navigation.dart';
import '../../core/view_mode.dart';
import '../../models/accounts.dart';
import '../../models/client.dart';
import '../../models/project.dart';
import '../../models/session.dart';
import '../../widgets/accounts_widgets.dart';

class _AccountsLivePage extends StatelessWidget {
  const _AccountsLivePage({
    required this.session,
    required this.title,
    required this.children,
  });
  final CehSession session;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!isUiAdmin(context, session)) {
      return const Scaffold(
          body: Center(child: Text('Administrator access required.')));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: cehHomeAction(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: children,
      ),
    );
  }
}

class _AccountsLoadError extends StatelessWidget {
  const _AccountsLoadError(this.error, this.retry);
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(children: [
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 8),
            const Text('Accounts data is not available yet.',
                style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text(error is ApiException
                ? (error as ApiException).code
                : 'ACCOUNTS_LOAD_FAILED'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry')),
          ]),
        ),
      );
}

class AccountsBankingScreen extends StatefulWidget {
  const AccountsBankingScreen({super.key, required this.session});
  final CehSession session;
  @override
  State<AccountsBankingScreen> createState() => _AccountsBankingScreenState();
}

class _AccountsBankingScreenState extends State<AccountsBankingScreen> {
  final _api = const CehApiClient();
  late Future<(List<CehBankAccount>, List<CehBankTransaction>)> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _api.bankAccounts(widget.session).then((banks) async => (
          banks,
          banks.isEmpty
              ? <CehBankTransaction>[]
              : await _api.bankTransactions(widget.session, banks.first.id)
        ));
  }

  void _retry() => setState(_load);

  Future<void> _confirmMatch(CehBankTransaction row) async {
    if (row.potentialSourceType == null || row.potentialSourceId == null) {
      return;
    }
    try {
      await _api.reconcileBankRow(widget.session,
          statementRowId: row.id,
          sourceType: row.potentialSourceType!,
          sourceRecordId: row.potentialSourceId!);
      _retry();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => _AccountsLivePage(
        session: widget.session,
        title: 'Banking',
        children: [
          const AccountsSectionTitle('Bank accounts',
              subtitle: 'Authoritative CEH ledger and reconciliation data'),
          FutureBuilder<(List<CehBankAccount>, List<CehBankTransaction>)>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _AccountsLoadError(snapshot.error!, _retry);
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final banks = snapshot.data!.$1;
              final rows = snapshot.data!.$2;
              if (banks.isEmpty) return const Text('No active bank account.');
              final bank = banks.first;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(bank.name,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 12),
                          AccountsMetricLine('Current CEH balance',
                              formatNaira(bank.currentBalance)),
                          AccountsMetricLine(
                              'Statement balance',
                              bank.statementBalance == null
                                  ? 'No statement imported'
                                  : formatNaira(bank.statementBalance!)),
                          AccountsMetricLine('Unreconciled transactions',
                              '${bank.unreconciledCount}'),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: null,
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text(
                                'CSV / XLSX Import — desktop picker pending'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const AccountsSectionTitle('Reconciliation workspace'),
                  for (final row in rows)
                    Card(
                      child: ExpansionTile(
                        title: Text(row.narration,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(
                            '${displayAccountsDate(row.date)} • Ref ${row.reference}\n${row.status}'),
                        trailing: Text(
                          '${row.amount < 0 ? '−' : '+'}${formatNaira(row.amount.abs())}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        children: [
                          if (row.status == 'POTENTIAL_MATCH')
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: () => _confirmMatch(row),
                                icon: const Icon(Icons.compare_arrows),
                                label: const Text('Confirm Match'),
                              ),
                            ),
                          if (row.status == 'POSSIBLE_DUPLICATE')
                            const Text(
                                'Review this row before creating or matching any CEH transaction.'),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      );
}

class AccountsExpensesScreen extends StatefulWidget {
  const AccountsExpensesScreen({super.key, required this.session});
  final CehSession session;

  @override
  State<AccountsExpensesScreen> createState() => _AccountsExpensesScreenState();
}

class _AccountsExpensesScreenState extends State<AccountsExpensesScreen> {
  final _api = const CehApiClient();
  late Future<List<ConsolidatedExpense>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = _api.consolidatedExpenses(widget.session);
  void _retry() => setState(_load);

  @override
  Widget build(BuildContext context) => _AccountsLivePage(
        session: widget.session,
        title: 'Expenses',
        children: [
          const AccountsSectionTitle('Expense register',
              subtitle: 'Approved accounting expenses — reporting view only'),
          FutureBuilder<List<ConsolidatedExpense>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _AccountsLoadError(snapshot.error!, _retry);
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.isEmpty) {
                return const Text('No approved expenses recorded.');
              }
              return Column(
                children: [
                  for (final expense in snapshot.data!)
                    Card(
                      child: ExpansionTile(
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        title: Row(children: [
                          Expanded(
                            child: Text(expense.reference,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                          ),
                          Text(formatNaira(expense.amount),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900)),
                        ]),
                        subtitle: Text(
                            '${expense.category} • ${displayAccountsDate(expense.date)}'),
                        children: [
                          AccountsMetricLine(
                              'Supplier / Paid To', expense.supplier),
                          AccountsMetricLine(
                              'Description', expense.description),
                          AccountsMetricLine(
                              'Client', expense.client ?? 'Not allocated'),
                          AccountsMetricLine(
                              'Project', expense.project ?? 'Not allocated'),
                          AccountsMetricLine('Equipment',
                              expense.equipment ?? 'Not allocated'),
                          AccountsMetricLine('Source',
                              '${expense.sourceType} — ${expense.sourceName}'),
                          AccountsMetricLine('Receipt',
                              expense.hasEvidence ? 'Attached' : 'No receipt'),
                          Align(
                            alignment: Alignment.centerRight,
                            child: AccountsStatusChip(expense.status),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      );
}

class AccountsPettyCashScreen extends StatefulWidget {
  const AccountsPettyCashScreen({super.key, required this.session});
  final CehSession session;
  @override
  State<AccountsPettyCashScreen> createState() =>
      _AccountsPettyCashScreenState();
}

class _AccountsPettyCashScreenState extends State<AccountsPettyCashScreen> {
  final _api = const CehApiClient();
  late Future<(PettyCashOverview, List<Map<String, dynamic>>)> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = Future.wait<Object>([
      _api.pettyCashOverview(widget.session),
      _api.pettyCashExpenses(widget.session),
    ]).then((values) => (
          values[0] as PettyCashOverview,
          values[1] as List<Map<String, dynamic>>
        ));
  }

  void _reload() => setState(_load);

  Future<void> _review(int id, String action) async {
    try {
      await _api.reviewPettyCashExpense(widget.session,
          expenseId: id,
          action: action,
          reason: action == 'APPROVE'
              ? ''
              : action == 'CORRECTION_REQUIRED'
                  ? 'Correction required by Admin'
                  : 'Admin confirmed money was not spent');
      _reload();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => _AccountsLivePage(
        session: widget.session,
        title: 'Petty Cash',
        children: [
          FutureBuilder<(PettyCashOverview, List<Map<String, dynamic>>)>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _AccountsLoadError(snapshot.error!, _reload);
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final overview = snapshot.data!.$1;
              final expenses = snapshot.data!.$2;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 190,
                    child: AccountsSummaryCard(
                      label: 'TOTAL PETTY CASH',
                      value: overview.totalPettyCash,
                      detail:
                          'Across ${overview.custodians.length} active custodians',
                      emphasized: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(spacing: 10, runSpacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    AccountsCustodianManagementScreen(
                                        session: widget.session)));
                        _reload();
                      },
                      icon: const Icon(Icons.manage_accounts_outlined),
                      label: const Text('Manage Custodians'),
                    ),
                    FilledButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => AccountsFundPettyCashScreen(
                                    session: widget.session)));
                        _reload();
                      },
                      icon: const Icon(Icons.account_balance_outlined),
                      label: const Text('Fund Petty Cash'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => AccountsPettyExpenseScreen(
                                    session: widget.session)));
                        _reload();
                      },
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Add Petty Cash Expense'),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  const AccountsSectionTitle('Custodian balances'),
                  for (final custodian in overview.custodians)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(custodian.name,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w900)),
                            Text(custodian.role),
                            const Divider(),
                            AccountsMetricLine('Funds Received',
                                formatNaira(custodian.fundsReceived)),
                            AccountsMetricLine('Accounted / Spent',
                                formatNaira(custodian.accounted)),
                            AccountsMetricLine('Pending Approval',
                                formatNaira(custodian.pending)),
                            AccountsMetricLine(
                                'Balance', formatNaira(custodian.balance),
                                prominent: true),
                            AccountsMetricLine('Available to spend',
                                formatNaira(custodian.available)),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const AccountsSectionTitle('Expense approval queue'),
                  if (expenses.isEmpty)
                    const Text('No petty cash expenses recorded.'),
                  for (final expense in expenses)
                    Card(
                      child: ExpansionTile(
                        title: Text(
                            '${expense['reference_no'] ?? 'Reference pending'} • ${formatNaira(double.tryParse('${expense['amount']}') ?? 0)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text(
                            '${expense['custodian_name']} • ${displayAccountsDate('${expense['expense_date']}')} • ${expense['status']}'),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        children: [
                          AccountsMetricLine(
                              'Paid To', '${expense['supplier_paid_to']}'),
                          AccountsMetricLine(
                              'Description', '${expense['description']}'),
                          AccountsMetricLine(
                              'Receipt',
                              (expense['evidence_count'] as num?)?.toInt() == 0
                                  ? 'No receipt'
                                  : 'Attached'),
                          AccountsMetricLine('Project',
                              '${expense['project_name'] ?? 'Not allocated'}'),
                          AccountsMetricLine('Equipment',
                              '${expense['mixer_code'] ?? 'Not allocated'}'),
                          if (expense['status'] == 'SUBMITTED')
                            Wrap(spacing: 8, children: [
                              FilledButton(
                                  onPressed: () => _review(
                                      (expense['id'] as num).toInt(),
                                      'APPROVE'),
                                  child: const Text('Approve')),
                              OutlinedButton(
                                  onPressed: () => _review(
                                      (expense['id'] as num).toInt(),
                                      'CORRECTION_REQUIRED'),
                                  child: const Text('Needs Correction')),
                              TextButton(
                                  onPressed: () => _review(
                                      (expense['id'] as num).toInt(),
                                      'CANCELLED_NOT_SPENT'),
                                  child: const Text('Not Spent / Cancel')),
                            ]),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      );
}

class AccountsCustodianManagementScreen extends StatefulWidget {
  const AccountsCustodianManagementScreen({
    super.key,
    required this.session,
  });
  final CehSession session;
  @override
  State<AccountsCustodianManagementScreen> createState() =>
      _AccountsCustodianManagementScreenState();
}

class _AccountsCustodianManagementScreenState
    extends State<AccountsCustodianManagementScreen> {
  final _api = const CehApiClient();
  late Future<(List<CehUser>, PettyCashOverview)> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = Future.wait<Object>([
      _api.users(widget.session),
      _api.pettyCashOverview(widget.session),
    ]).then((value) => (
          value[0] as List<CehUser>,
          value[1] as PettyCashOverview,
        ));
  }

  Future<void> _set(int userId, bool active) async {
    try {
      await _api.updatePettyCashCustodian(widget.session,
          userId: userId, isActive: active);
      setState(_load);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => _AccountsLivePage(
        session: widget.session,
        title: 'Petty Cash Custodians',
        children: [
          const AccountsSectionTitle('Designated custodians',
              subtitle: 'Admin controls who may hold and submit CEH cash'),
          FutureBuilder<(List<CehUser>, PettyCashOverview)>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _AccountsLoadError(
                    snapshot.error!, () => setState(_load));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final activeIds = snapshot.data!.$2.custodians
                  .map((item) => item.userId)
                  .toSet();
              final users =
                  snapshot.data!.$1.where((user) => user.isActive).toList();
              return Column(
                children: [
                  for (final user in users)
                    Card(
                      child: SwitchListTile(
                        title: Text(user.fullName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(user.username ?? user.email),
                        value: activeIds.contains(user.id),
                        onChanged: (value) => _set(user.id, value),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      );
}

class AccountsFundPettyCashScreen extends StatefulWidget {
  const AccountsFundPettyCashScreen({super.key, required this.session});
  final CehSession session;
  @override
  State<AccountsFundPettyCashScreen> createState() =>
      _AccountsFundPettyCashScreenState();
}

class _AccountsFundPettyCashScreenState
    extends State<AccountsFundPettyCashScreen> {
  final _api = const CehApiClient();
  final _picker = ImagePicker();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _description = TextEditingController();
  String _date = canonicalAccountsDate(DateTime.now());
  XFile? _proof;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AccountsLivePage(
        session: widget.session,
        title: 'Fund Petty Cash',
        children: [
          FutureBuilder<(List<CehBankAccount>, PettyCashOverview)>(
            future: Future.wait<Object>([
              _api.bankAccounts(widget.session),
              _api.pettyCashOverview(widget.session)
            ]).then((v) =>
                (v[0] as List<CehBankAccount>, v[1] as PettyCashOverview)),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _AccountsLoadError(
                    snapshot.error!, () => setState(() {}));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final banks = snapshot.data!.$1;
              final custodians = snapshot.data!.$2.custodians;
              if (banks.isEmpty || custodians.isEmpty) {
                return const Text('An active bank and custodian are required.');
              }
              return Column(children: [
                TextFormField(
                    initialValue: banks.first.name,
                    enabled: false,
                    decoration:
                        const InputDecoration(labelText: 'From Account')),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                    initialValue: custodians.first.userId,
                    decoration:
                        const InputDecoration(labelText: 'To Custodian'),
                    items: custodians
                        .map((c) => DropdownMenuItem(
                            value: c.userId, child: Text(c.name)))
                        .toList(),
                    onChanged: (value) => _selectedCustodian = value),
                const SizedBox(height: 12),
                TextField(
                    controller: _amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: const [NgnAmountInputFormatter()],
                    decoration: const InputDecoration(labelText: 'Amount (₦)')),
                const SizedBox(height: 12),
                AccountsDatePickerField(
                    initialCanonicalDate: _date,
                    onChanged: (value) => _date = value),
                const SizedBox(height: 12),
                TextField(
                    controller: _reference,
                    decoration:
                        const InputDecoration(labelText: 'Zenith Reference')),
                const SizedBox(height: 12),
                TextField(
                    controller: _description,
                    decoration: const InputDecoration(
                        labelText: 'Description / notes')),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                    onPressed: () async {
                      final file = await _picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 90,
                          maxWidth: 2400);
                      if (file != null && mounted) {
                        setState(() => _proof = file);
                      }
                    },
                    icon: const Icon(Icons.attach_file),
                    label: Text(_proof == null
                        ? 'Optional proof'
                        : 'Proof: ${_proof!.name}')),
                const SizedBox(height: 12),
                TextFormField(
                    initialValue: widget.session.user.fullName,
                    enabled: false,
                    decoration: const InputDecoration(labelText: 'Entered by')),
                const SizedBox(height: 18),
                FilledButton(
                    onPressed: _saving
                        ? null
                        : () => _save(banks.first.id,
                            _selectedCustodian ?? custodians.first.userId),
                    child: Text(_saving ? 'Saving…' : 'Record Funding')),
              ]);
            },
          ),
        ],
      );

  int? _selectedCustodian;
  Future<void> _save(int bankId, int custodianId) async {
    setState(() => _saving = true);
    try {
      final amount = parseNgnInput(_amount.text);
      if (amount == null) throw const ApiException('INVALID_AMOUNT');
      final fundingId = await _api.fundPettyCash(widget.session, {
        'bank_account_id': bankId,
        'custodian_user_id': custodianId,
        'amount': amount,
        'funding_date': _date,
        'bank_reference': _reference.text,
        'description': _description.text,
      });
      if (_proof != null) {
        final bytes = await _proof!.readAsBytes();
        final lower = _proof!.name.toLowerCase();
        await _api.uploadFinancialEvidence(widget.session,
            sourceType: 'PETTY_CASH_FUNDING',
            sourceRecordId: fundingId,
            filename: _proof!.name,
            mimeType: lower.endsWith('.png') ? 'image/png' : 'image/jpeg',
            bytes: bytes);
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class AccountsPettyExpenseScreen extends StatefulWidget {
  const AccountsPettyExpenseScreen({super.key, required this.session});
  final CehSession session;
  @override
  State<AccountsPettyExpenseScreen> createState() =>
      _AccountsPettyExpenseScreenState();
}

class _AccountsPettyExpenseScreenState
    extends State<AccountsPettyExpenseScreen> {
  final _api = const CehApiClient();
  final _picker = ImagePicker();
  final _amount = TextEditingController();
  final _supplier = TextEditingController();
  final _description = TextEditingController();
  final _noReceiptReason = TextEditingController();
  int? _custodian;
  int? _account;
  int? _client;
  int? _project;
  int? _mixer;
  XFile? _receipt;
  bool _noReceipt = false;
  bool _saving = false;
  String _date = canonicalAccountsDate(DateTime.now());
  String? _issuedReference;
  late Future<_ExpenseLookups> _lookups;

  @override
  void initState() {
    super.initState();
    _lookups = _loadLookups();
  }

  Future<_ExpenseLookups> _loadLookups() async {
    final overview = await _api.pettyCashOverview(widget.session);
    final accounts = await _api.financialAccounts(widget.session);
    final clients = await _api.clients(widget.session);
    final projectGroups = await Future.wait(
        clients.map((client) => _api.projects(widget.session, client.id)));
    final mixers = await _api.mixers(widget.session);
    return _ExpenseLookups(
      overview: overview,
      accounts: accounts,
      clients: clients,
      projects: projectGroups.expand((items) => items).toList(),
      mixers: mixers,
    );
  }

  Future<void> _pickReceipt(ImageSource source) async {
    final selected = await _picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 2400,
    );
    if (selected != null && mounted) {
      setState(() {
        _receipt = selected;
        _noReceipt = false;
      });
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _amount,
      _supplier,
      _description,
      _noReceiptReason
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AccountsLivePage(
        session: widget.session,
        title: 'Add Petty Cash Expense',
        children: [
          FutureBuilder<_ExpenseLookups>(
            future: _lookups,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _AccountsLoadError(
                    snapshot.error!, () => setState(() {}));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final lookup = snapshot.data!;
              final custodians = lookup.overview.custodians;
              final accounts = lookup.accounts
                  .where((a) =>
                      a.accountType == 'EXPENSE' && a.isPostable && a.isActive)
                  .toList();
              if (custodians.isEmpty || accounts.isEmpty) {
                return const Text(
                    'Custodian and expense accounts are required.');
              }
              return Column(children: [
                TextFormField(
                    initialValue: _issuedReference ??
                        'Issued automatically after creation',
                    enabled: false,
                    decoration:
                        const InputDecoration(labelText: 'CEH reference')),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                    initialValue: custodians.first.userId,
                    decoration: const InputDecoration(labelText: 'Custodian'),
                    items: custodians
                        .map((c) => DropdownMenuItem(
                            value: c.userId, child: Text(c.name)))
                        .toList(),
                    onChanged: (value) => _custodian = value),
                const SizedBox(height: 12),
                AccountsDatePickerField(
                    initialCanonicalDate: _date,
                    onChanged: (value) => _date = value),
                const SizedBox(height: 12),
                TextField(
                    controller: _amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: const [NgnAmountInputFormatter()],
                    decoration: const InputDecoration(labelText: 'Amount (₦)')),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                    initialValue: accounts.first.id,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: accounts
                        .map((a) => DropdownMenuItem(
                            value: a.id, child: Text('${a.code} • ${a.name}')))
                        .toList(),
                    onChanged: (value) => _account = value),
                const SizedBox(height: 12),
                TextField(
                    controller: _supplier,
                    decoration:
                        const InputDecoration(labelText: 'Supplier / Paid To')),
                const SizedBox(height: 12),
                TextField(
                    controller: _description,
                    maxLines: 3,
                    decoration:
                        const InputDecoration(labelText: 'Description')),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                    initialValue: _client,
                    decoration: const InputDecoration(
                        labelText: 'Client allocation (optional)'),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('Not allocated')),
                      ...lookup.clients.map((client) => DropdownMenuItem<int?>(
                          value: client.id, child: Text(client.name)))
                    ],
                    onChanged: (value) => setState(() {
                          _client = value;
                          _project = null;
                        })),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                    key: ValueKey('expense-project-${_client ?? 0}'),
                    initialValue: _project,
                    decoration: const InputDecoration(
                        labelText: 'Project / Site (optional)'),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('Not allocated')),
                      ...lookup.projects
                          .where((project) => project.clientId == _client)
                          .map((project) => DropdownMenuItem<int?>(
                              value: project.id, child: Text(project.name)))
                    ],
                    onChanged: _client == null
                        ? null
                        : (value) => setState(() => _project = value)),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                    initialValue: _mixer,
                    decoration: const InputDecoration(
                        labelText: 'Equipment / Mixer (optional)'),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('Not allocated')),
                      ...lookup.mixers.map((mixer) => DropdownMenuItem<int?>(
                          value: (mixer['id'] as num).toInt(),
                          child: Text(
                              '${mixer['code'] ?? mixer['name'] ?? mixer['id']}')))
                    ],
                    onChanged: (value) => setState(() => _mixer = value)),
                const SizedBox(height: 18),
                const AccountsSectionTitle('Receipt / evidence'),
                Wrap(spacing: 10, runSpacing: 8, children: [
                  OutlinedButton.icon(
                      onPressed: _noReceipt
                          ? null
                          : () => _pickReceipt(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Take Photo')),
                  OutlinedButton.icon(
                      onPressed: _noReceipt
                          ? null
                          : () => _pickReceipt(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose Existing Photo')),
                ]),
                if (_receipt != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.verified_outlined),
                    title: const Text('Receipt selected'),
                    subtitle: Text(_receipt!.name),
                  ),
                CheckboxListTile(
                    value: _noReceipt,
                    title: const Text('No Receipt'),
                    onChanged: (value) => setState(() {
                          _noReceipt = value ?? false;
                          if (_noReceipt) _receipt = null;
                        })),
                if (_noReceipt)
                  TextField(
                      controller: _noReceiptReason,
                      decoration: const InputDecoration(
                          labelText: 'Reason (required)')),
                const SizedBox(height: 12),
                TextFormField(
                    initialValue: widget.session.user.fullName,
                    enabled: false,
                    decoration: const InputDecoration(labelText: 'Entered by')),
                const SizedBox(height: 18),
                FilledButton(
                    onPressed: _saving
                        ? null
                        : () => _save(_custodian ?? custodians.first.userId,
                            _account ?? accounts.first.id),
                    child: Text(_saving ? 'Saving…' : 'Save and Submit')),
              ]);
            },
          ),
        ],
      );

  Future<void> _save(int custodianId, int accountId) async {
    setState(() => _saving = true);
    try {
      final amount = parseNgnInput(_amount.text);
      if (amount == null) throw const ApiException('INVALID_AMOUNT');
      final created = await _api.createPettyCashExpense(widget.session, {
        'custodian_user_id': custodianId,
        'expense_date': _date,
        'amount': amount,
        'expense_account_id': accountId,
        'supplier_paid_to': _supplier.text,
        'description': _description.text,
        if (_client != null) 'client_id': _client,
        if (_project != null) 'project_id': _project,
        if (_mixer != null) 'mixer_id': _mixer,
        if (_noReceipt) 'no_receipt_reason': _noReceiptReason.text,
      });
      if (!_noReceipt && _receipt == null) {
        throw const ApiException('RECEIPT_OR_REASON_REQUIRED');
      }
      if (mounted) setState(() => _issuedReference = created.reference);
      if (_receipt != null) {
        final bytes = await _receipt!.readAsBytes();
        final lower = _receipt!.name.toLowerCase();
        final mime = lower.endsWith('.png') ? 'image/png' : 'image/jpeg';
        await _api.uploadFinancialEvidence(widget.session,
            sourceType: 'PETTY_CASH_EXPENSE',
            sourceRecordId: created.id,
            filename: _receipt!.name,
            mimeType: mime,
            bytes: bytes);
      }
      await _api.submitPettyCashExpense(widget.session, created.id);
      if (mounted) {
        await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
                  title: Text(created.reference),
                  content:
                      const Text('Petty Cash Expense created and submitted.'),
                  actions: [
                    FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'))
                  ],
                ));
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ExpenseLookups {
  const _ExpenseLookups({
    required this.overview,
    required this.accounts,
    required this.clients,
    required this.projects,
    required this.mixers,
  });
  final PettyCashOverview overview;
  final List<FinancialAccount> accounts;
  final List<CehClient> clients;
  final List<CehProject> projects;
  final List<Map<String, dynamic>> mixers;
}
