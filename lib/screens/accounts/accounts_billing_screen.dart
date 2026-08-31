import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/accounts_formatters.dart';
import '../../core/api_client.dart';
import '../../core/internal_navigation.dart';
import '../../models/accounts.dart';
import '../../models/client.dart';
import '../../models/session.dart';
import '../../widgets/accounts_widgets.dart';
import 'accounts_billing_settings_screen.dart';
import 'accounts_estimates_screen.dart';

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
                        session: widget.session, api: widget.api)))),
        ...cehHomeAction(context),
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
                  label: const Text('Client Payments'),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ClientPaymentsScreen(
                              session: widget.session,
                              api: widget.api,
                              newPaymentBuilder: (_) => CustomerPaymentScreen(
                                  session: widget.session, api: widget.api))))),
              OutlinedButton.icon(
                  key: const ValueKey('apply-customer-credit'),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Apply Client Credit'),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ApplyCustomerCreditScreen(
                              session: widget.session, api: widget.api)))),
              OutlinedButton.icon(
                  key: const ValueKey('estimates'),
                  icon: const Icon(Icons.request_quote_outlined),
                  label: const Text('Estimates'),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => EstimatesScreen(
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
                              key: ValueKey('invoice-row-${i.id}'),
                              title: Text('${i.reference} • ${i.client}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              subtitle: Text(
                                  '${formatAccountsStatus(i.status)} • Outstanding ${formatNaira(i.outstanding)}'),
                              trailing: Text(formatNaira(i.total)),
                              onTap: () async {
                                await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => InvoiceDetailsScreen(
                                            invoiceId: i.id,
                                            session: widget.session,
                                            api: widget.api)));
                                if (mounted) setState(_reload);
                              }))
                  ]);
                })
          ])));
}

class InvoiceEditorScreen extends StatefulWidget {
  const InvoiceEditorScreen(
      {super.key, required this.session, required this.api, this.draft});
  final CehSession session;
  final CehApiClient api;
  final BillingInvoiceDetail? draft;
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
  int? _revenueAccountId;
  int? _invoiceId;
  late String _invoiceDate;
  String _paymentTerm = 'ADVANCE_PAYMENT';
  String _terms = 'Advance Payment';
  List<Map<String, dynamic>> _vatCodes = const [];
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _invoiceDate = DateTime.now().toIso8601String().substring(0, 10);
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
      final draft = widget.draft;
      if (draft != null && draft.lines.isNotEmpty) {
        final line = draft.lines.first;
        _invoiceId = draft.id;
        _invoiceDate = draft.invoiceDate;
        _paymentTerm = draft.paymentTerm;
        _terms = draft.terms;
        _client = _clients.where((c) => c.id == draft.clientId).firstOrNull;
        _quantity.text = line.quantity?.toString() ?? '';
        _rate.text = line.unitPrice?.toStringAsFixed(2) ?? '';
        _description.text = line.description;
        _revenueAccountId = line.revenueAccountId;
        _vatMode = draft.vatMode;
        _vatTaxCodeId = draft.vatTaxCodeId;
      }
    });
    if (_client != null) {
      final rows = await widget.api
          .billableProductionReports(widget.session, _client!.id);
      if (mounted) {
        setState(() {
          _reports = rows;
          final allocations =
              widget.draft?.lines.first.productionAllocations ?? const [];
          if (allocations.isNotEmpty) {
            final sessionId =
                int.tryParse('${allocations.first['production_session_id']}');
            _report = rows.where((r) => r.sessionId == sessionId).firstOrNull;
          }
        });
      }
    }
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
      (double.tryParse(_quantity.text) ?? 0) * (parseNgnInput(_rate.text) ?? 0);
  Future<void> _save() async {
    if (_client == null || _revenue.isEmpty) return;
    if (_vatMode != 'NONE' && _vatTaxCodeId == null) {
      _message('Select an effective VAT code.');
      return;
    }
    final q = double.tryParse(_quantity.text) ?? 0;
    final rate = parseNgnInput(_rate.text) ?? 0;
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
        if (_invoiceId != null) 'id': _invoiceId,
        'client_id': _client!.id,
        'invoice_date': _invoiceDate,
        'payment_term': _paymentTerm,
        'terms': _terms,
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
            'revenue_account_id': _revenueAccountId ?? _revenue.first.id,
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
      _invoiceId = (saved['id'] as num).toInt();
      if (mounted) {
        _message('Invoice draft saved.');
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
      appBar: AppBar(
          title: Text(widget.draft == null ? 'New Invoice' : 'Edit Draft'),
          actions: cehHomeAction(context,
              canLeave: () => confirmCehDiscardChanges(context))),
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
                  inputFormatters: const [NgnAmountInputFormatter()],
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
                      child: Text(
                          '${c['name']} • ${formatBillingTaxRate(c['rate_percent'])}')))
                  .toList(),
              onChanged: (v) => setState(() => _vatTaxCodeId = v))
        ],
        const SizedBox(height: 12),
        Text('Invoice line total: ${formatNaira(_amount)}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 20),
        FilledButton(
            onPressed: _saving ? null : _save, child: const Text('Save Draft'))
      ]));
}

class InvoiceDetailsScreen extends StatefulWidget {
  const InvoiceDetailsScreen(
      {super.key,
      required this.invoiceId,
      required this.session,
      required this.api});
  final int invoiceId;
  final CehSession session;
  final CehApiClient api;
  @override
  State<InvoiceDetailsScreen> createState() => _InvoiceDetailsScreenState();
}

