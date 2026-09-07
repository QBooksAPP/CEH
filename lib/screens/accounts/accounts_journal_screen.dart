import 'package:flutter/material.dart';

import '../../core/accounts_formatters.dart';
import '../../core/api_client.dart';
import '../../core/internal_navigation.dart';
import '../../core/view_mode.dart';
import '../../models/accounts.dart';
import '../../models/session.dart';
import 'accounts_billing_screen.dart';
import 'accounts_general_expense_screen.dart';
import 'accounts_live_screens.dart';

class AccountsJournalScreen extends StatelessWidget {
  const AccountsJournalScreen(
      {super.key, required this.session, this.api = const CehApiClient()});
  final CehSession session;
  final CehApiClient api;

  @override
  Widget build(BuildContext context) {
    if (!isUiAdmin(context, session)) {
      return const Scaffold(
          body: Center(child: Text('Administrator access required.')));
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Journals & Ledger',
              style: TextStyle(fontWeight: FontWeight.w900)),
          actions: cehHomeAction(context),
          bottom: const TabBar(tabs: [
            Tab(text: 'General Journal'),
            Tab(text: 'Account Ledger')
          ]),
        ),
        body: TabBarView(children: [
          GeneralJournalView(session: session, api: api),
          AccountLedgerView(session: session, api: api),
        ]),
      ),
    );
  }
}

class GeneralJournalView extends StatefulWidget {
  const GeneralJournalView(
      {super.key, required this.session, required this.api});
  final CehSession session;
  final CehApiClient api;
  @override
  State<GeneralJournalView> createState() => _GeneralJournalViewState();
}

class _GeneralJournalViewState extends State<GeneralJournalView> {
  int _page = 1;
  Map<String, String> _filters = {};
  late Future<AccountsPage<FinancialJournalSummary>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = widget.api
      .financialJournals(widget.session, page: _page, filters: _filters);
  void _reload() => setState(_load);

  Future<void> _filter() async {
    Map<String, dynamic> options;
    List<FinancialAccount> accounts;
    try {
      final values = await Future.wait([
        widget.api.financialJournalFilters(widget.session),
        widget.api.financialAccounts(widget.session),
      ]);
      options = values[0] as Map<String, dynamic>;
      accounts = values[1] as List<FinancialAccount>;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Filters unavailable: $error')));
      }
      return;
    }
    if (!mounted) return;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _JournalFilterDialog(
          initial: _filters, options: options, accounts: accounts),
    );
    if (result != null) {
      _filters = result;
      _page = 1;
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<AccountsPage<FinancialJournalSummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
                message: 'General Journal unavailable: ${snapshot.error}',
                retry: _reload);
          }
          final data = snapshot.data!;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(children: [
                Expanded(
                    child: Text('${data.total} journals',
                        style: Theme.of(context).textTheme.titleMedium)),
                OutlinedButton.icon(
                    key: const ValueKey('journal-filter'),
                    onPressed: _filter,
                    icon: const Icon(Icons.filter_list),
                    label: const Text('Filters')),
              ]),
            ),
            if (_filters.isNotEmpty) const Text('Filters applied'),
            Expanded(
              child: data.items.isEmpty
                  ? const Center(
                      child: Text('No journals match these filters.'))
                  : ListView.separated(
                      itemCount: data.items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final journal = data.items[index];
                        return ListTile(
                          key: ValueKey('journal-${journal.id}'),
                          title: Text(journal.reference,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(
                              '${displayAccountsDate(journal.date)} • ${formatAccountsStatus(journal.sourceType)}\n${journal.sourceReference ?? journal.description}\nPosted by ${journal.postedBy} • ${formatAccountsStatus(journal.status)}'),
                          isThreeLine: true,
                          trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(formatNgn(journal.totalDebit),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                Text('Dr = Cr',
                                    style: TextStyle(
                                        color: journal.balances
                                            ? Colors.black54
                                            : Theme.of(context)
                                                .colorScheme
                                                .error)),
                              ]),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => JournalDetailScreen(
                                      session: widget.session,
                                      api: widget.api,
                                      journalId: journal.id))),
                        );
                      },
                    ),
            ),
            _Pager(
              page: data.page,
              totalPages: data.totalPages,
              onPrevious: data.page > 1
                  ? () {
                      _page--;
                      _reload();
                    }
                  : null,
              onNext: data.hasNext
                  ? () {
                      _page++;
                      _reload();
                    }
                  : null,
            ),
          ]);
        },
      );
}

class JournalDetailScreen extends StatefulWidget {
  const JournalDetailScreen(
      {super.key,
      required this.session,
      required this.api,
      required this.journalId});
  final CehSession session;
  final CehApiClient api;
  final int journalId;
  @override
  State<JournalDetailScreen> createState() => _JournalDetailScreenState();
}

