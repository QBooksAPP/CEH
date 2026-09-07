import 'package:flutter/material.dart';

import '../../core/accounts_formatters.dart';
import '../../core/api_client.dart';
import '../../core/internal_navigation.dart';
import '../../core/view_mode.dart';
import '../../models/expense_refunds.dart';
import '../../models/session.dart';

class AccountsExpenseRefundsScreen extends StatefulWidget {
  const AccountsExpenseRefundsScreen(
      {super.key,
      required this.session,
      required this.expenseId,
      this.api = const CehApiClient()});
  final CehSession session;
  final int expenseId;
  final CehApiClient api;
  @override
  State<AccountsExpenseRefundsScreen> createState() => _RefundsState();
}

class _RefundsState extends State<AccountsExpenseRefundsScreen> {
  Future<ExpenseRefundPage>? _future;
  final _search = TextEditingController();
  String _view = 'history', _query = '', _from = '', _to = '';
  int _page = 1;
  bool _busy = false;
  bool _confirming = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future == null && isUiAdmin(context, widget.session)) _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    _future = widget.api
        .generalExpenseRefunds(widget.session,
            expenseId: widget.expenseId,
            view: _view,
            page: _page,
            search: _query,
            dateFrom: _from,
            dateTo: _to)
        .then(ExpenseRefundPage.fromJson);
  }

  void _reload() => setState(_load);
  void _message(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _date(bool from) async {
    final chosen = await showDatePicker(
        context: context,
        initialDate: DateTime.tryParse(from ? _from : _to) ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100));
    if (!mounted || chosen == null) return;
    final value = chosen.toIso8601String().substring(0, 10);
    if ((from && _to.isNotEmpty && value.compareTo(_to) > 0) ||
        (!from && _from.isNotEmpty && value.compareTo(_from) < 0)) {
      _message('From date must not be after To date.');
      return;
    }
    setState(() {
      if (from) {
        _from = value;
      } else {
        _to = value;
      }
      _page = 1;
      _load();
    });
  }

  Future<void> _link(ExpenseRefundPage report, ExpenseRefundEntry row) async {
    if (_busy || _confirming) return;
    _confirming = true;
    try {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Link bank refund?'),
                content: Text(
                    '${formatNgn(row.amount)} • ${row.reference}\n${row.narration}\n\n'
                    'Link this bank credit to ${report.reference}? The bank entry remains unchanged. '
                    'No journal is created. There is no unlink action.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Confirm Link'))
                ],
              ));
      if (!mounted || confirmed != true) return;
      setState(() => _busy = true);
      await widget.api.linkGeneralExpenseRefund(widget.session,
          expenseId: widget.expenseId, statementRowId: row.statementRowId);
      if (!mounted) return;
      _message('Refund linked. No financial journal was created.');
      setState(() {
        _view = 'history';
        _page = 1;
        _query = '';
        _search.clear();
        _from = '';
        _to = '';
        _load();
      });
    } catch (error) {
      if (!mounted) return;
      final code = error is ApiException ? error.code : '';
      _message(switch (code) {
        'REFUND_ALREADY_LINKED' =>
          'This bank credit is already linked. The list has been refreshed.',
        'REFUND_EXCEEDS_EXPENSE' =>
          'This credit exceeds the remaining refundable amount. The list has been refreshed.',
        'ACTUAL_BANK_CREDIT_REQUIRED' =>
          'Only an incoming credit from the same bank can be linked.',
        'EXPENSE_NOT_REFUNDABLE' =>
          'This expense is no longer eligible for refund linkage.',
        _ =>
          'Could not confirm refund linkage. Refresh the history before trying again.',
      });
      _reload();
    } finally {
      _confirming = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _metric(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 8),
        Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w700)))
      ]));

  @override
  Widget build(BuildContext context) {
    if (!isUiAdmin(context, widget.session)) {
      return Scaffold(
          appBar: AppBar(
              title: const Text('Refunds'), actions: cehHomeAction(context)),
          body: const Center(child: Text('Administrator access required.')));
    }
    return Scaffold(
      appBar: AppBar(
          title: const Text('Expense Refunds'),
          actions: cehHomeAction(context)),
      body: AbsorbPointer(
          absorbing: _busy,
          child: Column(children: [
            if (_busy) const LinearProgressIndicator(),
            Expanded(
                child: FutureBuilder<ExpenseRefundPage>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              const Text(
                                  'Refund information could not be loaded.'),
                              OutlinedButton(
                                  onPressed: _reload,
                                  child: const Text('Try again'))
                            ]));
                      }
                      final report = snapshot.data!;
                      return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Text(report.reference,
                                style: Theme.of(context).textTheme.titleLarge),
                            Card(
                                child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(children: [
                                      _metric('Original expense',
                                          formatNgn(report.original)),
                                      _metric('Bank account', report.bank),
                                      _metric('Already linked',
                                          formatNgn(report.linked)),
                                      _metric('Remaining eligible',
                                          formatNgn(report.remaining)),
                                      _metric(
                                          'Refund status', report.statusLabel),
                                    ]))),
                            const Text(
                                'Bank refund linkage records evidence only. It does not post a journal or change the bank statement.'),
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, children: [
                              ChoiceChip(
                                  label: const Text('Refund history'),
                                  selected: _view == 'history',
                                  onSelected: (_) => setState(() {
                                        _view = 'history';
                                        _page = 1;
                                        _load();
                                      })),
                              ChoiceChip(
                                  label: const Text('Link Refund'),
                                  selected: _view == 'eligible',
                                  onSelected: report.canLink
                                      ? (_) => setState(() {
                                            _view = 'eligible';
                                            _page = 1;
                                            _load();
                                          })
                                      : null),
                              IconButton(
                                  tooltip: 'Refresh refunds',
                                  onPressed: _reload,
                                  icon: const Icon(Icons.refresh)),
                            ]),
                            if (_view == 'eligible')
                              const Text(
                                  'Only unlinked incoming credits from this bank, within the remaining amount, are listed. Eligibility is checked again when you confirm.'),
                            TextField(
                                controller: _search,
                                maxLength: 200,
                                decoration: InputDecoration(
                                    labelText:
                                        'Search narration / bank reference',
                                    suffixIcon: IconButton(
                                        tooltip: 'Search',
                                        icon: const Icon(Icons.search),
                                        onPressed: () => setState(() {
                                              _query = _search.text.trim();
                                              _page = 1;
                                              _load();
                                            }))),
                                onSubmitted: (v) => setState(() {
                                      _query = v.trim();
                                      _page = 1;
                                      _load();
                                    })),
                            Wrap(spacing: 8, children: [
                              OutlinedButton(
                                  onPressed: () => _date(true),
                                  child: Text(_from.isEmpty
                                      ? 'From date'
                                      : displayAccountsDate(_from))),
                              OutlinedButton(
                                  onPressed: () => _date(false),
                                  child: Text(_to.isEmpty
                                      ? 'To date'
                                      : displayAccountsDate(_to))),
                              TextButton(
                                  onPressed: () => setState(() {
                                        _from = '';
                                        _to = '';
                                        _query = '';
                                        _search.clear();
                                        _page = 1;
                                        _load();
                                      }),
                                  child: const Text('Clear filters'))
                            ]),
                            const SizedBox(height: 12),
                            if (report.rows.isEmpty)
                              Text(_view == 'history'
                                  ? 'No linked refunds match these filters.'
                                  : 'No eligible bank credits match these filters.'),
                            for (final row in report.rows)
                              Card(
                                  child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                '${formatNgn(row.amount)} • ${displayAccountsDate(row.date)}',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            Text(report.bank),
                                            Text(row.reference),
                                            Text(row.narration),
                                            Text(
                                                'Statement status: ${row.statementStatus.replaceAll('_', ' ')}'),
                                            if (row.linkedAt != null)
                                              Text(
                                                  'Linked • ${row.linkedBy ?? 'Admin'} • ${displayAccountsDate(row.linkedAt!)}'),
                                            if (_view == 'eligible' &&
                                                report.canLink)
                                              Align(
                                                  alignment:
                                                      Alignment.centerRight,
                                                  child: OutlinedButton(
                                                      onPressed: () =>
                                                          _link(report, row),
                                                      child: const Text(
                                                          'Link this credit'))),
                                          ]))),
                            Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                      tooltip: 'Previous page',
                                      onPressed: _page > 1
                                          ? () => setState(() {
                                                _page--;
                                                _load();
                                              })
                                          : null,
                                      icon: const Icon(Icons.chevron_left)),
                                  Flexible(
                                      child: Text(
                                          '${report.total} entries • Page ${report.totalPages == 0 ? 0 : report.page} of ${report.totalPages}')),
                                  IconButton(
                                      tooltip: 'Next page',
                                      onPressed: _page < report.totalPages
                                          ? () => setState(() {
                                                _page++;
                                                _load();
                                              })
                                          : null,
                                      icon: const Icon(Icons.chevron_right)),
                                ]),
                          ]);
                    })),
          ])),
    );
  }
}