class _InvoiceDetailsScreenState extends State<InvoiceDetailsScreen> {
  late Future<BillingInvoiceDetail> _detail;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() =>
      _detail = widget.api.invoiceDetails(widget.session, widget.invoiceId);
  String _vatMode(String value) => switch (value) {
        'VAT_EXCLUSIVE' => 'VAT Exclusive',
        'VAT_INCLUSIVE' => 'VAT Inclusive',
        _ => 'No VAT'
      };
  Future<void> _issue(BillingInvoiceDetail invoice) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Issue Invoice?'),
                content: Text(
                    'Final invoice total: ${formatNaira(invoice.total)}\n\nIssuing posts this invoice to Trade Receivables, Revenue and Output VAT where applicable. The posted accounting record cannot be edited silently.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      key: const ValueKey('confirm-issue-invoice'),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Issue Invoice'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.issueInvoice(widget.session, invoice.id);
      if (mounted) {
        setState(() {
          _reload();
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sharePdf(BillingInvoiceDetail invoice) async {
    setState(() => _busy = true);
    try {
      final pdf = await widget.api.invoicePdf(widget.session, invoice.id);
      final temp = await getTemporaryDirectory();
      final dir = Directory('${temp.path}/ceh-invoices');
      await dir.create(recursive: true);
      final safeFilename = RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(pdf.filename)
          ? pdf.filename
          : '${invoice.reference}.pdf';
      final file = File('${dir.path}/$safeFilename');
      await file.writeAsBytes(pdf.bytes, flush: true);
      await SharePlus.instance.share(ShareParams(
          title: invoice.reference,
          files: [XFile(file.path, mimeType: 'application/pdf')]));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('INVOICE_PDF_SHARE_FAILED')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _metric(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 145,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700))),
        Expanded(child: Text(value))
      ]));

  String _lineUnit(BillingInvoiceLine line) {
    final unit = (line.unitName ?? '').trim();
    if (unit == 'm³' || line.sourceType == 'PRODUCTION_REPORT') return 'm³';
    final description = line.description.toLowerCase();
    if ((unit.isEmpty || unit.toLowerCase() == 'unit') &&
        (description.contains('concrete') || description.contains('batch'))) {
      return 'm³';
    }
    return unit.isEmpty ? 'unit' : unit;
  }

  String _settlementType(String type) => switch (type) {
        'CUSTOMER_PAYMENT' => 'Client Payment',
        'CUSTOMER_CREDIT' => 'Client Credit Applied',
        'WHT' => 'WHT Allocated',
        'CREDIT_NOTE' => 'Credit Note',
        _ => formatAccountsStatus(type),
      };

  String _settlementDetails(InvoiceSettlementEvent event) {
    final details = <String>[];
    if ((event.reference ?? '').isNotEmpty) details.add(event.reference!);
    if ((event.bankDestination ?? '').isNotEmpty) {
      details.add('Received into ${event.bankDestination}');
    }
    if ((event.bankReference ?? '').isNotEmpty) {
      details.add('Bank ref ${event.bankReference}');
    }
    if ((event.taxCode ?? '').isNotEmpty) {
      details.add('${event.taxCode} ${formatBillingTaxRate(event.taxRate)}');
    }
    if ((event.calculationBase ?? '').isNotEmpty) {
      final amount = event.calculationBaseAmount;
      details.add(amount == null
          ? '${formatAccountsStatus(event.calculationBase!)} base'
          : '${formatAccountsStatus(event.calculationBase!)} base ${formatNaira(amount)}');
    }
    if ((event.certificateStatus ?? '').isNotEmpty) {
      details.add(formatAccountsStatus(event.certificateStatus!));
    }
    return details.join(' • ');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Invoice Details'),
          actions: cehHomeAction(context)),
      body: FutureBuilder<BillingInvoiceDetail>(
          future: _detail,
          builder: (context, s) {
            if (s.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (s.hasError) {
              return Center(child: Text('Unable to load invoice: ${s.error}'));
            }
            final i = s.data!;
            final draft = i.status == 'DRAFT';
            return ListView(padding: const EdgeInsets.all(18), children: [
              Text(i.reference,
                  key: const ValueKey('invoice-detail-reference'),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        _metric('Status',
                            draft ? 'Draft' : formatAccountsStatus(i.status)),
                        _metric('Client', i.client),
                        _metric(
                            'Invoice date', displayAccountsDate(i.invoiceDate)),
                        _metric('Terms', i.terms.replaceAll('_', ' ')),
                        _metric('VAT treatment', _vatMode(i.vatMode)),
                        _metric(
                            'VAT rate',
                            i.vatMode == 'NONE'
                                ? 'Not applicable'
                                : formatBillingTaxRate(i.vatRate)),
                        _metric('Net', formatNaira(i.net)),
                        _metric('VAT', formatNaira(i.vat)),
                        _metric('Total', formatNaira(i.total)),
                        if (i.originEstimateReference != null)
                          _metric('Originating Estimate',
                              i.originEstimateReference!)
                      ]))),
              const AccountsSectionTitle('Invoice lines'),
              for (final line in i.lines)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(line.description,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              if (line.quantity != null &&
                                  line.unitPrice != null)
                                Text(
                                    '${line.quantity!.toStringAsFixed(2)} ${_lineUnit(line)} × ${formatNaira(line.unitPrice!)} = ${formatNaira(line.enteredAmount)}')
                              else
                                Text(formatNaira(line.enteredAmount)),
                              if ((line.project ?? '').isNotEmpty)
                                Text('Project: ${line.project}'),
                              if ((line.equipment ?? '').isNotEmpty)
                                Text('Equipment: ${line.equipment}'),
                              for (final p in line.productionAllocations)
                                Text(
                                    'Production Report: ${p['report_reference_snapshot']} • ${p['billed_m3']} m³')
                            ]))),
              if (!draft) ...[
                const AccountsSectionTitle('Settlement summary'),
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          _metric(
                              'Issued',
                              i.issuedAt == null
                                  ? '—'
                                  : displayAccountsTimestampDate(i.issuedAt!)),
                          _metric('Invoice Total', formatNaira(i.total)),
                          _metric('Cash Payments', formatNaira(i.amountPaid)),
                          _metric('Client Credit Applied',
                              formatNaira(i.customerCreditApplied)),
                          _metric('WHT Allocated', formatNaira(i.whtAllocated)),
                          _metric(
                              'Credit Notes', formatNaira(i.creditNotesTotal)),
                          _metric('Outstanding', formatNaira(i.outstanding)),
                          _metric(
                              'Journal / posting',
                              i.journalId == null
                                  ? 'Not posted'
                                  : 'Journal #${i.journalId} • ${formatAccountsStatus(i.postingStatus ?? 'POSTED')}')
                        ]))),
                const AccountsSectionTitle('Payment / Allocation History'),
                if (i.settlementHistory.isEmpty)
                  const Card(
                      child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No settlement activity yet.')))
                else
                  for (final event in i.settlementHistory)
                    Card(
                        child: ListTile(
                            key: ValueKey(
                                'settlement-${event.type}-${event.date}-${event.amount}'),
                            title: Text(
                                '${displayAccountsDate(event.date)} • ${_settlementType(event.type)} • ${formatNaira(event.amount)}'),
                            subtitle: _settlementDetails(event).isEmpty
                                ? null
                                : Text(_settlementDetails(event)),
                            trailing: event.receiptId == null ||
                                    !['CUSTOMER_PAYMENT', 'WHT']
                                        .contains(event.type)
                                ? null
                                : IconButton(
                                    tooltip: 'View / Share Receipt PDF',
                                    icon:
                                        const Icon(Icons.receipt_long_outlined),
                                    onPressed: () => shareClientPaymentPdf(
                                        context,
                                        widget.api,
                                        widget.session,
                                        event.receiptId!,
                                        event.reference ?? 'Client Payment'))))
              ],
              if (draft)
                Row(children: [
                  Expanded(
                      child: OutlinedButton(
                          key: const ValueKey('edit-invoice-draft'),
                          onPressed: _busy
                              ? null
                              : () async {
                                  await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => InvoiceEditorScreen(
                                              session: widget.session,
                                              api: widget.api,
                                              draft: i)));
                                  if (mounted) {
                                    setState(() {
                                      _reload();
                                    });
                                  }
                                },
                          child: const Text('Edit Draft'))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: FilledButton(
                          key: const ValueKey('issue-invoice-from-detail'),
                          onPressed: _busy ? null : () => _issue(i),
                          child: const Text('Issue Invoice')))
                ])
              else
                FilledButton.icon(
                    onPressed: _busy ? null : () => _sharePdf(i),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('View / Share Invoice PDF'))
            ]);
          }));
}

