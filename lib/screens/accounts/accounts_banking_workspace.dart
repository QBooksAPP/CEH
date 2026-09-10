import 'package:flutter/material.dart';
import '../../core/accounts_formatters.dart';
import '../../core/api_client.dart';
import '../../core/bank_document_viewer.dart';
import '../../core/internal_navigation.dart';
import '../../core/view_mode.dart';
import '../../models/banking_workspace.dart';
import '../../models/session.dart';
import 'bank_statement_import_screen.dart';

class AccountsBankingWorkspace extends StatefulWidget {
  const AccountsBankingWorkspace(
      {super.key, required this.session, this.api = const CehApiClient()});
  final CehSession session;
  final CehApiClient api;
  @override
  State<AccountsBankingWorkspace> createState() => _BankingState();
}

class _BankingState extends State<AccountsBankingWorkspace> {
  List<Map<String, dynamic>> _banks = [];
  int? _bank;
  int _page = 1, _request = 0;
  bool _imports = false, _loading = false;
  String? _error;
  BankingPage? _data;
  Map<String, String> _filters = {};
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_request == 0 && isUiAdmin(context, widget.session)) {
      _request++;
      _loadBanks();
    }
  }

  Future<void> _loadBanks() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final b = await widget.api.bankingAccounts(widget.session);
      if (mounted) {
        setState(() {
          _banks = b;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load bank accounts.';
        });
      }
    }
  }

  Future<void> _load() async {
    if (_bank == null) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
    });
    try {
      final d = await widget.api.bankingPage(widget.session, _bank!,
          page: _page, imports: _imports, filters: _filters);
      if (mounted && request == _request) {
        setState(() {
          _data = d;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _error = 'Could not load Banking. Check filters and retry.';
        });
      }
    }
  }

  void _select(int? id) {
    setState(() {
      _bank = id;
      _page = 1;
      _filters = {};
    });
    _load();
  }

  String _money(Object? v) => formatCurrency(num.tryParse('$v') ?? 0,
      currencyCode: _banks
              .where((b) => bankInt(b['id']) == _bank)
              .map((b) => bankText(b['currency']))
              .firstOrNull ??
          'NGN');
  Future<void> _filter() async {
    final f = await showDialog<Map<String, String>>(
        context: context, builder: (_) => _BankFilters(initial: _filters));
    if (!mounted || f == null) return;
    setState(() {
      _filters = f;
      _page = 1;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!isUiAdmin(context, widget.session)) {
      return const Scaffold(
          body: Center(child: Text('Administrator access required.')));
    }
    final bank = _banks.where((b) => bankInt(b['id']) == _bank).firstOrNull;
    return Scaffold(
        appBar: AppBar(
            title: const Text('Banking'), actions: cehHomeAction(context)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          DropdownButtonFormField<int>(
              key: const Key('bank-selector'),
              initialValue: _bank,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Select bank account'),
              items: _banks
                  .map((b) => DropdownMenuItem(
                      value: bankInt(b['id']),
                      child: Text(bankAccountLabel(b),
                          overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: _select),
          if (bank != null)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${bank['bank_name']} • ${bank['currency']}'),
                          if (bank['masked_account_reference'] != null)
                            Text(bankText(bank['masked_account_reference'])),
                          _pair('CEH Ledger Balance',
                              _money(bank['current_balance'])),
                          _pair(
                              'Latest Bank Statement Balance',
                              bank['statement_balance'] == null
                                  ? 'Not available'
                                  : _money(bank['statement_balance'])),
                          Text(
                              'Statement date: ${bank['statement_date'] == null ? 'Not available' : displayAccountsDate(bankText(bank['statement_date']))}'),
                          const Text(
                              'Ledger and statement balances may differ.')
                        ]))),
          if (_bank != null) ...[
            OutlinedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Import Statement'),
                onPressed: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => BankStatementImportScreen(
                              session: widget.session,
                              bank: bank!,
                              api: widget.api)));
                  if (!mounted) return;
                  _page = 1;
                  await _loadBanks();
                  if (mounted) await _load();
                }),
            SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Transactions')),
                  ButtonSegment(value: true, label: Text('Imports'))
                ],
                selected: {
                  _imports
                },
                onSelectionChanged: (v) {
                  setState(() {
                    _imports = v.first;
                    _page = 1;
                  });
                  _load();
                }),
            if (!_imports)
              TextButton.icon(
                  onPressed: _filter,
                  icon: const Icon(Icons.filter_list),
                  label: Text(_filters.isEmpty ? 'Filters' : 'Filters applied'))
          ],
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator())),
          if (_error != null) ...[
            Text(_error!),
            TextButton(
                onPressed: _banks.isEmpty ? _loadBanks : _load,
                child: const Text('Retry'))
          ],
          if (!_loading && _error == null && _bank == null)
            Text(_banks.isEmpty
                ? 'No bank accounts available.'
                : 'Choose a bank account to view its statements.'),
          if (_data != null) ...[
            if (!_imports)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${_data!.total} transactions • all matching rows'),
                            _pair('${_data!.summary['debit_count']} debits',
                                _money(_data!.summary['debit_total'])),
                            _pair('${_data!.summary['credit_count']} credits',
                                _money(_data!.summary['credit_total']))
                          ]))),
            if (_data!.rows.isEmpty)
              Text(_imports
                  ? 'No statement imports.'
                  : 'No transactions match these filters.'),
            for (final r in _data!.rows)
              _imports ? _importCard(r) : _rowCard(r),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              TextButton(
                  onPressed: _page > 1
                      ? () {
                          _page--;
                          _load();
                        }
                      : null,
                  child: const Text('Previous')),
              Text('Page $_page'),
              TextButton(
                  onPressed: _data!.hasMore
                      ? () {
                          _page++;
                          _load();
                        }
                      : null,
                  child: const Text('Next'))
            ]),
          ]
        ]));
  }

  Widget _rowCard(Map<String, dynamic> r) {
    final a = num.tryParse('${r['amount']}') ?? 0;
    return Card(
        child: ListTile(
            title: Text(bankText(r['narration'])),
            subtitle: Text(
                '${displayAccountsDate(bankText(r['transaction_date']))} • ${bankUsageLabels[r['usage_state']] ?? 'Unavailable'}\n${bankText(r['bank_reference'])}'),
            trailing: Text('${a < 0 ? 'Debit' : 'Credit'}\n${_money(a.abs())}',
                textAlign: TextAlign.right),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => BankTransactionDetail(
                        session: widget.session, row: r, money: _money)))));
  }

  Widget _importCard(Map<String, dynamic> r) => Card(
      child: ListTile(
          title: Text(bankText(r['original_filename'])),
          subtitle: Text(
              'Import ${r['id']} • ${r['transaction_count']} transactions\n${displayAccountsDate(bankText(r['statement_from']))} – ${displayAccountsDate(bankText(r['statement_to']))}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => BankImportDetail(
                      session: widget.session,
                      row: {
                        ...r,
                        'masked_account_reference': _banks
                            .where((b) => bankInt(b['id']) == _bank)
                            .firstOrNull?['masked_account_reference']
                      },
                      money: _money)))));
}

