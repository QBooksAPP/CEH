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
import 'accounts_general_expense_screen.dart';

class _AccountsLivePage extends StatelessWidget {
  const _AccountsLivePage({
    required this.session,
    required this.title,
    required this.children,
    this.requireAdmin = true,
  });
  final CehSession session;
  final String title;
  final List<Widget> children;
  final bool requireAdmin;

  @override
  Widget build(BuildContext context) {
    if (requireAdmin && !isUiAdmin(context, session)) {
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

enum PettyCashExpenseSection { needsApproval, drafts, history }

PettyCashExpenseSection? pettyCashExpenseSection(Object? status) {
  switch ('$status'.toUpperCase()) {
    case 'SUBMITTED':
      return PettyCashExpenseSection.needsApproval;
    case 'DRAFT':
    case 'CORRECTION_REQUIRED':
      return PettyCashExpenseSection.drafts;
    case 'APPROVED':
    case 'CANCELLED_NOT_SPENT':
    case 'VOIDED':
      return PettyCashExpenseSection.history;
    default:
      return null;
  }
}

List<Map<String, dynamic>> pettyCashExpensesForSection(
  Iterable<Map<String, dynamic>> expenses,
  PettyCashExpenseSection section,
) =>
    expenses
        .where(
            (expense) => pettyCashExpenseSection(expense['status']) == section)
        .toList(growable: false);

bool canManagePettyCashDraft({
  required bool isAdmin,
  required int currentUserId,
  required Object? custodianUserId,
}) =>
    isAdmin ||
    (custodianUserId is num
            ? custodianUserId.toInt()
            : int.tryParse('${custodianUserId ?? ''}')) ==
        currentUserId;

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
                          if (row.amount < 0 &&
                              const {'UNMATCHED', 'POSSIBLE_DUPLICATE'}
                                  .contains(row.status))
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                onPressed: row.status == 'POSSIBLE_DUPLICATE'
                                    ? null
                                    : () async {
                                        await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    AccountsGeneralExpenseScreen(
                                                        session: widget.session,
                                                        statement: row)));
                                        _retry();
                                      },
                                icon: const Icon(Icons.add_card_outlined),
                                label:
                                    const Text('Create Expense from Statement'),
                              ),
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

class AccountsExpensesScreen extends StatefulWidget {
  const AccountsExpensesScreen({super.key, required this.session});
  final CehSession session;

  @override
  State<AccountsExpensesScreen> createState() => _AccountsExpensesScreenState();
}

class _AccountsExpensesScreenState extends State<AccountsExpensesScreen> {
  final _api = const CehApiClient();
  late Future<List<ConsolidatedExpense>> _future;
  String _filter = 'ACTIVE';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = _api.consolidatedExpenses(widget.session);
  void _retry() => setState(_load);

  List<ConsolidatedExpense> _filtered(List<ConsolidatedExpense> expenses) {
    switch (_filter) {
      case 'PETTY_CASH':
        return expenses
            .where((expense) => expense.sourceType == 'PETTY_CASH')
            .toList();
      case 'BANK':
        return expenses
            .where((expense) => expense.sourceType == 'BANK')
            .toList();
      case 'PENDING':
        return expenses
            .where((expense) => const {
                  'DRAFT',
                  'SUBMITTED',
                  'CORRECTION_REQUIRED'
                }.contains(expense.lifecycleStatus))
            .toList();
      case 'VOIDED':
        return expenses
            .where((expense) => expense.lifecycleStatus == 'VOIDED')
            .toList();
      case 'ALL':
        return expenses;
      default:
        return expenses
            .where((expense) => expense.lifecycleStatus == 'APPROVED')
            .toList();
    }
  }

  String _actionSource(ConsolidatedExpense expense) =>
      expense.sourceType == 'PETTY_CASH'
          ? 'PETTY_CASH_EXPENSE'
          : expense.sourceType == 'BANK'
              ? 'GENERAL_EXPENSE'
              : expense.sourceType;

