import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../models/accounts.dart';
import '../../models/client.dart';
import '../../models/session.dart';
import '../../widgets/accounts_widgets.dart';
import 'accounts_billing_settings_screen.dart';

class AccountsBillingScreen extends StatefulWidget {
  const AccountsBillingScreen(
      {super.key, required this.session, this.api = const CehApiClient()});
  final CehSession session;
  final CehApiClient api;
  @override
  State<AccountsBillingScreen> createState() => _AccountsBillingScreenState();
}

class _AccountsBillingScreenState extends State<AccountsBillingScreen> {
  late Future<List<BillingInvoice>> _invoices;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _invoices = widget.api.invoices(widget.session);
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Billing & Receivables'), actions: [
        IconButton(
            key: const ValueKey('billing-settings'),
            tooltip: 'Billing Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AccountsBillingSettingsScreen(
                        session: widget.session, api: widget.api))))
      ]),
      floatingActionButton: FloatingActionButton.extended(
          key: const ValueKey('new-invoice'),
          icon: const Icon(Icons.add),
          label: const Text('New Invoice'),
          onPressed: () async {
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => InvoiceEditorScreen(
                        session: widget.session, api: widget.api)));
            if (mounted) setState(_reload);
          }),
      body: RefreshIndicator(
          onRefresh: () async => setState(_reload),
          child: ListView(padding: const EdgeInsets.all(18), children: [
            Wrap(spacing: 10, runSpacing: 8, children: [
              OutlinedButton.icon(
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Customer Receipt'),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => CustomerReceiptScreen(
                              session: widget.session, api: widget.api)))),
              OutlinedButton.icon(
                  icon: const Icon(Icons.schedule_outlined),
                  label: const Text('Receivables Ageing'),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ReceivablesAgeingScreen(
                              session: widget.session, api: widget.api))))
            ]),
            const SizedBox(height: 16),
            const AccountsSectionTitle('Invoices',
                subtitle:
                    'Production billing, receivables and permanent CEH invoice references'),
            FutureBuilder<List<BillingInvoice>>(
                future: _invoices,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                        child: Padding(
                            padding: EdgeInsets.all(30),
                            child: CircularProgressIndicator()));
                  }
                  if (snapshot.hasError) {
                    return Center(
                        child:
                            Text('Unable to load invoices: ${snapshot.error}'));
                  }
                  final rows = snapshot.data ?? const [];
                  if (rows.isEmpty) {
                    return const Card(
                        child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('No invoices yet.')));
                  }
                  return Column(children: [
                    for (final i in rows)
                      Card(
                          child: ListTile(
                              title: Text('${i.reference} • ${i.client}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              subtitle: Text(
                                  '${i.status} • Outstanding ${formatNaira(i.outstanding)}'),
                              trailing: Text(formatNaira(i.total))))
                  ]);
                })
          ])));
}

class InvoiceEditorScreen extends StatefulWidget {
  const InvoiceEditorScreen(
      {super.key, required this.session, required this.api});
  final CehSession session;
  final CehApiClient api;
  @override
  State<InvoiceEditorScreen> createState() => _InvoiceEditorScreenState();
}