class _JournalDetailScreenState extends State<JournalDetailScreen> {
  late Future<FinancialJournalDetail> _future;
  @override
  void initState() {
    super.initState();
    _future = widget.api.financialJournal(widget.session, widget.journalId);
  }

  bool _canOpenSource(String source) => const {
        'INVOICE',
        'GENERAL_EXPENSE',
        'PETTY_CASH_EXPENSE',
      }.contains(source);

  Future<void> _openSource(FinancialJournalSummary journal) async {
    if (journal.sourceType == 'INVOICE') {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => InvoiceDetailsScreen(
                  invoiceId: journal.sourceRecordId,
                  session: widget.session,
                  api: widget.api)));
      return;
    }
    final rows = journal.sourceType == 'GENERAL_EXPENSE'
        ? await widget.api.generalExpenses(widget.session)
        : await widget.api.pettyCashExpenses(widget.session);
    final matches = rows.where((row) =>
        '${row['id'] ?? row['source_record_id']}' ==
        '${journal.sourceRecordId}');
    if (!mounted || matches.isEmpty) return;
    final screen = journal.sourceType == 'GENERAL_EXPENSE'
        ? AccountsGeneralExpenseScreen(
            session: widget.session, expense: matches.first)
        : AccountsPettyExpenseScreen(
            session: widget.session, expense: matches.first);
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Journal Detail'),
            actions: cehHomeAction(context)),
        body: FutureBuilder<FinancialJournalDetail>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(
                  message: 'Journal unavailable: ${snapshot.error}',
                  retry: () => setState(() => _future = widget.api
                      .financialJournal(widget.session, widget.journalId)));
            }
            final detail = snapshot.data!;
            final journal = detail.summary;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text(journal.reference,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                  '${displayAccountsDate(journal.date)} • ${formatAccountsStatus(journal.sourceType)} • ${formatAccountsStatus(journal.status)}'),
              Text(journal.description),
              if (journal.sourceReference?.isNotEmpty == true)
                Text('Source reference: ${journal.sourceReference}'),
              Text(
                  'Created by ${journal.createdBy} • Posted by ${journal.postedBy}'),
              if (_canOpenSource(journal.sourceType))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('journal-source-drilldown'),
                    onPressed: () => _openSource(journal),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(
                        'Open ${formatAccountsStatus(journal.sourceType)}'),
                  ),
                ),
              if (detail.originalJournalId != null ||
                  detail.reversalJournalId != null)
                Card(
                  child: ListTile(
                    title: Text(detail.originalJournalId != null
                        ? 'Reversal of ${detail.originalReference}'
                        : 'Reversed by ${detail.reversalReference}'),
                    trailing: const Icon(Icons.swap_horiz),
                    onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => JournalDetailScreen(
                                session: widget.session,
                                api: widget.api,
                                journalId: detail.originalJournalId ??
                                    detail.reversalJournalId!))),
                  ),
                ),
              const SizedBox(height: 12),
              const Text('Immutable journal lines',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              ...detail.lines.map((line) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${line.accountCode} — ${line.accountName}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            if (line.description.isNotEmpty)
                              Text(line.description),
                            Wrap(spacing: 12, children: [
                              if (line.client?.isNotEmpty == true)
                                Text('Client: ${line.client}'),
                              if (line.project?.isNotEmpty == true)
                                Text('Project: ${line.project}'),
                              if (line.equipment?.isNotEmpty == true)
                                Text('Equipment: ${line.equipment}'),
                              if (line.costCentre?.isNotEmpty == true)
                                Text('Cost centre: ${line.costCentre}'),
                              if (line.custodian?.isNotEmpty == true)
                                Text('Custodian: ${line.custodian}'),
                            ]),
                            Row(children: [
                              Expanded(
                                  child:
                                      Text('Debit ${formatNgn(line.debit)}')),
                              Expanded(
                                  child:
                                      Text('Credit ${formatNgn(line.credit)}')),
                            ]),
                          ]),
                    ),
                  )),
              const Divider(),
              Row(children: [
                Expanded(
                    child: Text('Total Debit\n${formatNgn(journal.totalDebit)}',
                        style: const TextStyle(fontWeight: FontWeight.w900))),
                Expanded(
                    child: Text(
                        'Total Credit\n${formatNgn(journal.totalCredit)}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w900))),
              ]),
              Center(
                  child: Chip(
                      avatar: Icon(journal.balances
                          ? Icons.check_circle
                          : Icons.error_outline),
                      label: Text(journal.balances
                          ? 'Journal balances'
                          : 'Journal does not balance'))),
            ]);
          },
        ),
      );
}

class AccountLedgerView extends StatefulWidget {
  const AccountLedgerView(
      {super.key, required this.session, required this.api});
  final CehSession session;
  final CehApiClient api;
  @override
  State<AccountLedgerView> createState() => _AccountLedgerViewState();
}

