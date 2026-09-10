import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/accounts_formatters.dart';
import '../../core/internal_navigation.dart';
import '../../core/view_mode.dart';
import '../../widgets/accounts_widgets.dart';
import '../../models/accounts.dart';
import '../../models/banking_workspace.dart';
import '../../models/session.dart';
import 'accounts_general_expense_screen.dart';
import 'accounts_live_screens.dart';
import 'accounts_expense_refunds_screen.dart';
import 'accounts_banking_workspace.dart' show BankSourceDetail;

String bankingHistoryLabel(String code) =>
    const {
      'GENERAL_EXPENSE_DRAFTED': 'Expense drafted',
      'GENERAL_EXPENSE_UPDATED': 'Expense updated',
      'GENERAL_EXPENSE_SUBMITTED': 'Expense submitted',
      'GENERAL_EXPENSE_APPROVED': 'Expense approved',
      'GENERAL_EXPENSE_CORRECTION_REQUIRED': 'Expense correction requested',
      'GENERAL_EXPENSE_CANCELLED_NOT_SPENT': 'Expense cancelled (not spent)',
      'GENERAL_EXPENSE_REFUND_LINKED': 'Refund linked',
      'BANK_ROW_RECONCILED': 'Bank transaction reconciled',
      'ADMIN_CONFIRMED': 'Confirmed by administrator',
      'EXPENSE_APPROVAL': 'Reconciled on Expense approval',
    }[code] ??
    code;

class BankTransactionActions extends StatefulWidget {
  const BankTransactionActions(
      {super.key,
      required this.session,
      required this.bankId,
      required this.rowId,
      this.api = const CehApiClient()});
  final CehSession session;
  final int bankId, rowId;
  final CehApiClient api;
  @override
  State<BankTransactionActions> createState() => _ActionsState();
}

class _ActionsState extends State<BankTransactionActions> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && isUiAdmin(context, widget.session)) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.api
          .bankingDetail(widget.session, widget.bankId, widget.rowId);
      if (mounted) setState(() => _data = data);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not refresh transaction. Retry before taking action.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _money(Object? value) => formatCurrency(num.tryParse('$value') ?? 0,
      currencyCode: bankText(bankMap(_data?['bank'])['currency']));
  Widget _pair(String label, String value) =>
      ListTile(title: Text(label), subtitle: SelectableText(value));
  Future<void> _create() async {
    final row = bankMap(_data?['transaction']);
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AccountsGeneralExpenseScreen(
                session: widget.session,
                statement: CehBankTransaction.fromJson(row))));
    if (mounted) await _load();
  }

  Future<void> _match() async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => BankMatchSelection(
                session: widget.session,
                bankId: widget.bankId,
                row: bankMap(_data?['transaction']),
                api: widget.api)));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!isUiAdmin(context, widget.session)) {
      return const Scaffold(
          body: Center(child: Text('Admin access required.')));
    }
    final row = bankMap(_data?['transaction']);
    final amount = num.tryParse('${row['amount']}') ?? 0;
    return Scaffold(
        appBar: AppBar(
            title: const Text('Statement transaction'),
            actions: cehHomeAction(context)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          TextButton(
              onPressed: _busy ? null : _load, child: const Text('Refresh')),
          if (_data != null) ...[
            _pair('Bank / account', bankAccountLabel(bankMap(_data!['bank']))),
            _pair('Transaction date',
                displayAccountsDate(bankText(row['transaction_date']))),
            if (row['value_date'] != null)
              _pair('Value date',
                  displayAccountsDate(bankText(row['value_date']))),
            _pair(amount < 0 ? 'Debit' : 'Credit', _money(amount.abs())),
            _pair('Narration', bankText(row['narration'])),
            _pair('Bank reference', bankText(row['bank_reference'])),
            _pair('Source',
                'Import ${row['import_batch_id']} • ${row['source_sheet'] ?? 'Legacy'} • row ${row['source_row'] ?? 'not recorded'}'),
            _pair('Ownership',
                bankUsageLabels[row['usage_state']] ?? 'Unavailable'),
            if (_error == null && _data!['can_create_expense'] == true)
              FilledButton(
                  onPressed: _busy ? null : _create,
                  child: const Text('Create Expense')),
            if (_error == null && _data!['can_match'] == true)
              OutlinedButton(
                  onPressed: _busy ? null : _match,
                  child: const Text('Match Existing Transaction')),
            if (_error == null && _data!['can_link_refund'] == true)
              OutlinedButton(
                  onPressed: _busy ? null : _match,
                  child: const Text('Link Expense Refund')),
            if (bankMap(row['owner'])['type'] == 'GENERAL_EXPENSE')
              OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => AccountsExpensesScreen(
                                      session: widget.session,
                                      focusExpenseId: bankInt(
                                          bankMap(row['owner'])['id']))));
                          if (mounted) await _load();
                        },
                  child: const Text('Open Expense')),
            const Divider(),
            if (row['owner'] != null &&
                bankMap(row['owner'])['type'] != 'GENERAL_EXPENSE')
              OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => BankSourceDetail(
                                  session: widget.session,
                                  rowId: widget.rowId,
                                  bankId: widget.bankId))),
                  child: const Text('View linked transaction')),
            const Text('Ownership / reconciliation history (latest 100)'),
            for (final item in (_data!['history'] as List? ?? []))
              Builder(builder: (_) {
                final h = bankMap(item);
                return _pair(bankingHistoryLabel(bankText(h['action'])),
                    '${h['source_reference'] ?? ''}\n${h['actor'] ?? 'Recorded user'} • ${displayAccountsTimestampDate(bankText(h['timestamp']))} ${bankText(h['timestamp']).length >= 19 ? bankText(h['timestamp']).substring(11, 19) : ''} UTC\n${bankingHistoryLabel(bankText(h['method']))}');
              }),
          ]
        ]));
  }
}