  Future<String?> _expenseReason(String title, String warning) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(warning),
          const SizedBox(height: 12),
          TextField(
              controller: controller,
              maxLines: 3,
              decoration:
                  const InputDecoration(labelText: 'Reason (required)')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back')),
          FilledButton(
              onPressed: () {
                final reason = controller.text.trim();
                if (reason.isNotEmpty) Navigator.pop(context, reason);
              },
              child: const Text('Confirm')),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _deleteExpense(ConsolidatedExpense expense) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Draft Expense?'),
            content: const Text(
                'This permanently removes the unposted draft and its evidence. Any issued reference remains retired forever.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Back')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete Draft')),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _runExpenseAction(() => _api.deleteExpense(widget.session,
        sourceType: _actionSource(expense),
        sourceRecordId: expense.sourceRecordId));
  }

  Future<void> _openGeneralDraft(ConsolidatedExpense expense) async {
    try {
      final rows = await _api.generalExpenses(widget.session);
      final record = rows.cast<Map<String, dynamic>>().firstWhere(
          (row) => (row['id'] as num).toInt() == expense.sourceRecordId);
      if (!mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AccountsGeneralExpenseScreen(
                  session: widget.session, expense: record)));
      _retry();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code)));
      }
    }
  }

  Future<void> _cancelExpense(ConsolidatedExpense expense) async {
    final reason = await _expenseReason('Cancel / Not Spent',
        'Use only when the expense did not occur. Otherwise require correction.');
    if (reason == null) return;
    await _runExpenseAction(() => expense.sourceType == 'BANK'
        ? _api.reviewGeneralExpense(widget.session,
            expenseId: expense.sourceRecordId,
            action: 'CANCELLED_NOT_SPENT',
            reason: reason)
        : _api.reviewPettyCashExpense(widget.session,
            expenseId: expense.sourceRecordId,
            action: 'CANCELLED_NOT_SPENT',
            reason: reason));
  }

  Future<void> _voidPostedExpense(ConsolidatedExpense expense) async {
    String? basis;
    if (expense.sourceType == 'BANK') {
      basis = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Bank expense Void basis'),
          children: [
            SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'DUPLICATE_ACCOUNTING'),
                child: const Text('Duplicate accounting record')),
            SimpleDialogOption(
                onPressed: () =>
                    Navigator.pop(context, 'ECONOMICALLY_NEVER_EXISTED'),
                child: const Text('Transaction economically never existed')),
            SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'ACTUAL_LINKED_REFUND'),
                child: const Text('Actual bank refund already linked')),
          ],
        ),
      );
      if (basis == null) return;
    }
    final reason = await _expenseReason(
        'Void Posted Expense?',
        expense.sourceType == 'BANK'
            ? 'Wrong coding must use Reclassify. A matched Zenith debit cannot be voided unless a valid duplicate or actual-refund rule is satisfied.'
            : 'The original record, evidence and journal remain. A linked reversing journal will be posted.');
    if (reason == null) return;
    await _runExpenseAction(() => _api.voidExpense(widget.session,
        sourceType: _actionSource(expense),
        sourceRecordId: expense.sourceRecordId,
        reason: reason,
        voidBasis: basis));
  }

  Future<void> _reclassifyLine(
      ConsolidatedExpense expense, ExpenseLine line) async {
    if (line.id == null) return;
    final accounts = (await _api.financialAccounts(widget.session))
        .where((account) =>
            account.accountType == 'EXPENSE' &&
            account.isActive &&
            account.isPostable)
        .toList();
    if (!mounted || accounts.isEmpty) return;
    var accountId =
        accounts.any((account) => account.id == line.expenseAccountId)
            ? line.expenseAccountId
            : accounts.first.id;
    final description = TextEditingController(text: line.description);
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Correct line ${line.lineNo}'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                  initialValue: accountId,
                  decoration:
                      const InputDecoration(labelText: 'Correct category'),
                  items: accounts
                      .map((account) => DropdownMenuItem(
                          value: account.id, child: Text(account.name)))
                      .toList(),
                  onChanged: (value) => accountId = value ?? accountId),
              TextField(
                  controller: description,
                  decoration:
                      const InputDecoration(labelText: 'Line description')),
              TextField(
                  controller: reason,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'Reason (required)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Back')),
              FilledButton(
                  onPressed: () {
                    if (reason.text.trim().isNotEmpty) {
                      Navigator.pop(context, true);
                    }
                  },
                  child: const Text('Post Reclassification')),
            ],
          ),
        ) ??
        false;
    if (confirmed) {
      await _runExpenseAction(() => _api.reclassifyExpenseLine(widget.session,
              sourceType: _actionSource(expense),
              sourceRecordId: expense.sourceRecordId,
              lineId: line.id!,
              reason: reason.text.trim(),
              classification: {
                'expense_account_id': accountId,
                'description': description.text.trim(),
              }));
    }
    description.dispose();
    reason.dispose();
  }

  Future<void> _runExpenseAction(Future<void> Function() action) async {
    try {
      await action();
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
        title: 'Expenses',
        children: [
          const AccountsSectionTitle('Expense register',
              subtitle: 'Active, pending and voided accounting expenses'),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () async {
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AccountsGeneralExpenseScreen(
                            session: widget.session)));
                _retry();
              },
              icon: const Icon(Icons.account_balance_outlined),
              label: const Text('Add Bank-Paid Expense'),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final filter in [
                'ACTIVE',
                'PENDING',
                'VOIDED',
                'ALL',
                'PETTY_CASH',
                'BANK'
              ])
                ChoiceChip(
                  label: Text(filter[0] + filter.substring(1).toLowerCase()),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<ConsolidatedExpense>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _AccountsLoadError(snapshot.error!, _retry);
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final expenses = _filtered(snapshot.data!);
              if (expenses.isEmpty) {
                return const Text('No expenses match this filter.');
              }
              return Column(
                children: [
                  for (final expense in expenses)
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
                            '${expense.category} • ${displayAccountsDate(expense.date)} • ${expense.lifecycleStatus}'),
                        children: [
                          AccountsMetricLine(
                              'Supplier / Paid To', expense.supplier),
                          AccountsMetricLine(
                              'Description', expense.description),
                          if (expense.lines.isNotEmpty) ...[
                            const Divider(),
                            for (final line in expense.lines)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title:
                                    Text('${line.lineNo}. ${line.description}'),
                                subtitle: Text(
                                    '${line.category}${line.client == null ? '' : ' • ${line.client}'}${line.project == null ? '' : ' • ${line.project}'}${line.equipment == null ? '' : ' • ${line.equipment}'}'),
                                trailing: Text(formatNaira(line.amount),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                onTap: expense.lifecycleStatus == 'APPROVED' &&
                                        line.id != null
                                    ? () => _reclassifyLine(expense, line)
                                    : null,
                              ),
                          ],
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
                          AccountsMetricLine('Posting status', expense.status),
                          AccountsMetricLine('Original journal',
                              expense.originalJournalReference ?? 'Not posted'),
                          if (expense.reversalJournalReference != null)
                            AccountsMetricLine('Reversal journal',
                                expense.reversalJournalReference!),
                          if (expense.reclassificationJournalReference !=
                              null) ...[
                            AccountsMetricLine(
                                'Latest reclassification journal',
                                expense.reclassificationJournalReference!),
                            AccountsMetricLine('Reclassified by',
                                expense.reclassifiedBy ?? 'Admin'),
                            AccountsMetricLine('Reclassification date',
                                expense.reclassifiedAt ?? 'Not recorded'),
                            AccountsMetricLine(
                                'Reclassification reason',
                                expense.reclassificationReason ??
                                    'Not recorded'),
                          ],
                          if (expense.lifecycleStatus == 'VOIDED') ...[
                            AccountsMetricLine(
                                'Voided by', expense.voidedBy ?? 'Admin'),
                            AccountsMetricLine('Void date',
                                expense.voidedAt ?? 'Not recorded'),
                            AccountsMetricLine('Void reason',
                                expense.voidReason ?? 'Not recorded'),
                          ],
                          Align(
                            alignment: Alignment.centerRight,
                            child: AccountsStatusChip(expense.status),
                          ),
                          if (expense.lifecycleStatus == 'DRAFT')
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              children: [
                                if (expense.sourceType == 'BANK')
                                  OutlinedButton.icon(
                                    onPressed: () => _openGeneralDraft(expense),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Continue Draft'),
                                  ),
                                TextButton.icon(
                                  onPressed: () => _deleteExpense(expense),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Delete Draft'),
                                ),
                              ],
                            ),
                          if (const {'SUBMITTED', 'CORRECTION_REQUIRED'}
                              .contains(expense.lifecycleStatus))
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              children: [
                                if (expense.sourceType == 'BANK' &&
                                    expense.lifecycleStatus ==
                                        'CORRECTION_REQUIRED')
                                  OutlinedButton.icon(
                                    onPressed: () => _openGeneralDraft(expense),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Correct & Resubmit'),
                                  ),
                                if (expense.sourceType == 'BANK' &&
                                    expense.lifecycleStatus == 'SUBMITTED') ...[
                                  FilledButton(
                                      onPressed: () => _runExpenseAction(() =>
                                          _api.reviewGeneralExpense(
                                              widget.session,
                                              expenseId: expense.sourceRecordId,
                                              action: 'APPROVE')),
                                      child: const Text('Approve')),
                                  OutlinedButton(
                                      onPressed: () async {
                                        final reason = await _expenseReason(
                                            'Correction Required',
                                            'Return this expense for correction without posting it.');
                                        if (reason != null) {
                                          await _runExpenseAction(() =>
                                              _api.reviewGeneralExpense(
                                                  widget.session,
                                                  expenseId:
                                                      expense.sourceRecordId,
                                                  action: 'CORRECTION_REQUIRED',
                                                  reason: reason));
                                        }
                                      },
                                      child: const Text('Correction Required')),
                                ],
                                TextButton(
                                  onPressed: () => _cancelExpense(expense),
                                  child: const Text('Cancel / Not Spent'),
                                ),
                              ],
                            ),
                          if (expense.lifecycleStatus == 'APPROVED')
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: () => _voidPostedExpense(expense),
                                icon: const Icon(Icons.undo_outlined),
                                label: const Text('Void Expense'),
                              ),
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

  Future<void> _review(int id, String action, {String? reason}) async {
    try {
      await _api.reviewPettyCashExpense(widget.session,
          expenseId: id,
          action: action,
          reason: reason ??
              (action == 'APPROVE'
                  ? ''
                  : action == 'CORRECTION_REQUIRED'
                      ? 'Correction required by Admin'
                      : 'Admin confirmed money was not spent'));
      _reload();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code)));
      }
    }
  }

  Future<String?> _reasonDialog({
    required String title,
    required String warning,
    required String actionLabel,
  }) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(warning),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Reason (required)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back')),
          FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.pop(context, value);
              },
              child: Text(actionLabel)),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }

  Future<void> _deleteDraft(Map<String, dynamic> expense) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Draft Expense?'),
            content: const Text(
                'This permanently removes the unposted draft and its receipt/evidence. The issued CEH-PC reference will remain retired and will never be reused.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep Draft')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete Draft')),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await _api.deleteExpense(widget.session,
          sourceType: 'PETTY_CASH_EXPENSE',
          sourceRecordId: (expense['id'] as num).toInt());
      _reload();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code)));
      }
    }
  }

  Future<void> _cancelNotSpent(Map<String, dynamic> expense) async {
    final reason = await _reasonDialog(
      title: 'Cancel / Not Spent',
      warning:
          'Use this only when the money was not spent. If the expense occurred but paperwork is wrong, choose Correction Required instead.',
      actionLabel: 'Confirm Not Spent',
    );
    if (reason == null) return;
    await _review((expense['id'] as num).toInt(), 'CANCELLED_NOT_SPENT',
        reason: reason);
  }

  Future<void> _voidExpense(Map<String, dynamic> expense) async {
    final reason = await _reasonDialog(
      title: 'Void Posted Expense?',
      warning:
          'Use Void only when the transaction should not exist, such as a duplicate, mistaken entry, or money genuinely returned. This restores Petty Cash. For wrong coding when money was genuinely spent, use Correct / Reclassify instead.',
      actionLabel: 'Void Expense',
    );
    if (reason == null) return;
    try {
      await _api.voidExpense(widget.session,
          sourceType: 'PETTY_CASH_EXPENSE',
          sourceRecordId: (expense['id'] as num).toInt(),
          reason: reason);
      _reload();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code)));
      }
    }
  }

  Future<void> _submit(int id) async {
    try {
      await _api.submitPettyCashExpense(widget.session, id);
      _reload();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code)));
      }
    }
  }

  Future<void> _openDraft(Map<String, dynamic> expense) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountsPettyExpenseScreen(
          session: widget.session,
          expense: expense,
        ),
      ),
    );
    _reload();
  }

  Future<void> _openReclassification(Map<String, dynamic> expense) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountsPettyExpenseScreen(
          session: widget.session,
          expense: expense,
          reclassifyPosted: true,
        ),
      ),
    );
    _reload();
  }

  Widget _expenseCard(
    Map<String, dynamic> expense, {
    required bool isAdmin,
    required PettyCashExpenseSection section,
  }) {
    final status = '${expense['status']}';
    final canManageDraft = canManagePettyCashDraft(
      isAdmin: isAdmin,
      currentUserId: widget.session.user.id,
      custodianUserId: expense['custodian_user_id'],
    );
    final evidenceCount = (expense['evidence_count'] as num?)?.toInt() ?? 0;
    final reference = expense['reference_no'] ?? 'Reference pending';
    final postingStatus = status == 'VOIDED'
        ? 'VOIDED / REVERSED'
        : status == 'APPROVED'
            ? 'APPROVED / POSTED'
            : status == 'CANCELLED_NOT_SPENT'
                ? 'CANCELLED / NOT POSTED'
                : status;
    return Card(
      child: ExpansionTile(
        title: Text(
          '$reference • ${formatNaira(double.tryParse('${expense['amount']}') ?? 0)}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          '${expense['custodian_name']} • ${displayAccountsDate('${expense['expense_date']}')} • $status',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          AccountsMetricLine('CEH-PC reference', '$reference'),
          AccountsMetricLine(
              'Date', displayAccountsDate('${expense['expense_date']}')),
          AccountsMetricLine('Amount',
              formatNaira(double.tryParse('${expense['amount']}') ?? 0)),
          AccountsMetricLine('Custodian', '${expense['custodian_name']}'),
          AccountsMetricLine('Paid To', '${expense['supplier_paid_to']}'),
          AccountsMetricLine('Description', '${expense['description']}'),
          AccountsMetricLine(
              'Client', '${expense['client_name'] ?? 'Not allocated'}'),
          AccountsMetricLine(
              'Project', '${expense['project_name'] ?? 'Not allocated'}'),
          AccountsMetricLine(
              'Equipment', '${expense['mixer_code'] ?? 'Not allocated'}'),
          AccountsMetricLine('Receipt / evidence',
              evidenceCount == 0 ? 'No receipt' : 'Attached'),
          AccountsMetricLine('Approval / posting status', postingStatus),
          if (expense['original_journal_reference'] != null)
            AccountsMetricLine(
                'Original journal', '${expense['original_journal_reference']}'),
          if (expense['reversal_journal_reference'] != null)
            AccountsMetricLine(
                'Reversal journal', '${expense['reversal_journal_reference']}'),
          if (expense['reclassification_journal_reference'] != null) ...[
            AccountsMetricLine('Latest reclassification journal',
                '${expense['reclassification_journal_reference']}'),
            AccountsMetricLine('Reclassified by',
                '${expense['reclassified_by_name'] ?? 'Admin'}'),
            AccountsMetricLine('Reclassification date',
                '${expense['reclassified_at'] ?? 'Not recorded'}'),
            AccountsMetricLine('Reclassification reason',
                '${expense['reclassification_reason'] ?? 'Not recorded'}'),
          ],
          if (status == 'VOIDED') ...[
            AccountsMetricLine(
                'Voided by', '${expense['voided_by_name'] ?? 'Admin'}'),
            AccountsMetricLine(
                'Void date', '${expense['voided_at'] ?? 'Not recorded'}'),
            AccountsMetricLine(
                'Void reason', '${expense['void_reason'] ?? 'Not recorded'}'),
          ],
          if (section == PettyCashExpenseSection.needsApproval && isAdmin)
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(
                onPressed: () =>
                    _review((expense['id'] as num).toInt(), 'APPROVE'),
                child: const Text('Approve'),
              ),
              OutlinedButton(
                onPressed: () => _review(
                    (expense['id'] as num).toInt(), 'CORRECTION_REQUIRED'),
                child: const Text('Correction Required'),
              ),
              TextButton(
                onPressed: () => _cancelNotSpent(expense),
                child: const Text('Cancel / Not Spent'),
              ),
            ]),
          if (section == PettyCashExpenseSection.drafts && canManageDraft)
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => _openDraft(expense),
                icon: const Icon(Icons.edit_outlined),
                label: Text(status == 'CORRECTION_REQUIRED'
                    ? 'Correct & Resubmit'
                    : 'Continue Draft'),
              ),
              OutlinedButton.icon(
                onPressed: () => _submit((expense['id'] as num).toInt()),
                icon: const Icon(Icons.send_outlined),
                label: const Text('Submit Expense'),
              ),
              if (isAdmin && status == 'DRAFT')
                TextButton.icon(
                  onPressed: () => _deleteDraft(expense),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete Draft'),
                ),
              if (isAdmin && status == 'CORRECTION_REQUIRED')
                TextButton(
                  onPressed: () => _cancelNotSpent(expense),
                  child: const Text('Cancel / Not Spent'),
                ),
            ]),
          if (section == PettyCashExpenseSection.history &&
              isAdmin &&
              status == 'APPROVED')
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => _openReclassification(expense),
                icon: const Icon(Icons.swap_horiz_outlined),
                label: const Text('Correct / Reclassify'),
              ),
              OutlinedButton.icon(
                onPressed: () => _voidExpense(expense),
                icon: const Icon(Icons.undo_outlined),
                label: const Text('Void Expense'),
              ),
            ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _AccountsLivePage(
        session: widget.session,
        title: 'Petty Cash',
        requireAdmin: false,
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
              final isAdmin = isUiAdmin(context, widget.session);
              final needsApproval = pettyCashExpensesForSection(
                  expenses, PettyCashExpenseSection.needsApproval);
              final drafts = pettyCashExpensesForSection(
                  expenses, PettyCashExpenseSection.drafts);
              final history = pettyCashExpensesForSection(
                  expenses, PettyCashExpenseSection.history);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isAdmin)
                    SizedBox(
                      height: 190,
                      child: AccountsSummaryCard(
                        label: 'TOTAL PETTY CASH OUTSTANDING',
                        value: overview.totalPettyCash,
                        detail:
                            'Across ${overview.custodians.length} active custodians',
                        emphasized: true,
                      ),
                    ),
                  if (isAdmin) const SizedBox(height: 14),
                  Wrap(spacing: 10, runSpacing: 8, children: [
                    if (isAdmin)
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
                    if (isAdmin)
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
                  AccountsSectionTitle(
                      isAdmin ? 'Custodian balances' : 'My Balance'),
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
                            AccountsMetricLine('Current Balance',
                                formatNaira(custodian.balance),
                                prominent: true),
                            AccountsMetricLine('Available to Spend',
                                formatNaira(custodian.available)),
                            if (!isAdmin)
                              AccountsMetricLine('Pending Approval',
                                  formatNaira(custodian.pending)),
                            if (isAdmin) ...[
                              AccountsMetricLine('Pending Approval',
                                  formatNaira(custodian.pending)),
                              const Divider(),
                              const Text('This Month',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w900)),
                              AccountsMetricLine(
                                  'Funds Received',
                                  formatNaira(
                                      custodian.thisMonthFundsReceived)),
                              AccountsMetricLine('Accounted / Spent',
                                  formatNaira(custodian.thisMonthAccounted)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (isAdmin) ...[
                    const AccountsSectionTitle('Needs Approval'),
                    if (needsApproval.isEmpty)
                      const Text('No expenses awaiting approval'),
                    for (final expense in needsApproval)
                      _expenseCard(expense,
                          isAdmin: true,
                          section: PettyCashExpenseSection.needsApproval),
                    const SizedBox(height: 20),
                  ],
                  AccountsSectionTitle(isAdmin
                      ? 'Drafts / Needs Correction'
                      : 'My Drafts / Corrections'),
                  if (drafts.isEmpty)
                    const Text('No drafts or corrections requiring action.'),
                  for (final expense in drafts)
                    _expenseCard(expense,
                        isAdmin: isAdmin,
                        section: PettyCashExpenseSection.drafts),
                  const SizedBox(height: 20),
                  AccountsSectionTitle(isAdmin
                      ? 'Transaction History'
                      : 'My Transaction History'),
                  if (history.isEmpty)
                    const Text('No completed petty cash transactions.'),
                  for (final expense in history)
                    _expenseCard(expense,
                        isAdmin: isAdmin,
                        section: PettyCashExpenseSection.history),
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
  const AccountsPettyExpenseScreen({
    super.key,
    required this.session,
    this.expense,
    this.reclassifyPosted = false,
  });
  final CehSession session;
  final Map<String, dynamic>? expense;
  final bool reclassifyPosted;
  @override
  State<AccountsPettyExpenseScreen> createState() =>
      _AccountsPettyExpenseScreenState();
}

class _AccountsPettyExpenseScreenState
    extends State<AccountsPettyExpenseScreen> {
  final _api = const CehApiClient();
  final _picker = ImagePicker();
  final _amount = TextEditingController();
  final _firstLineAmount = TextEditingController();
  final _supplier = TextEditingController();
  final _description = TextEditingController();
  final _noReceiptReason = TextEditingController();
  final _reclassificationReason = TextEditingController();
  int? _custodian;
  int? _account;
  int? _supplierId;
  int? _client;
  int? _project;
  int? _mixer;
  XFile? _receipt;
  final List<Map<String, dynamic>> _additionalLines = [];
  bool _noReceipt = false;
  bool _saving = false;
  String _date = canonicalAccountsDate(DateTime.now());
  String? _issuedReference;
  late Future<_ExpenseLookups> _lookups;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    if (expense != null) {
      _amount.text = formatNgn(double.tryParse('${expense['amount']}') ?? 0)
          .replaceFirst('₦', '');
      _supplier.text = '${expense['supplier_paid_to'] ?? ''}';
      _supplierId = (expense['supplier_id'] as num?)?.toInt();
      _description.text = '${expense['description'] ?? ''}';
      _noReceiptReason.text = '${expense['no_receipt_reason'] ?? ''}';
      _custodian = (expense['custodian_user_id'] as num?)?.toInt();
      _account = (expense['expense_account_id'] as num?)?.toInt();
      _client = (expense['client_id'] as num?)?.toInt();
      _project = (expense['project_id'] as num?)?.toInt();
      _mixer = (expense['mixer_id'] as num?)?.toInt();
      _date = '${expense['expense_date']}';
      _issuedReference = expense['reference_no']?.toString();
      _noReceipt = _noReceiptReason.text.trim().isNotEmpty;
      final existingLines = (expense['lines'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (existingLines.isNotEmpty) {
        final first = existingLines.first;
        _firstLineAmount.text = '${first['amount'] ?? ''}';
        _account = (first['expense_account_id'] as num?)?.toInt() ?? _account;
        _client = (first['client_id'] as num?)?.toInt();
        _project = (first['project_id'] as num?)?.toInt();
        _mixer = (first['mixer_id'] as num?)?.toInt();
        _additionalLines.addAll(existingLines.skip(1));
      } else {
        _firstLineAmount.text = '${expense['amount'] ?? ''}';
      }
    }
    _lookups = _loadLookups();
  }

  Future<_ExpenseLookups> _loadLookups() async {
    final overview = await _api.pettyCashOverview(widget.session);
    final accounts = await _api.financialAccounts(widget.session);
    final clients = await _api.clients(widget.session);
    final projectGroups = await Future.wait(
        clients.map((client) => _api.projects(widget.session, client.id)));
    final mixers = await _api.mixers(widget.session);
    final suppliers = await _api.expenseSuppliers(widget.session);
    return _ExpenseLookups(
      overview: overview,
      accounts: accounts,
      clients: clients,
      projects: projectGroups.expand((items) => items).toList(),
      mixers: mixers,
      suppliers: suppliers,
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
      _firstLineAmount,
      _supplier,
      _description,
      _noReceiptReason,
      _reclassificationReason,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AccountsLivePage(
        session: widget.session,
        title: widget.reclassifyPosted
            ? 'Correct / Reclassify Expense'
            : widget.expense == null
                ? 'Add Petty Cash Expense'
                : widget.expense!['status'] == 'CORRECTION_REQUIRED'
                    ? 'Correct Petty Cash Expense'
                    : 'Continue Petty Cash Draft',
        requireAdmin: false,
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
                    initialValue: _custodian ?? custodians.first.userId,
                    decoration: const InputDecoration(labelText: 'Custodian'),
                    items: custodians
                        .map((c) => DropdownMenuItem(
                            value: c.userId, child: Text(c.name)))
                        .toList(),
                    onChanged: widget.expense == null
                        ? (value) => _custodian = value
                        : null),
                const SizedBox(height: 12),
                if (widget.reclassifyPosted)
                  TextFormField(
                      initialValue: displayAccountsDate(_date),
                      enabled: false,
                      decoration: const InputDecoration(
                          labelText: 'Original expense date'))
                else
                  AccountsDatePickerField(
                      initialCanonicalDate: _date,
                      onChanged: (value) => _date = value),
                const SizedBox(height: 12),
                TextField(
                    controller: _amount,
                    enabled: !widget.reclassifyPosted,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: const [NgnAmountInputFormatter()],
                    decoration: const InputDecoration(labelText: 'Amount (₦)')),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                    initialValue: _account ?? accounts.first.id,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: accounts
                        .map((a) => DropdownMenuItem(
                            value: a.id, child: Text('${a.code} • ${a.name}')))
                        .toList(),
                    onChanged: (value) => _account = value),
                const SizedBox(height: 12),
                TextField(
                    controller: _firstLineAmount,
                    enabled: !widget.reclassifyPosted,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: const [NgnAmountInputFormatter()],
                    decoration:
                        const InputDecoration(labelText: 'Line 1 amount (₦)')),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                    initialValue: _supplierId,
                    decoration: const InputDecoration(
                        labelText: 'Supplier Master (preferred)'),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('One-off / Other Payee')),
                      ...lookup.suppliers
                          .where((supplier) => supplier.isActive)
                          .map((supplier) => DropdownMenuItem<int?>(
                              value: supplier.id, child: Text(supplier.name)))
                    ],
                    onChanged: (value) => setState(() {
                          _supplierId = value;
                          if (value != null) {
                            _supplier.text = lookup.suppliers
                                .firstWhere((item) => item.id == value)
                                .name;
                          }
                        })),
                if (_supplierId == null)
                  TextField(
                      controller: _supplier,
                      enabled: isUiAdmin(context, widget.session) ||
                          widget.expense != null,
                      decoration: InputDecoration(
                          labelText: 'One-off / Other Payee',
                          helperText: isUiAdmin(context, widget.session)
                              ? 'Admin-only; no Supplier Master record is created'
                              : 'Select a Supplier Master record')),
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
                if (!widget.reclassifyPosted) ...[
                  const SizedBox(height: 16),
                  const AccountsSectionTitle('Expense lines',
                      subtitle: 'Header total must equal all line amounts'),
                  for (var index = 0; index < _additionalLines.length; index++)
                    Card(
                        child: ListTile(
                      title: Text(
                          'Line ${index + 2} • ${_additionalLines[index]['description']}'),
                      subtitle: Text(formatNaira(double.tryParse(
                              '${_additionalLines[index]['amount']}') ??
                          0)),
                      trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              setState(() => _additionalLines.removeAt(index))),
                    )),
                  OutlinedButton.icon(
                    onPressed: () => _addExpenseLine(lookup, accounts),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Expense Line'),
                  ),
                ],
                if (widget.reclassifyPosted) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _reclassificationReason,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Correction reason (required)'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This posts expense-to-expense correction lines only. The amount, receipt, CEH-PC reference and Petty Cash balance remain unchanged.',
                  ),
                ],
                if (!widget.reclassifyPosted) ...[
                  const SizedBox(height: 18),
                  const AccountsSectionTitle('Receipt / evidence'),
                  if (widget.expense != null &&
                      ((widget.expense!['evidence_count'] as num?)?.toInt() ??
                              0) >
                          0 &&
                      _receipt == null)
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.verified_outlined),
                      title: Text('Existing receipt attached'),
                      subtitle: Text(
                          'The existing private evidence remains attached.'),
                    ),
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
                ],
                const SizedBox(height: 12),
                TextFormField(
                    initialValue: widget.session.user.fullName,
                    enabled: false,
                    decoration: const InputDecoration(labelText: 'Entered by')),
                const SizedBox(height: 18),
                if (widget.reclassifyPosted ||
                    widget.expense?['status'] == 'CORRECTION_REQUIRED')
                  FilledButton(
                      onPressed: _saving
                          ? null
                          : () => _save(_custodian ?? custodians.first.userId,
                              _account ?? accounts.first.id,
                              submit: true),
                      child: Text(_saving
                          ? 'Saving…'
                          : widget.reclassifyPosted
                              ? 'Post Reclassification'
                              : 'Correct & Resubmit'))
                else
                  Wrap(spacing: 10, runSpacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _save(_custodian ?? custodians.first.userId,
                              _account ?? accounts.first.id,
                              submit: false),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save Draft'),
                    ),
                    FilledButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _save(_custodian ?? custodians.first.userId,
                              _account ?? accounts.first.id,
                              submit: true),
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Submit Expense'),
                    ),
                  ]),
              ]);
            },
          ),
        ],
      );

  Future<void> _save(int custodianId, int accountId,
      {required bool submit}) async {
    setState(() => _saving = true);
    try {
      final amount = parseNgnInput(_amount.text);
      if (amount == null) throw const ApiException('INVALID_AMOUNT');
      final payload = <String, dynamic>{
        'custodian_user_id': custodianId,
        'expense_date': _date,
        'amount': amount,
        'expense_account_id': accountId,
        'supplier_id': _supplierId,
        'supplier_paid_to': _supplier.text,
        'description': _description.text,
        'lines': [
          {
            'description': _description.text,
            'amount': parseNgnInput(_firstLineAmount.text) ?? amount,
            'expense_account_id': accountId,
            if (_client != null) 'client_id': _client,
            if (_project != null) 'project_id': _project,
            if (_mixer != null) 'mixer_id': _mixer,
          },
          ..._additionalLines,
        ],
        if (_noReceipt) 'no_receipt_reason': _noReceiptReason.text,
      };
      if (widget.reclassifyPosted) {
        final reason = _reclassificationReason.text.trim();
        if (reason.isEmpty) {
          throw const ApiException('RECLASSIFICATION_REASON_REQUIRED');
        }
        await _api.reclassifyExpense(widget.session,
            sourceType: 'PETTY_CASH_EXPENSE',
            sourceRecordId: (widget.expense!['id'] as num).toInt(),
            reason: reason,
            classification: payload);
        if (mounted) Navigator.pop(context);
        return;
      }
      if (submit && !_noReceipt && _receipt == null) {
        final evidenceCount =
            (widget.expense?['evidence_count'] as num?)?.toInt() ?? 0;
        if (evidenceCount == 0) {
          throw const ApiException('RECEIPT_OR_REASON_REQUIRED');
        }
      }
      final CreatedPettyCashExpense created;
      if (widget.expense == null) {
        created = await _api.createPettyCashExpense(widget.session, payload);
      } else {
        final id = (widget.expense!['id'] as num).toInt();
        await _api.updatePettyCashExpense(widget.session,
            expenseId: id, payload: payload);
        created = CreatedPettyCashExpense(
          id: id,
          reference: widget.expense!['reference_no']?.toString() ??
              'Reference pending',
        );
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
      if (submit) {
        await _api.submitPettyCashExpense(widget.session, created.id);
      }
      if (mounted) {
        await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
                  title: Text(created.reference),
                  content: Text(submit
                      ? 'Petty Cash Expense created and submitted.'
                      : 'Petty Cash Expense saved as a draft.'),
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

  Future<void> _addExpenseLine(
      _ExpenseLookups lookup, List<FinancialAccount> accounts) async {
    final description = TextEditingController();
    final amount = TextEditingController();
    final quantity = TextEditingController();
    final unitPrice = TextEditingController();
    int account = accounts.first.id;
    int? client;
    int? project;
    int? mixer;
    final line = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
                  title: const Text('Add Expense Line'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: description,
                        decoration: const InputDecoration(
                            labelText: 'Item / description')),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                        initialValue: account,
                        decoration: const InputDecoration(
                            labelText: 'Expense category'),
                        items: accounts
                            .map((a) => DropdownMenuItem(
                                value: a.id, child: Text(a.name)))
                            .toList(),
                        onChanged: (v) => account = v ?? account),
                    const SizedBox(height: 10),
                    TextField(
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: const [NgnAmountInputFormatter()],
                        decoration: const InputDecoration(
                            labelText: 'Line amount (₦)')),
                    const SizedBox(height: 10),
                    TextField(
                        controller: quantity,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Quantity (optional)')),
                    const SizedBox(height: 10),
                    TextField(
                        controller: unitPrice,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: const [NgnAmountInputFormatter()],
                        decoration: const InputDecoration(
                            labelText: 'Unit price (optional)')),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                        initialValue: client,
                        decoration: const InputDecoration(
                            labelText: 'Client (optional)'),
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null, child: Text('Not allocated')),
                          ...lookup.clients.map((c) => DropdownMenuItem<int?>(
                              value: c.id, child: Text(c.name)))
                        ],
                        onChanged: (v) => setDialogState(() {
                              client = v;
                              project = null;
                            })),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                        key: ValueKey('line-project-${client ?? 0}'),
                        initialValue: project,
                        decoration: const InputDecoration(
                            labelText: 'Project (optional)'),
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null, child: Text('Not allocated')),
                          ...lookup.projects
                              .where((p) => p.clientId == client)
                              .map((p) => DropdownMenuItem<int?>(
                                  value: p.id, child: Text(p.name)))
                        ],
                        onChanged: client == null
                            ? null
                            : (v) => setDialogState(() => project = v)),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                        initialValue: mixer,
                        decoration: const InputDecoration(
                            labelText: 'Equipment (optional)'),
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null, child: Text('Not allocated')),
                          ...lookup.mixers.map((m) => DropdownMenuItem<int?>(
                              value: (m['id'] as num).toInt(),
                              child: Text('${m['code'] ?? m['name']}')))
                        ],
                        onChanged: (v) => mixer = v),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Back')),
                    FilledButton(
                        onPressed: () {
                          final parsed = parseNgnInput(amount.text);
                          if (description.text.trim().isEmpty ||
                              parsed == null) {
                            return;
                          }
                          Navigator.pop(context, {
                            'description': description.text.trim(),
                            'amount': parsed,
                            'expense_account_id': account,
                            if (quantity.text.trim().isNotEmpty)
                              'quantity': quantity.text.trim(),
                            if (unitPrice.text.trim().isNotEmpty)
                              'unit_price': parseNgnInput(unitPrice.text),
                            if (client != null) 'client_id': client,
                            if (project != null) 'project_id': project,
                            if (mixer != null) 'mixer_id': mixer
                          });
                        },
                        child: const Text('Add Line'))
                  ],
                )));
    description.dispose();
    amount.dispose();
    quantity.dispose();
    unitPrice.dispose();
    if (line != null && mounted) setState(() => _additionalLines.add(line));
  }
}

class _ExpenseLookups {
  const _ExpenseLookups({
    required this.overview,
    required this.accounts,
    required this.clients,
    required this.projects,
    required this.mixers,
    required this.suppliers,
  });
  final PettyCashOverview overview;
  final List<FinancialAccount> accounts;
  final List<CehClient> clients;
  final List<CehProject> projects;
  final List<Map<String, dynamic>> mixers;
  final List<ExpenseSupplier> suppliers;
}