class _InvoiceEditorScreenState extends State<InvoiceEditorScreen> {
  List<CehClient> _clients = const [];
  List<FinancialAccount> _revenue = const [];
  List<BillableProductionReport> _reports = const [];
  CehClient? _client;
  BillableProductionReport? _report;
  final _quantity = TextEditingController();
  final _rate = TextEditingController();
  final _description = TextEditingController();
  String _vatMode = 'NONE';
  int? _vatTaxCodeId;
  List<Map<String, dynamic>> _vatCodes = const [];
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      widget.api.clients(widget.session),
      widget.api.financialAccounts(widget.session),
      widget.api.taxConfiguration(widget.session)
    ]);
    if (!mounted) return;
    setState(() {
      _clients = values[0] as List<CehClient>;
      _revenue = (values[1] as List<FinancialAccount>)
          .where((a) => a.accountType == 'INCOME' && a.isPostable && a.isActive)
          .toList();
      final config = values[2] as Map<String, dynamic>;
      _vatCodes = (config['tax_codes'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) =>
              e['tax_type'] == 'VAT' &&
              ('${e['is_active']}' == '1' || e['is_active'] == true))
          .toList();
    });
  }

  Future<void> _selectClient(CehClient? value) async {
    setState(() {
      _client = value;
      _report = null;
      _reports = const [];
    });
    if (value != null) {
      final rows =
          await widget.api.billableProductionReports(widget.session, value.id);
      if (mounted) setState(() => _reports = rows);
    }
  }

  double get _amount =>
      (double.tryParse(_quantity.text) ?? 0) *
      (double.tryParse(_rate.text) ?? 0);
  Future<void> _save(bool issue) async {
    if (_client == null || _revenue.isEmpty) return;
    if (_vatMode != 'NONE' && _vatTaxCodeId == null) {
      _message('Select an effective VAT code.');
      return;
    }
    final q = double.tryParse(_quantity.text) ?? 0;
    final rate = double.tryParse(_rate.text) ?? 0;
    if (_report != null && (q <= 0 || q > _report!.availableM3)) {
      _message(
          'Billing m³ must be positive and no more than available signed m³.');
      return;
    }
    if (q <= 0 || rate <= 0) {
      _message('Quantity and rate are required.');
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await widget.api.saveInvoice(widget.session, {
        'client_id': _client!.id,
        'invoice_date': DateTime.now().toIso8601String().substring(0, 10),
        'payment_term': 'ADVANCE_PAYMENT',
        'terms': 'Advance Payment',
        'vat_mode': _vatMode,
        'vat_tax_code_id': _vatTaxCodeId,
        'lines': [
          {
            'source_type': _report == null ? 'MANUAL' : 'PRODUCTION_REPORT',
            'description': _description.text.trim().isEmpty
                ? (_report == null
                    ? 'Service'
                    : '${_report!.reference} • ${_report!.project}')
                : _description.text.trim(),
            'quantity': q.toStringAsFixed(2),
            'unit_name': _report == null ? 'unit' : 'm³',
            'unit_price': rate.toStringAsFixed(2),
            'amount': _amount.toStringAsFixed(2),
            'taxable': true,
            'revenue_account_id': _revenue.first.id,
            'project_id': _report?.projectId,
            'production': _report == null
                ? null
                : {
                    'production_session_id': _report!.sessionId,
                    'billed_m3': q.toStringAsFixed(2),
                    'rate': rate.toStringAsFixed(2)
                  }
          }
        ]
      });
      if (issue) {
        await widget.api
            .issueInvoice(widget.session, (saved['id'] as num).toInt());
      }
      if (mounted) {
        _message(issue ? 'Invoice issued.' : 'Invoice draft saved.');
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      _message(e.code);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('New Invoice')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const AccountsSectionTitle(
            'Client → signed production → rate → invoice',
            subtitle:
                'Only signed, still-available CEH-PR quantities can be selected.'),
        DropdownButtonFormField<CehClient>(
            initialValue: _client,
            decoration: const InputDecoration(labelText: 'Client'),
            items: _clients
                .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                .toList(),
            onChanged: _selectClient),
        const SizedBox(height: 12),
        DropdownButtonFormField<BillableProductionReport>(
            initialValue: _report,
            decoration: const InputDecoration(
                labelText: 'Signed CEH Production Report (optional)'),
            items: _reports
                .map((r) => DropdownMenuItem(
                    value: r,
                    child: Text('${r.reference} • ${r.project} • ${r.mixer}')))
                .toList(),
            onChanged: (v) {
              setState(() => _report = v);
              if (v != null) _quantity.text = v.availableM3.toStringAsFixed(2);
            }),
        if (_report != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                  'Signed ${_report!.signedM3.toStringAsFixed(2)} m³  •  Previously billed ${_report!.billedM3.toStringAsFixed(2)} m³  •  Available ${_report!.availableM3.toStringAsFixed(2)} m³',
                  key: const ValueKey('production-availability'))),
        Row(children: [
          Expanded(
              child: TextField(
                  key: const ValueKey('invoice-quantity'),
                  controller: _quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'm³ / Quantity'),
                  onChanged: (_) => setState(() {}))),
          const SizedBox(width: 12),
          Expanded(
              child: TextField(
                  key: const ValueKey('invoice-rate'),
                  controller: _rate,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Rate'),
                  onChanged: (_) => setState(() {})))
        ]),
        const SizedBox(height: 12),
        TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Line description')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
            initialValue: _vatMode,
            decoration: const InputDecoration(labelText: 'VAT treatment'),
            items: const [
              DropdownMenuItem(value: 'NONE', child: Text('No VAT')),
              DropdownMenuItem(
                  value: 'VAT_EXCLUSIVE', child: Text('VAT Exclusive')),
              DropdownMenuItem(
                  value: 'VAT_INCLUSIVE', child: Text('VAT Inclusive'))
            ],
            onChanged: (v) => setState(() {
                  _vatMode = v!;
                  if (v == 'NONE') _vatTaxCodeId = null;
                })),
        if (_vatMode != 'NONE') ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
              initialValue: _vatTaxCodeId,
              decoration:
                  const InputDecoration(labelText: 'Effective VAT code'),
              items: _vatCodes
                  .map((c) => DropdownMenuItem(
                      value: (c['id'] as num).toInt(),
                      child: Text('${c['name']} • ${c['rate_percent']}%')))
                  .toList(),
              onChanged: (v) => setState(() => _vatTaxCodeId = v))
        ],
        const SizedBox(height: 12),
        Text('Invoice line total: ${formatNaira(_amount)}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(false),
                  child: const Text('Save Draft'))),
          const SizedBox(width: 12),
          Expanded(
              child: FilledButton(
                  onPressed: _saving ? null : () => _save(true),
                  child: const Text('Issue Invoice')))
        ])
      ]));
}