Widget _pair(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.black54)),
      SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w600))
    ]));

class _BankFilters extends StatefulWidget {
  const _BankFilters({required this.initial});
  final Map<String, String> initial;
  @override
  State<_BankFilters> createState() => _FilterState();
}

class _FilterState extends State<_BankFilters> {
  late final values = Map<String, String>.from(widget.initial);
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Statement filters'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
                initialValue: values['direction'] ?? 'ALL',
                items: const [
                  DropdownMenuItem(value: 'ALL', child: Text('All directions')),
                  DropdownMenuItem(value: 'DEBIT', child: Text('Debit')),
                  DropdownMenuItem(value: 'CREDIT', child: Text('Credit'))
                ],
                onChanged: (v) => values['direction'] = v!),
            DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: values['usage'] ?? 'ALL',
                items: bankUsageLabels.entries
                    .map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => values['usage'] = v!),
            for (final key in ['date_from', 'date_to'])
              TextButton(
                  onPressed: () async {
                    final date = await showDatePicker(
                        context: context,
                        initialDate:
                            parseCanonicalAccountsDate(values[key] ?? '') ??
                                DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100));
                    if (date != null && mounted) {
                      setState(() => values[key] = canonicalAccountsDate(date));
                    }
                  },
                  child: Text(
                      '${key == 'date_from' ? 'From' : 'To'}: ${values[key]?.isNotEmpty == true ? displayAccountsDate(values[key]!) : 'Any date'}')),
            TextFormField(
                initialValue: values['amount'],
                decoration: const InputDecoration(
                    labelText: 'Exact amount (debit or credit)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) => values['amount'] = v.trim()),
            TextFormField(
                initialValue: values['search'],
                decoration:
                    const InputDecoration(labelText: 'Narration or reference'),
                onChanged: (v) => values['search'] = v.trim()),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, <String, String>{}),
                child: const Text('Clear')),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, values),
                child: const Text('Apply'))
          ]);
}

class BankTransactionDetail extends StatelessWidget {
  const BankTransactionDetail(
      {super.key,
      required this.session,
      required this.row,
      required this.money});
  final CehSession session;
  final Map<String, dynamic> row;
  final String Function(Object?) money;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Statement transaction'),
          actions: cehHomeAction(context)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _pair('Narration', bankText(row['narration'])),
        _pair('Transaction date',
            displayAccountsDate(bankText(row['transaction_date']))),
        if (row['value_date'] != null)
          _pair('Value date', displayAccountsDate(bankText(row['value_date']))),
        _pair('Bank reference', bankText(row['bank_reference'])),
        _pair((num.tryParse('${row['amount']}') ?? 0) < 0 ? 'Debit' : 'Credit',
            money((num.tryParse('${row['amount']}') ?? 0).abs())),
        _pair(
            'Statement balance after this transaction',
            row['statement_balance'] == null
                ? 'Not available'
                : money(row['statement_balance'])),
        const Text(
            'Balance supplied by the statement; not calculated from this page.'),
        _pair('Source',
            'Import ${row['import_batch_id']} • ${row['source_sheet'] ?? 'Legacy source'} • row ${row['source_row'] ?? 'not recorded'}'),
        _pair('Usage', bankUsageLabels[row['usage_state']] ?? 'Unavailable'),
        if (row['owner'] != null)
          OutlinedButton(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => BankSourceDetail(
                          session: session,
                          rowId: bankInt(row['id']),
                          bankId: bankInt(row['bank_account_id'])))),
              child: const Text('View linked record (read-only)')),
      ]));
}