class _AccountLedgerViewState extends State<AccountLedgerView> {
  late Future<List<FinancialAccount>> _accounts;
  Future<AccountLedgerPage>? _ledger;
  int? _account;
  int _page = 1;
  String _from = '';
  String _to = '';
  Map<String, String> _dimensionFilters = {};
  @override
  void initState() {
    super.initState();
    _accounts = widget.api.financialAccounts(widget.session);
  }

  void _load() {
    if (_account == null) return;
    setState(() {
      _ledger = widget.api.accountLedger(
        widget.session,
        accountId: _account!,
        page: _page,
        filters: {
          if (_from.isNotEmpty) 'date_from': _from,
          if (_to.isNotEmpty) 'date_to': _to,
          ..._dimensionFilters,
        },
      );
    });
  }

  Future<void> _dates() async {
    Map<String, dynamic> options;
    try {
      options = await widget.api.financialJournalFilters(widget.session);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Filters unavailable: $error')));
      }
      return;
    }
    if (!mounted) return;
    final from = TextEditingController(text: _from);
    final to = TextEditingController(text: _to);
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _LedgerFilterDialog(
          initial: {'date_from': _from, 'date_to': _to, ..._dimensionFilters},
          options: options,
          from: from,
          to: to),
    );
    if (result != null) {
      _from = result.remove('date_from') ?? '';
      _to = result.remove('date_to') ?? '';
      _dimensionFilters = result;
      _page = 1;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        FutureBuilder<List<FinancialAccount>>(
          future: _accounts,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            if (snapshot.hasError) {
              return Text('Accounts unavailable: ${snapshot.error}');
            }
            final rows =
                snapshot.data!.where((account) => account.isPostable).toList();
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                    child: DropdownButtonFormField<int>(
                  key: const ValueKey('ledger-account'),
                  initialValue: _account,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: rows
                      .map((account) => DropdownMenuItem(
                          value: account.id,
                          child: Text('${account.code} — ${account.name}',
                              overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (value) {
                    _account = value;
                    _page = 1;
                    _load();
                  },
                )),
                const SizedBox(width: 8),
                IconButton(
                    tooltip: 'Date filters',
                    onPressed: _dates,
                    icon: const Icon(Icons.date_range)),
              ]),
            );
          },
        ),
        Expanded(
          child: _ledger == null
              ? const Center(
                  child: Text(
                      'Choose an account to view its authoritative ledger.'))
              : FutureBuilder<AccountLedgerPage>(
                  future: _ledger,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _ErrorState(
                          message:
                              'Account Ledger unavailable: ${snapshot.error}',
                          retry: _load);
                    }
                    final data = snapshot.data!;
                    return Column(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(children: [
                          Expanded(
                              child: Text('Opening balance',
                                  style:
                                      Theme.of(context).textTheme.titleMedium)),
                          Text(formatNgn(data.openingBalance),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900)),
                        ]),
                      ),
                      Expanded(
                        child: data.entries.isEmpty
                            ? const Center(
                                child:
                                    Text('No ledger entries match this range.'))
                            : ListView.separated(
                                itemCount: data.entries.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final entry = data.entries[index];
                                  return ListTile(
                                    key: ValueKey('ledger-entry-${entry.id}'),
                                    title: Text(entry.journalReference,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800)),
                                    subtitle: Text(
                                        '${displayAccountsDate(entry.date)} • ${formatAccountsStatus(entry.sourceType)}\n${entry.description}'),
                                    trailing: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(entry.debit > 0
                                              ? 'Dr ${formatNgn(entry.debit)}'
                                              : 'Cr ${formatNgn(entry.credit)}'),
                                          Text(formatNgn(entry.runningBalance),
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w800)),
                                        ]),
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => JournalDetailScreen(
                                                session: widget.session,
                                                api: widget.api,
                                                journalId: entry.journalId))),
                                  );
                                },
                              ),
                      ),
                      _Pager(
                        page: data.page,
                        totalPages: data.totalPages,
                        onPrevious: data.page > 1
                            ? () {
                                _page--;
                                _load();
                              }
                            : null,
                        onNext: data.hasNext
                            ? () {
                                _page++;
                                _load();
                              }
                            : null,
                      ),
                    ]);
                  },
                ),
        ),
      ]);
}

class _Pager extends StatelessWidget {
  const _Pager(
      {required this.page,
      required this.totalPages,
      this.onPrevious,
      this.onNext});
  final int page;
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
              tooltip: 'Previous page',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left)),
          Text('Page $page of ${totalPages == 0 ? 1 : totalPages}'),
          IconButton(
              tooltip: 'Next page',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right)),
        ]),
      );
}