class CustomerPaymentScreen extends StatefulWidget {
  const CustomerPaymentScreen(
      {super.key, required this.session, required this.api});
  final CehSession session;
  final CehApiClient api;
  @override
  State<CustomerPaymentScreen> createState() => _CustomerPaymentScreenState();
}

class _PaymentWhtDraft {
  bool enabled = false;
  int? taxCodeId;
  String certificateStatus = 'CERTIFICATE_PENDING';
  final base = TextEditingController();
  final accepted = TextEditingController();
  final overrideReason = TextEditingController();
  bool acceptedEdited = false;
  XFile? certificate;

  void dispose() {
    base.dispose();
    accepted.dispose();
    overrideReason.dispose();
  }
}

class _CustomerPaymentScreenState extends State<CustomerPaymentScreen> {
  List<CehClient> clients = const [];
  List<CehBankAccount> banks = const [];
  List<BillingInvoice> invoices = const [];
  List<Map<String, dynamic>> whtCodes = const [];
  CehClient? client;
  CehBankAccount? bank;
  final amount = TextEditingController();
  final reference = TextEditingController();
  final Map<int, TextEditingController> allocations = {};
  final Map<int, _PaymentWhtDraft> wht = {};
  final Set<int> selectedInvoiceIds = {};
  final ImagePicker _picker = ImagePicker();
  bool loadingInvoices = false;
  bool posting = false;
  @override
  void initState() {
    super.initState();
    Future.wait([
      widget.api.clients(widget.session),
      widget.api.bankAccounts(widget.session),
    ]).then((v) {
      if (mounted) {
        setState(() {
          clients = v[0] as List<CehClient>;
          banks = v[1] as List<CehBankAccount>;
        });
      }
    });
    widget.api.taxConfiguration(widget.session).then((tax) {
      if (!mounted) return;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      setState(() {
        whtCodes = (tax['tax_codes'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .where((code) {
          final active = code['is_active'] == true ||
              code['is_active'] == 1 ||
              '${code['is_active']}' == '1';
          final from = '${code['effective_from'] ?? ''}';
          final to = code['effective_to']?.toString();
          return active &&
              code['tax_type'] == 'WHT' &&
              from.compareTo(today) <= 0 &&
              (to == null || to.isEmpty || to.compareTo(today) >= 0);
        }).toList();
      });
    }).onError((_, __) {
      // Tax lookup failure must not block an ordinary cash-only payment.
    });
  }

  @override
  void dispose() {
    amount.dispose();
    reference.dispose();
    for (final controller in allocations.values) {
      controller.dispose();
    }
    for (final draft in wht.values) {
      draft.dispose();
    }
    super.dispose();
  }

  int _minor(String value) => parseNgnMinorUnits(value) ?? 0;
  int get receivedMinor => _minor(amount.text);
  int get allocatedMinor => allocations.values
      .fold(0, (total, controller) => total + _minor(controller.text));
  int _outstandingMinor(BillingInvoice invoice) =>
      (invoice.outstanding * 100).round();
  int _cashCapacityMinor(BillingInvoice invoice) =>
      (_outstandingMinor(invoice) - _whtMinor(invoice.id)).clamp(0, 1 << 62);

  void _setCashAllocation(BillingInvoice invoice, int minor) {
    allocations[invoice.id]!.text =
        minor > 0 ? completeNgnInput(ngnMinorUnitsForApi(minor)) : '';
  }

  void _rebalanceSingleInvoice() {
    if (selectedInvoiceIds.length != 1) return;
    final invoice =
        invoices.firstWhere((row) => row.id == selectedInvoiceIds.single);
    _setCashAllocation(
        invoice, receivedMinor.clamp(0, _cashCapacityMinor(invoice)));
  }

  void _toggleInvoice(BillingInvoice invoice, bool selected) {
    if (selected) {
      selectedInvoiceIds.add(invoice.id);
      if (selectedInvoiceIds.length == 1) {
        _rebalanceSingleInvoice();
      } else {
        final usedElsewhere = allocations.entries
            .where((entry) => entry.key != invoice.id)
            .fold(0, (total, entry) => total + _minor(entry.value.text));
        final remaining = (receivedMinor - usedElsewhere).clamp(0, 1 << 62);
        _setCashAllocation(
            invoice, remaining.clamp(0, _cashCapacityMinor(invoice)));
      }
    } else {
      selectedInvoiceIds.remove(invoice.id);
      _setCashAllocation(invoice, 0);
      final draft = wht[invoice.id]!;
      draft.enabled = false;
      draft.taxCodeId = null;
      draft.base.clear();
      draft.accepted.clear();
      draft.overrideReason.clear();
      draft.acceptedEdited = false;
      draft.certificateStatus = 'CERTIFICATE_PENDING';
      draft.certificate = null;
      _rebalanceSingleInvoice();
    }
  }

  Map<String, dynamic>? _whtCode(int? taxCodeId) {
    if (taxCodeId == null) return null;
    for (final item in whtCodes) {
      if ((item['id'] as num).toInt() == taxCodeId) return item;
    }
    return null;
  }

  int _suggestedWhtMinor(int invoiceId) {
    final draft = wht[invoiceId];
    if (draft == null || !draft.enabled || draft.taxCodeId == null) return 0;
    final code = _whtCode(draft.taxCodeId);
    if (code == null) return 0;
    try {
      return calculateTaxMinorUnits(
          _minor(draft.base.text), code['rate_percent']);
    } on FormatException {
      return 0;
    }
  }

  int _whtMinor(int invoiceId) {
    final draft = wht[invoiceId];
    if (draft == null || !draft.enabled) return 0;
    return _minor(draft.accepted.text);
  }

  int? _automaticBaseMinor(BillingInvoice invoice, Map<String, dynamic> code) {
    if (invoice.creditNotesTotal > 0) return null;
    return switch ('${code['calculation_base']}') {
      'NET' => (invoice.net * 100).round(),
      'GROSS' => (invoice.total * 100).round(),
      _ => null,
    };
  }

  bool _requiresManualBase(BillingInvoice invoice, Map<String, dynamic> code) =>
      _automaticBaseMinor(invoice, code) == null;

  void _selectWhtCode(BillingInvoice invoice, int? value) {
    final draft = wht[invoice.id]!;
    draft.taxCodeId = value;
    draft.acceptedEdited = false;
    draft.overrideReason.clear();
    final code = _whtCode(value);
    final baseMinor = code == null ? null : _automaticBaseMinor(invoice, code);
    if (baseMinor == null || baseMinor <= 0) {
      draft.base.clear();
      draft.accepted.clear();
      return;
    }
    draft.base.text = completeNgnInput(ngnMinorUnitsForApi(baseMinor));
    final suggested = calculateTaxMinorUnits(baseMinor, code!['rate_percent']);
    draft.accepted.text = completeNgnInput(ngnMinorUnitsForApi(suggested));
    _rebalanceSingleInvoice();
  }

  void _baseChanged(BillingInvoice invoice) {
    final draft = wht[invoice.id]!;
    if (!draft.acceptedEdited) {
      final suggested = _suggestedWhtMinor(invoice.id);
      draft.accepted.text =
          suggested > 0 ? completeNgnInput(ngnMinorUnitsForApi(suggested)) : '';
    }
    _rebalanceSingleInvoice();
    setState(() {});
  }

  int get whtAllocatedMinor =>
      invoices.fold(0, (total, invoice) => total + _whtMinor(invoice.id));
  int get unallocatedMinor =>
      receivedMinor > allocatedMinor ? receivedMinor - allocatedMinor : 0;

  Future<void> _selectClient(CehClient? value) async {
    for (final controller in allocations.values) {
      controller.dispose();
    }
    for (final draft in wht.values) {
      draft.dispose();
    }
    setState(() {
      client = value;
      invoices = const [];
      allocations.clear();
      wht.clear();
      selectedInvoiceIds.clear();
      loadingInvoices = value != null;
    });
    if (value == null) return;
    try {
      final rows =
          await widget.api.outstandingInvoices(widget.session, value.id);
      if (!mounted || client?.id != value.id) return;
      setState(() {
        invoices = rows;
        for (final invoice in rows) {
          allocations[invoice.id] = TextEditingController();
          wht[invoice.id] = _PaymentWhtDraft();
        }
        loadingInvoices = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => loadingInvoices = false);
      _message(e.code);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(value)));

  Future<void> saveAndPost() async {
    if (client == null || bank == null || receivedMinor <= 0) {
      _message('Select a Client, Received Into account and Amount Received.');
      return;
    }
    if (allocatedMinor > receivedMinor) {
      _message('Allocated amount cannot exceed Amount Received.');
      return;
    }
    for (final invoice in invoices) {
      final cashValue = _minor(allocations[invoice.id]?.text ?? '');
      final draft = wht[invoice.id]!;
      final whtValue = _whtMinor(invoice.id);
      if (draft.enabled) {
        final suggestedWht = _suggestedWhtMinor(invoice.id);
        if (draft.taxCodeId == null ||
            _minor(draft.base.text) <= 0 ||
            suggestedWht <= 0 ||
            whtValue <= 0) {
          _message(
              '${invoice.reference}: select a WHT Code and enter the calculation base.');
          return;
        }
        final reason = draft.overrideReason.text.trim();
        if (whtValue != suggestedWht && reason.isEmpty) {
          _message(
              '${invoice.reference}: enter a reason for the WHT override.');
          return;
        }
        if (whtValue == suggestedWht && reason.isNotEmpty) {
          _message(
              '${invoice.reference}: remove the override reason because accepted WHT equals suggested WHT.');
          return;
        }
        if (draft.certificateStatus == 'CERTIFICATE_RECEIVED' &&
            draft.certificate == null) {
          _message(
              '${invoice.reference}: attach the received WHT certificate.');
          return;
        }
      }
      if (cashValue + whtValue > (invoice.outstanding * 100).round()) {
        _message(
            '${invoice.reference} settlement exceeds its outstanding balance.');
        return;
      }
    }
    setState(() => posting = true);
    try {
      final draft = await widget.api.saveCustomerReceipt(widget.session, {
        'client_id': client!.id,
        'bank_account_id': bank!.id,
        'receipt_date': DateTime.now().toIso8601String().substring(0, 10),
        'cash_amount': ngnMinorUnitsForApi(receivedMinor),
        'bank_reference': reference.text,
      });
      final whtEvidenceIds = <int, int>{};
      for (final invoice in invoices) {
        final certificate = wht[invoice.id]?.certificate;
        if (certificate != null) {
          whtEvidenceIds[invoice.id] = await widget.api
              .uploadFinancialEvidenceRecord(widget.session,
                  sourceType: 'WHT_CERTIFICATE',
                  sourceRecordId: (draft['id'] as num).toInt(),
                  filename: certificate.name,
                  mimeType: certificate.name.toLowerCase().endsWith('.png')
                      ? 'image/png'
                      : 'image/jpeg',
                  bytes: await certificate.readAsBytes());
        }
      }
      await widget.api.postCustomerPayment(widget.session, {
        'receipt_id': draft['id'],
        'allocations': [
          for (final invoice in invoices)
            if (_minor(allocations[invoice.id]?.text ?? '') > 0 ||
                _whtMinor(invoice.id) > 0)
              {
                'invoice_id': invoice.id,
                'cash_amount':
                    ngnMinorUnitsForApi(_minor(allocations[invoice.id]!.text)),
                if (_whtMinor(invoice.id) > 0) ...{
                  'wht_amount': ngnMinorUnitsForApi(_whtMinor(invoice.id)),
                  'wht_tax_code_id': wht[invoice.id]!.taxCodeId,
                  'wht_calculation_base_amount':
                      ngnMinorUnitsForApi(_minor(wht[invoice.id]!.base.text)),
                  'wht_suggested_amount':
                      ngnMinorUnitsForApi(_suggestedWhtMinor(invoice.id)),
                  if (_whtMinor(invoice.id) != _suggestedWhtMinor(invoice.id))
                    'wht_override_reason':
                        wht[invoice.id]!.overrideReason.text.trim(),
                  'certificate_status': wht[invoice.id]!.certificateStatus,
                  if (whtEvidenceIds[invoice.id] != null)
                    'wht_certificate_evidence_id': whtEvidenceIds[invoice.id],
                }
              }
        ],
      });
      if (mounted) {
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code)));
      }
    } finally {
      if (mounted) setState(() => posting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('New Client Payment'),
          actions: cehHomeAction(context,
              canLeave: () => confirmCehDiscardChanges(context))),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const Text(
            'Allocate this payment to outstanding invoices. Any remainder is retained automatically as Client Credit / Advance.'),
        const SizedBox(height: 12),
        DropdownButtonFormField<CehClient>(
            initialValue: client,
            decoration: const InputDecoration(labelText: 'Client'),
            items: clients
                .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
                .toList(),
            onChanged: posting ? null : _selectClient),
        const SizedBox(height: 12),
        const Text('Outstanding Invoice(s)',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (loadingInvoices)
          const Center(child: CircularProgressIndicator())
        else if (client != null && invoices.isEmpty)
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(16),
                  child:
                      Text('No outstanding issued invoices for this Client.')))
        else
          for (final invoice in invoices)
            Card(
                key: ValueKey('payment-invoice-${invoice.id}'),
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${invoice.reference} • ${invoice.projectNames.isEmpty ? 'General / No project' : invoice.projectNames}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                              'Invoice ${formatNaira(invoice.total)} • Outstanding ${formatNaira(invoice.outstanding)}'),
                          const SizedBox(height: 10),
                          CheckboxListTile(
                              key: ValueKey(
                                  'payment-select-invoice-${invoice.id}'),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text('Allocate payment'),
                              subtitle: Text(receivedMinor <= 0
                                  ? 'Enter Amount Received; CEH will allocate it automatically.'
                                  : 'Use this invoice for the payment settlement.'),
                              value: selectedInvoiceIds.contains(invoice.id),
                              onChanged: posting
                                  ? null
                                  : (value) => setState(() =>
                                      _toggleInvoice(invoice, value ?? false))),
                          if (selectedInvoiceIds.contains(invoice.id)) ...[
                            if (selectedInvoiceIds.length == 1)
                              Card(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: _paymentMetric(
                                          'Cash allocated automatically',
                                          _minor(allocations[invoice.id]
                                                      ?.text ??
                                                  '') /
                                              100)))
                            else
                              TextField(
                                  key: ValueKey(
                                      'payment-allocation-${invoice.id}'),
                                  controller: allocations[invoice.id],
                                  enabled: !posting && receivedMinor > 0,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: const [
                                    NgnAmountInputFormatter()
                                  ],
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                      labelText: 'Cash allocated',
                                      helperText: receivedMinor <= 0
                                          ? 'Enter Amount Received first'
                                          : 'Adjust how the received cash is shared across invoices.')),
                            SwitchListTile.adaptive(
                                key: ValueKey('payment-wht-${invoice.id}'),
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Client deducted WHT'),
                                subtitle: const Text(
                                    'Enable only when the Client explicitly deducted WHT.'),
                                value: wht[invoice.id]?.enabled ?? false,
                                onChanged: posting
                                    ? null
                                    : (value) => setState(() {
                                          final draft = wht[invoice.id]!;
                                          draft.enabled = value;
                                          if (!value) {
                                            draft.taxCodeId = null;
                                            draft.base.clear();
                                            draft.accepted.clear();
                                            draft.overrideReason.clear();
                                            draft.acceptedEdited = false;
                                            draft.certificateStatus =
                                                'CERTIFICATE_PENDING';
                                            draft.certificate = null;
                                          }
                                          _rebalanceSingleInvoice();
                                        })),
                            if (wht[invoice.id]?.enabled ?? false) ...[
                              if (whtCodes.isEmpty)
                                const Text(
                                    'No active WHT codes are effective for today.'),
                              DropdownButtonFormField<int>(
                                  key: ValueKey(
                                      'payment-wht-code-${invoice.id}'),
                                  initialValue: wht[invoice.id]!.taxCodeId,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                      labelText: 'WHT Code / Type'),
                                  items: whtCodes
                                      .map((code) => DropdownMenuItem<int>(
                                          value: (code['id'] as num).toInt(),
                                          child: Text(
                                              '${code['name']} • ${formatBillingTaxRate(code['rate_percent'])}')))
                                      .toList(),
                                  onChanged: posting
                                      ? null
                                      : (value) => setState(() =>
                                          _selectWhtCode(invoice, value))),
                              const SizedBox(height: 10),
                              if (wht[invoice.id]!.taxCodeId != null)
                                Builder(builder: (context) {
                                  final code = whtCodes.firstWhere((item) =>
                                      (item['id'] as num).toInt() ==
                                      wht[invoice.id]!.taxCodeId);
                                  final manual =
                                      _requiresManualBase(invoice, code);
                                  final suggested =
                                      _suggestedWhtMinor(invoice.id);
                                  return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            'Configured rate: ${formatBillingTaxRate(code['rate_percent'])} • Calculation base: ${formatAccountsStatus('${code['calculation_base']}')}'),
                                        if (manual)
                                          const Text(
                                              'Enter the supported WHT base manually; CEH will not guess from cash or outstanding.'),
                                        if (suggested > 0)
                                          Text(
                                              '${formatBillingTaxRate(code['rate_percent'])} × ${formatNaira(_minor(wht[invoice.id]!.base.text) / 100)} = ${formatNaira(suggested / 100)}',
                                              key: ValueKey(
                                                  'payment-wht-calculation-${invoice.id}')),
                                      ]);
                                }),
                              const SizedBox(height: 8),
                              TextField(
                                  key: ValueKey(
                                      'payment-wht-base-${invoice.id}'),
                                  controller: wht[invoice.id]!.base,
                                  enabled: !posting &&
                                      (wht[invoice.id]!.taxCodeId == null ||
                                          _requiresManualBase(
                                              invoice,
                                              _whtCode(wht[invoice.id]!
                                                  .taxCodeId)!)),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: const [
                                    NgnAmountInputFormatter()
                                  ],
                                  onChanged: (_) => _baseChanged(invoice),
                                  decoration: InputDecoration(
                                      labelText: 'WHT calculation base amount',
                                      helperText: wht[invoice.id]!.taxCodeId !=
                                                  null &&
                                              !_requiresManualBase(
                                                  invoice,
                                                  _whtCode(wht[invoice.id]!
                                                      .taxCodeId)!)
                                          ? 'Suggested automatically from the immutable issued invoice.'
                                          : 'Required manually because a safe whole-invoice base cannot be proven.')),
                              const SizedBox(height: 8),
                              TextField(
                                  key: ValueKey(
                                      'payment-wht-accepted-${invoice.id}'),
                                  controller: wht[invoice.id]!.accepted,
                                  enabled: !posting,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: const [
                                    NgnAmountInputFormatter()
                                  ],
                                  onChanged: (_) => setState(() {
                                        wht[invoice.id]!.acceptedEdited = true;
                                        _rebalanceSingleInvoice();
                                      }),
                                  decoration: const InputDecoration(
                                      labelText: 'WHT Accepted')),
                              if (_whtMinor(invoice.id) > 0 &&
                                  _whtMinor(invoice.id) !=
                                      _suggestedWhtMinor(invoice.id)) ...[
                                const SizedBox(height: 8),
                                TextField(
                                    key: ValueKey(
                                        'payment-wht-override-reason-${invoice.id}'),
                                    controller: wht[invoice.id]!.overrideReason,
                                    enabled: !posting,
                                    maxLength: 500,
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(
                                        labelText: 'WHT override reason',
                                        helperText:
                                            'Required because accepted WHT differs from the suggestion.')),
                              ],
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                  key: ValueKey(
                                      'payment-wht-certificate-${invoice.id}'),
                                  initialValue:
                                      wht[invoice.id]!.certificateStatus,
                                  decoration: const InputDecoration(
                                      labelText: 'Certificate status'),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'CERTIFICATE_PENDING',
                                        child: Text('Certificate Pending')),
                                    DropdownMenuItem(
                                        value: 'CERTIFICATE_RECEIVED',
                                        child: Text('Received')),
                                  ],
                                  onChanged: posting
                                      ? null
                                      : (value) => setState(() {
                                            wht[invoice.id]!.certificateStatus =
                                                value ?? 'CERTIFICATE_PENDING';
                                          })),
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                      key: ValueKey(
                                          'payment-wht-evidence-${invoice.id}'),
                                      onPressed: posting
                                          ? null
                                          : () async {
                                              final file =
                                                  await _picker.pickImage(
                                                      source:
                                                          ImageSource.gallery,
                                                      imageQuality: 90);
                                              if (file != null && mounted) {
                                                setState(() => wht[invoice.id]!
                                                    .certificate = file);
                                              }
                                            },
                                      icon: const Icon(Icons.attach_file),
                                      label: Text(wht[invoice.id]!
                                                  .certificate ==
                                              null
                                          ? 'Attach certificate photo — optional while pending'
                                          : wht[invoice.id]!
                                              .certificate!
                                              .name))),
                              Card(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Column(children: [
                                        _paymentMetric(
                                            'Cash allocated',
                                            _minor(allocations[invoice.id]
                                                        ?.text ??
                                                    '') /
                                                100),
                                        _paymentMetric('WHT accepted',
                                            _whtMinor(invoice.id) / 100),
                                        _paymentMetric(
                                            'Invoice settlement',
                                            (_minor(allocations[invoice.id]
                                                            ?.text ??
                                                        '') +
                                                    _whtMinor(invoice.id)) /
                                                100),
                                      ])))
                            ]
                          ]
                        ]))),
        const SizedBox(height: 12),
        DropdownButtonFormField<CehBankAccount>(
            initialValue: bank,
            decoration: const InputDecoration(labelText: 'Received Into'),
            items: banks
                .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
                .toList(),
            onChanged: posting ? null : (v) => setState(() => bank = v)),
        const SizedBox(height: 12),
        TextField(
            key: const ValueKey('payment-amount-received'),
            controller: amount,
            enabled: !posting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [NgnAmountInputFormatter()],
            onChanged: (_) => setState(_rebalanceSingleInvoice),
            decoration: const InputDecoration(labelText: 'Amount Received')),
        const SizedBox(height: 12),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  _paymentMetric('Amount Received', receivedMinor / 100),
                  _paymentMetric('Cash Allocated', allocatedMinor / 100),
                  _paymentMetric(
                      'Remaining Cash to Allocate', unallocatedMinor / 100),
                  _paymentMetric('WHT Accepted', whtAllocatedMinor / 100),
                  _paymentMetric('Invoice Settlement',
                      (allocatedMinor + whtAllocatedMinor) / 100),
                  _paymentMetric(
                      'Unallocated / Client Credit', unallocatedMinor / 100),
                ]))),
        const SizedBox(height: 12),
        TextField(
            controller: reference,
            enabled: !posting,
            decoration: const InputDecoration(
                labelText: 'Zenith Reference — optional')),
        const SizedBox(height: 20),
        FilledButton(
            key: const ValueKey('save-post-customer-payment'),
            onPressed: posting ? null : saveAndPost,
            child: Text(posting ? 'Posting…' : 'Save / Post Payment'))
      ]));

  Widget _paymentMetric(String label, double value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label),
        Text(formatNaira(value),
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: value < 0 ? Theme.of(context).colorScheme.error : null))
      ]));
}