class BankMatchSelection extends StatefulWidget {
  const BankMatchSelection(
      {super.key,
      required this.session,
      required this.bankId,
      required this.row,
      required this.api});
  final CehSession session;
  final int bankId;
  final Map<String, dynamic> row;
  final CehApiClient api;
  @override
  State<BankMatchSelection> createState() => _MatchState();
}

class _MatchState extends State<BankMatchSelection> {
  final _search = TextEditingController();
  int _page = 1;
  bool _busy = false;
  Map<String, dynamic>? _data;
  String? _error;
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && isUiAdmin(context, widget.session)) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _data = null;
    });
    try {
      final d = await widget.api.bankingDetail(
          widget.session, widget.bankId, bankInt(widget.row['id']),
          candidates: true, page: _page, search: _search.text.trim());
      if (mounted) setState(() => _data = d);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load candidates.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(Map<String, dynamic> candidate) async {
    if (_data?['purpose'] == 'REFUND') {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AccountsExpenseRefundsScreen(
                  session: widget.session,
                  expenseId: bankInt(candidate['id']))));
      if (mounted) Navigator.pop(context);
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Confirm reconciliation'),
                content: SingleChildScrollView(
                    child: Text(
                        'Bank statement\n${displayAccountsDate(bankText(widget.row['transaction_date']))}\n${formatNaira((num.tryParse('${widget.row['amount']}') ?? 0).abs())}\n${widget.row['bank_reference']}\n${widget.row['narration']}\n\nCEH transaction\n${candidate['reference']}\n${displayAccountsDate(bankText(candidate['source_date']))}\n${formatNaira(num.tryParse('${candidate['amount']}') ?? 0)}\n${candidate['bank_reference']}\n${candidate['description']}\n\nThis matches an existing accounting transaction. No new journal is created.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Confirm Match'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.reconcileBankRow(widget.session,
          statementRowId: bankInt(widget.row['id']),
          sourceType: bankText(candidate['source_type']),
          sourceRecordId: bankInt(candidate['id']));
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Match was not confirmed. Return and refresh the statement to check authoritative ownership before retrying.';
          _data = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text((num.tryParse('${widget.row['amount']}') ?? 0) > 0
              ? 'Select refunded Expense'
              : 'Match existing transaction'),
          actions: cehHomeAction(context)),
      body: !isUiAdmin(context, widget.session)
          ? const Center(child: Text('Admin access required.'))
          : ListView(padding: const EdgeInsets.all(16), children: [
              TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                      labelText: 'Reference, description or payee'),
                  enabled: !_busy,
                  onSubmitted: (_) {
                    _page = 1;
                    _load();
                  }),
              TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _page = 1;
                          _load();
                        },
                  child: const Text('Search / Refresh')),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) Text(_error!),
              if (_data?['bank'] != null)
                Text(bankAccountLabel(bankMap(_data!['bank']))),
              if (_data != null && _data!['purpose'] != 'REFUND')
                const Text('Candidates are posted and not yet reconciled.'),
              if (_data != null && (_data!['candidates'] as List).isEmpty)
                const Text('No eligible existing transactions.'),
              for (final item in (_data?['candidates'] as List? ?? []))
                Builder(builder: (_) {
                  final c = bankMap(item);
                  return Card(
                      child: ListTile(
                          title: Text(bankText(c['reference'])),
                          subtitle: Text(
                              '${c['source_type']} • ${displayAccountsDate(bankText(c['source_date']))}\n${c['description'] ?? ''}\n${c['payee'] ?? ''}'),
                          trailing: Text(
                              formatNaira(num.tryParse('${c['amount']}') ?? 0)),
                          onTap: _busy ? null : () => _confirm(c)));
                }),
              Row(children: [
                TextButton(
                    onPressed: _busy || _page == 1
                        ? null
                        : () {
                            _page--;
                            _load();
                          },
                    child: const Text('Previous')),
                Text('Page $_page'),
                TextButton(
                    onPressed: _busy || _data?['has_more'] != true
                        ? null
                        : () {
                            _page++;
                            _load();
                          },
                    child: const Text('Next'))
              ])
            ]));
}