class _JournalFilterDialog extends StatefulWidget {
  const _JournalFilterDialog(
      {required this.initial, required this.options, required this.accounts});
  final Map<String, String> initial;
  final Map<String, dynamic> options;
  final List<FinancialAccount> accounts;
  @override
  State<_JournalFilterDialog> createState() => _JournalFilterDialogState();
}

class _JournalFilterDialogState extends State<_JournalFilterDialog> {
  late final TextEditingController search, from, to;
  late Map<String, String> values;
  @override
  void initState() {
    super.initState();
    values = {...widget.initial};
    search = TextEditingController(text: values['search']);
    from = TextEditingController(text: values['date_from']);
    to = TextEditingController(text: values['date_to']);
  }

  List<Map<String, dynamic>> _rows(String key) =>
      (widget.options[key] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Widget _choice(String key, String label, List<Map<String, dynamic>> rows) =>
      DropdownButtonFormField<String>(
        initialValue: values[key],
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: '', child: Text('All')),
          ...rows.map((r) => DropdownMenuItem(
              value: '${r['id']}',
              child: Text('${r['name']}', overflow: TextOverflow.ellipsis)))
        ],
        onChanged: (v) => setState(() => values[key] = v ?? ''),
      );
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Filter General Journal'),
        content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: search,
                  decoration: const InputDecoration(
                      labelText: 'Reference or description')),
              TextField(
                  controller: from,
                  decoration: const InputDecoration(
                      labelText: 'From date (YYYY-MM-DD)')),
              TextField(
                  controller: to,
                  decoration:
                      const InputDecoration(labelText: 'To date (YYYY-MM-DD)')),
              DropdownButtonFormField<String>(
                  initialValue: values['source_type'],
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Journal/source type'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All')),
                    ...(widget.options['source_types'] as List? ?? const [])
                        .map((e) => DropdownMenuItem(
                            value: '$e',
                            child: Text(formatAccountsStatus('$e'))))
                  ],
                  onChanged: (v) =>
                      setState(() => values['source_type'] = v ?? '')),
              _choice(
                  'account_id',
                  'Account',
                  widget.accounts
                      .where((a) => a.isPostable)
                      .map((a) => {'id': a.id, 'name': '${a.code} — ${a.name}'})
                      .toList()),
              _choice('project_id', 'Project', _rows('projects')),
              _choice('mixer_id', 'Equipment', _rows('equipment')),
              _choice('user_id', 'Created/posted by', _rows('users')),
            ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, <String, String>{}),
              child: const Text('Clear')),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                values.addAll({
                  'search': search.text.trim(),
                  'date_from': from.text.trim(),
                  'date_to': to.text.trim()
                });
                values.removeWhere((_, v) => v.isEmpty);
                Navigator.pop(context, values);
              },
              child: const Text('Apply')),
        ],
      );
}

class _LedgerFilterDialog extends StatefulWidget {
  const _LedgerFilterDialog(
      {required this.initial,
      required this.options,
      required this.from,
      required this.to});
  final Map<String, String> initial;
  final Map<String, dynamic> options;
  final TextEditingController from, to;
  @override
  State<_LedgerFilterDialog> createState() => _LedgerFilterDialogState();
}

class _LedgerFilterDialogState extends State<_LedgerFilterDialog> {
  late Map<String, String> values;
  @override
  void initState() {
    super.initState();
    values = {...widget.initial};
  }

  List<Map<String, dynamic>> _rows(String key) =>
      (widget.options[key] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Widget _choice(String key, String label, String source) =>
      DropdownButtonFormField<String>(
          initialValue: values[key],
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            const DropdownMenuItem(value: '', child: Text('All')),
            ..._rows(source).map((r) => DropdownMenuItem(
                value: '${r['id']}',
                child: Text('${r['name']}', overflow: TextOverflow.ellipsis)))
          ],
          onChanged: (v) => setState(() => values[key] = v ?? ''));
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Ledger filters'),
          content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: widget.from,
                    decoration: const InputDecoration(
                        labelText: 'From date (YYYY-MM-DD)')),
                TextField(
                    controller: widget.to,
                    decoration: const InputDecoration(
                        labelText: 'To date (YYYY-MM-DD)')),
                _choice('project_id', 'Project', 'projects'),
                _choice('mixer_id', 'Equipment', 'equipment'),
                _choice('client_id', 'Client', 'clients'),
                _choice('cost_centre_id', 'Cost centre', 'cost_centres')
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, <String, String>{}),
                child: const Text('Clear')),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  values['date_from'] = widget.from.text.trim();
                  values['date_to'] = widget.to.text.trim();
                  values.removeWhere((_, v) => v.isEmpty);
                  Navigator.pop(context, values);
                },
                child: const Text('Apply'))
          ]);
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again')),
        ]),
      ));
}