class ApplyCustomerCreditScreen extends StatefulWidget {
  const ApplyCustomerCreditScreen(
      {super.key, required this.session, required this.api});
  final CehSession session;
  final CehApiClient api;

  @override
  State<ApplyCustomerCreditScreen> createState() =>
      _ApplyCustomerCreditScreenState();
}

class _ApplyCustomerCreditScreenState extends State<ApplyCustomerCreditScreen> {
  List<CehClient> clients = const [];
  List<BillingInvoice> invoices = const [];
  CehClient? client;
  int availableMinor = 0;
  final Map<int, TextEditingController> allocations = {};
  bool loading = false;
  bool applying = false;

  int _minor(String value) => parseNgnMinorUnits(value) ?? 0;
  int get appliedMinor => allocations.values
      .fold(0, (total, controller) => total + _minor(controller.text));
  int get remainingMinor =>
      availableMinor > appliedMinor ? availableMinor - appliedMinor : 0;

  @override
  void initState() {
    super.initState();
    widget.api.clients(widget.session).then((value) {
      if (mounted) setState(() => clients = value);
    });
  }

  @override
  void dispose() {
    for (final controller in allocations.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _message(String value) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(value)));

  Future<void> _selectClient(CehClient? value) async {
    for (final controller in allocations.values) {
      controller.dispose();
    }
    setState(() {
      client = value;
      availableMinor = 0;
      invoices = const [];
      allocations.clear();
      loading = value != null;
    });
    if (value == null) return;
    try {
      final results = await Future.wait([
        widget.api.availableCustomerCredit(widget.session, value.id),
        widget.api.outstandingInvoices(widget.session, value.id),
      ]);
      if (!mounted || client?.id != value.id) return;
      final rows = results[1] as List<BillingInvoice>;
      setState(() {
        availableMinor = ((results[0] as double) * 100).round();
        invoices = rows;
        for (final invoice in rows) {
          allocations[invoice.id] = TextEditingController();
        }
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      _message(e.code);
    }
  }

  Future<void> applyCredit() async {
    if (client == null || appliedMinor <= 0) {
      _message('Select a Client and enter an amount to apply.');
      return;
    }
    if (appliedMinor > availableMinor) {
      _message('Total Applied cannot exceed Available Client Credit.');
      return;
    }
    for (final invoice in invoices) {
      final value = _minor(allocations[invoice.id]?.text ?? '');
      if (value > (invoice.outstanding * 100).round()) {
        _message(
            '${invoice.reference} application exceeds its outstanding balance.');
        return;
      }
    }
    setState(() => applying = true);
    try {
      await widget.api.applyCustomerCredit(widget.session, {
        'client_id': client!.id,
        'application_date': canonicalAccountsDate(DateTime.now()),
        'allocations': [
          for (final invoice in invoices)
            if (_minor(allocations[invoice.id]?.text ?? '') > 0)
              {
                'invoice_id': invoice.id,
                'amount':
                    ngnMinorUnitsForApi(_minor(allocations[invoice.id]!.text)),
              }
        ],
      });
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) _message(e.code);
    } finally {
      if (mounted) setState(() => applying = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Apply Client Credit'),
          actions: cehHomeAction(context,
              canLeave: () => confirmCehDiscardChanges(context))),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const Text(
            'Apply previously received Client Credit / Advance to outstanding invoices. No new cash movement is created.'),
        const SizedBox(height: 12),
        DropdownButtonFormField<CehClient>(
            initialValue: client,
            decoration: const InputDecoration(labelText: 'Client'),
            items: clients
                .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
                .toList(),
            onChanged: applying ? null : _selectClient),
        const SizedBox(height: 12),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: _paymentMetric('Available Client Credit / Advance',
                    availableMinor / 100))),
        const SizedBox(height: 12),
        const Text('Outstanding Invoice(s)',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (loading)
          const Center(child: CircularProgressIndicator())
        else if (client != null && invoices.isEmpty)
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(16),
                  child:
                      Text('No outstanding issued invoices for this Client.')))
        else
          for (final invoice in invoices)
            Card(
                key: ValueKey('credit-invoice-${invoice.id}'),
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${invoice.reference} • ${invoice.projectNames.isEmpty ? 'General / No project' : invoice.projectNames}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                              'Outstanding ${formatNaira(invoice.outstanding)}'),
                          const SizedBox(height: 10),
                          TextField(
                              key: ValueKey('credit-allocation-${invoice.id}'),
                              controller: allocations[invoice.id],
                              enabled: !applying && availableMinor > 0,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: const [
                                NgnAmountInputFormatter()
                              ],
                              onChanged: (_) => setState(() {}),
                              decoration:
                                  const InputDecoration(labelText: 'Apply'))
                        ]))),
        const SizedBox(height: 12),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  _paymentMetric('Total Applied', appliedMinor / 100),
                  _paymentMetric(
                      'Remaining Client Credit', remainingMinor / 100),
                ]))),
        const SizedBox(height: 20),
        FilledButton(
            key: const ValueKey('apply-customer-credit-submit'),
            onPressed: applying ? null : applyCredit,
            child: Text(applying ? 'Applying…' : 'Apply Client Credit'))
      ]));

  Widget _paymentMetric(String label, double value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(child: Text(label)),
        Text(formatNaira(value),
            style: const TextStyle(fontWeight: FontWeight.w800))
      ]));
}