class BankImportDetail extends StatelessWidget {
  const BankImportDetail(
      {super.key,
      required this.session,
      required this.row,
      required this.money});
  final CehSession session;
  final Map<String, dynamic> row;
  final String Function(Object?) money;
  @override
  Widget build(BuildContext context) {
    final r = row;
    return Scaffold(
        appBar: AppBar(
            title: Text('Statement import ${r['id']}'),
            actions: cehHomeAction(context)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          _pair('Original filename', bankText(r['original_filename'])),
          _pair(
              'Bank / account',
              bankAccountLabel({
                'name': r['account_name'] ?? r['bank_name'],
                'currency': r['currency'],
                'masked_account_reference': r['masked_account_reference'],
              })),
          _pair('Statement period',
              '${displayAccountsDate(bankText(r['statement_from']))} – ${displayAccountsDate(bankText(r['statement_to']))}'),
          _pair('Transactions', bankText(r['transaction_count'])),
          _pair('${r['debit_count']} debits', money(r['debit_total'])),
          _pair('${r['credit_count']} credits', money(r['credit_total'])),
          _pair(
              'Opening balance',
              r['opening_balance'] == null
                  ? 'Not recorded'
                  : money(r['opening_balance'])),
          _pair(
              'Closing balance',
              r['closing_balance'] == null
                  ? 'Not recorded'
                  : money(r['closing_balance'])),
          _pair('Imported by', bankText(r['imported_by_name'])),
          _pair('Uploaded by', bankText(r['uploaded_by_name'])),
          _pair('Imported timestamp',
              displayCehDateTime(bankText(r['imported_at']))),
          _pair('Source adapter', bankText(r['adapter'])),
          _pair('Original SHA-256', bankText(r['file_sha256'])),
          if (r['document_id'] != null)
            BankOriginalButton(session: session, row: r),
        ]));
  }
}

class BankOriginalButton extends StatefulWidget {
  const BankOriginalButton(
      {super.key, required this.session, required this.row});
  final CehSession session;
  final Map<String, dynamic> row;
  @override
  State<BankOriginalButton> createState() => _OriginalState();
}

class _OriginalState extends State<BankOriginalButton> {
  bool busy = false;
  String? error;
  Future<void> open() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final path = await cacheBankOriginal(
          const CehApiClient(), widget.session, widget.row);
      if (!mounted) return;
      setState(() => busy = false);
      await viewBankOriginal(path);
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'Unable to open statement. A compatible spreadsheet viewer is required.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        if (error != null) Text(error!),
        OutlinedButton.icon(
            onPressed: busy ? null : open,
            icon: const Icon(Icons.description_outlined),
            label: Text(
                busy ? 'Downloading securely…' : 'View Original Statement'))
      ]);
}

class BankSourceDetail extends StatefulWidget {
  const BankSourceDetail(
      {super.key,
      required this.session,
      required this.rowId,
      required this.bankId});
  final CehSession session;
  final int rowId, bankId;
  @override
  State<BankSourceDetail> createState() => _SourceState();
}

class _SourceState extends State<BankSourceDetail> {
  late Future<Map<String, dynamic>> result;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    result = const CehApiClient().bankingRead(
        widget.session, 'bank_statement_source.php', {
      'bank_account_id': '${widget.bankId}',
      'statement_row_id': '${widget.rowId}'
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Linked CEH record'),
          actions: cehHomeAction(context)),
      body: FutureBuilder<Map<String, dynamic>>(
          future: result,
          builder: (context, s) {
            if (s.hasError) {
              return Center(
                  child: TextButton(
                      onPressed: () => setState(load),
                      child: const Text('Could not load record. Retry')));
            }
            if (!s.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final r = bankMap(s.data!['record']);
            return ListView(padding: const EdgeInsets.all(16), children: [
              const Text('Read-only source record'),
              _pair('Relationship',
                  bankText(bankMap(s.data!['owner'])['relationship'])),
              _pair('Reference', bankText(r['reference'])),
              _pair('Date', displayAccountsDate(bankText(r['date']))),
              _pair('Description', bankText(r['description'])),
              _pair('Status', bankText(r['status'])),
              _pair('Amount',
                  formatCurrency(num.tryParse('${r['amount']}') ?? 0)),
              if (r['client'] != null) _pair('Client', bankText(r['client']))
            ]);
          }));
}