class CustomerReceiptScreen extends StatefulWidget {
  const CustomerReceiptScreen(
      {super.key, required this.session, required this.api});
  final CehSession session;
  final CehApiClient api;
  @override
  State<CustomerReceiptScreen> createState() => _CustomerReceiptScreenState();
}

class _CustomerReceiptScreenState extends State<CustomerReceiptScreen> {
  List<CehClient> clients = const [];
  List<CehBankAccount> banks = const [];
  CehClient? client;
  CehBankAccount? bank;
  String destination = 'CUSTOMER_ADVANCES';
  final amount = TextEditingController();
  final reference = TextEditingController();
  @override
  void initState() {
    super.initState();
    Future.wait([
      widget.api.clients(widget.session),
      widget.api.bankAccounts(widget.session)
    ]).then((v) {
      if (mounted) {
        setState(() {
          clients = v[0] as List<CehClient>;
          banks = v[1] as List<CehBankAccount>;
        });
      }
    });
  }

  Future<void> save() async {
    if (client == null || bank == null) return;
    try {
      await widget.api.saveCustomerReceipt(widget.session, {
        'client_id': client!.id,
        'bank_account_id': bank!.id,
        'receipt_date': DateTime.now().toIso8601String().substring(0, 10),
        'cash_amount': amount.text,
        'bank_reference': reference.text,
        'destination': destination
      });
      if (mounted) {
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Customer Receipt')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const Text(
            'A pre-invoice receipt is posted to Customer Advances. Trade Receivables receipts may be allocated after saving.'),
        const SizedBox(height: 12),
        DropdownButtonFormField<CehClient>(
            initialValue: client,
            decoration: const InputDecoration(labelText: 'Client'),
            items: clients
                .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
                .toList(),
            onChanged: (v) => setState(() => client = v)),
        const SizedBox(height: 12),
        DropdownButtonFormField<CehBankAccount>(
            initialValue: bank,
            decoration: const InputDecoration(labelText: 'Received into'),
            items: banks
                .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
                .toList(),
            onChanged: (v) => setState(() => bank = v)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
            initialValue: destination,
            decoration:
                const InputDecoration(labelText: 'Accounting destination'),
            items: const [
              DropdownMenuItem(
                  value: 'CUSTOMER_ADVANCES',
                  child: Text('Customer Advance / Deposit')),
              DropdownMenuItem(
                  value: 'TRADE_RECEIVABLES', child: Text('Trade Receivables'))
            ],
            onChanged: (v) => setState(() => destination = v!)),
        const SizedBox(height: 12),
        TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Cash received')),
        const SizedBox(height: 12),
        TextField(
            controller: reference,
            decoration: const InputDecoration(
                labelText: 'Zenith reference — optional')),
        const SizedBox(height: 20),
        FilledButton(onPressed: save, child: const Text('Save Receipt Draft'))
      ]));
}

class ReceivablesAgeingScreen extends StatelessWidget {
  const ReceivablesAgeingScreen(
      {super.key, required this.session, required this.api});
  final CehSession session;
  final CehApiClient api;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Receivables Ageing')),
      body: FutureBuilder<Map<String, dynamic>>(
          future: api.receivablesAgeing(session),
          builder: (context, s) {
            if (!s.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final buckets =
                Map<String, dynamic>.from(s.data!['buckets'] as Map);
            return ListView(padding: const EdgeInsets.all(18), children: [
              for (final entry in buckets.entries)
                Card(
                    child: ListTile(
                        title: Text(entry.key.replaceAll('_', '–')),
                        trailing: Text(formatNaira(
                            double.tryParse('${entry.value}') ?? 0))))
            ]);
          }));
}