class ReceivablesAgeingScreen extends StatelessWidget {
  const ReceivablesAgeingScreen(
      {super.key, required this.session, required this.api});
  final CehSession session;
  final CehApiClient api;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Receivables Ageing'),
          actions: cehHomeAction(context)),
      body: FutureBuilder<Map<String, dynamic>>(
          future: api.receivablesAgeing(session),
          builder: (context, s) {
            if (!s.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = s.data!;
            final buckets = Map<String, dynamic>.from(data['buckets'] as Map);
            final invoices = (data['invoices'] as List? ?? const [])
                .map((row) => Map<String, dynamic>.from(row as Map))
                .toList();
            const order = ['CURRENT', '1_30', '31_60', '61_90', 'OVER_90'];
            return ListView(padding: const EdgeInsets.all(18), children: [
              for (final key in order)
                Card(
                    child: ListTile(
                        key: ValueKey('ageing-bucket-$key'),
                        title: Text(_ageingLabel(key)),
                        trailing: Text(formatNaira(
                            double.tryParse('${buckets[key]}') ?? 0)),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ReceivablesAgeingDetailScreen(
                                    bucket: key,
                                    totalMinor: _ageingMinor(buckets[key]),
                                    invoices: invoices
                                        .where((row) => row['bucket'] == key)
                                        .toList())))))
            ]);
          }));
}

String _ageingLabel(String key) =>
    const {
      'CURRENT': 'Current',
      '1_30': '1–30 Days Overdue',
      '31_60': '31–60 Days Overdue',
      '61_90': '61–90 Days Overdue',
      'OVER_90': 'Over 90 Days',
    }[key] ??
    key;

int _ageingMinor(dynamic value) {
  final match =
      RegExp(r'^(-?\d+)(?:\.(\d{1,2}))?$').firstMatch('$value'.trim());
  if (match == null) return 0;
  final whole = int.parse(match.group(1)!);
  final fraction = int.parse((match.group(2) ?? '').padRight(2, '0'));
  return whole < 0 ? whole * 100 - fraction : whole * 100 + fraction;
}

class ReceivablesAgeingDetailScreen extends StatelessWidget {
  const ReceivablesAgeingDetailScreen(
      {super.key,
      required this.bucket,
      required this.totalMinor,
      required this.invoices});
  final String bucket;
  final int totalMinor;
  final List<Map<String, dynamic>> invoices;

  @override
  Widget build(BuildContext context) {
    final reconciledMinor = invoices.fold<int>(
        0, (sum, row) => sum + _ageingMinor(row['outstanding']));
    return Scaffold(
        appBar: AppBar(
            title: Text(_ageingLabel(bucket)), actions: cehHomeAction(context)),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          _summary('Total Outstanding', totalMinor),
          if (reconciledMinor != totalMinor)
            const Text('RECEIVABLES_AGEING_RECONCILIATION_ERROR',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (invoices.isEmpty)
            const Text('No outstanding invoices in this bucket.'),
          for (final row in invoices)
            Card(
                child: ListTile(
                    title: Text(
                        '${row['reference']} • ${row['client_name_snapshot']}'),
                    subtitle: Text(
                        'Invoice ${displayAccountsDate('${row['invoice_date']}')} • Due ${row['due_date'] == null ? 'Not set' : displayAccountsDate('${row['due_date']}')}\n'
                        'Original ${formatNaira(double.tryParse('${row['original_amount'] ?? row['total_amount']}') ?? 0)} • Payments/Credits ${formatNaira(double.tryParse('${row['payments_credits_applied'] ?? row['settled']}') ?? 0)}\n'
                        '${row['days_outstanding'] ?? 0} days outstanding • ${row['days_overdue'] ?? 0} days overdue • ${_ageingLabel('${row['bucket']}')}'),
                    trailing: Text(
                        formatNaira(
                            double.tryParse('${row['outstanding']}') ?? 0),
                        style: const TextStyle(fontWeight: FontWeight.w800))))
        ]));
  }

  Widget _summary(String label, int valueMinor) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label),
        Text(formatNaira(valueMinor / 100),
            style: const TextStyle(fontWeight: FontWeight.w800))
      ]));
}
