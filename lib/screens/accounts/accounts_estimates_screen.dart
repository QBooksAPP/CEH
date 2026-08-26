import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/accounts_formatters.dart';
import '../../core/api_client.dart';
import '../../models/accounts.dart';
import '../../models/client.dart';
import '../../models/mixer_context.dart';
import '../../models/project.dart';
import '../../models/session.dart';
import '../../widgets/accounts_widgets.dart';

Future<void> _shareBillingPdf(
    BuildContext context,
    Future<ProductionReportFile> request,
    String folder,
    String title,
    String failure) async {
  try {
    final pdf = await request;
    final root = await getTemporaryDirectory();
    final dir = Directory('${root.path}/$folder');
    await dir.create(recursive: true);
    final safe = RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(pdf.filename)
        ? pdf.filename
        : '$title.pdf';
    final file = File('${dir.path}/$safe');
    await file.writeAsBytes(pdf.bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
        title: title, files: [XFile(file.path, mimeType: 'application/pdf')]));
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.code)));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }
}

Future<void> shareClientPaymentPdf(BuildContext context, CehApiClient api,
        CehSession session, int id, String reference) =>
    _shareBillingPdf(context, api.clientPaymentPdf(session, id),
        'ceh-client-payments', reference, 'CLIENT_PAYMENT_PDF_SHARE_FAILED');

class ClientPaymentsScreen extends StatefulWidget {
  const ClientPaymentsScreen(
      {super.key,
      required this.session,
      required this.api,
      required this.newPaymentBuilder});
  final CehSession session;
  final CehApiClient api;
  final WidgetBuilder newPaymentBuilder;
  @override
  State<ClientPaymentsScreen> createState() => _ClientPaymentsScreenState();
}

class _ClientPaymentsScreenState extends State<ClientPaymentsScreen> {
  late Future<List<ClientPayment>> future;
  @override
  void initState() {
    super.initState();
    future = widget.api.clientPayments(widget.session);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Client Payments')),
      floatingActionButton: FloatingActionButton.extended(
          label: const Text('New Client Payment'),
          icon: const Icon(Icons.add),
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: widget.newPaymentBuilder))),
      body: FutureBuilder<List<ClientPayment>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                  child: Text(
                      'Unable to load Client Payments: ${snapshot.error}'));
            }
            final rows = snapshot.data ?? const [];
            if (rows.isEmpty) {
              return const Center(
                  child: Text('No posted Client Payments yet.'));
            }
            return ListView(padding: const EdgeInsets.all(18), children: [
              for (final payment in rows)
                Card(
                    child: ListTile(
                        key: ValueKey('client-payment-${payment.id}'),
                        title: Text('${payment.reference} • ${payment.client}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(
                            '${displayAccountsDate(payment.date)} • ${payment.receivedInto}'),
                        trailing: Text(formatNaira(payment.cash)),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ClientPaymentDetailsScreen(
                                    payment: payment,
                                    session: widget.session,
                                    api: widget.api)))))
            ]);
          }));
}

class ClientPaymentDetailsScreen extends StatelessWidget {
  const ClientPaymentDetailsScreen(
      {super.key,
      required this.payment,
      required this.session,
      required this.api});
  final ClientPayment payment;
  final CehSession session;
  final CehApiClient api;
  Widget metric(String label, Object? value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
            width: 180,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700))),
        Expanded(child: Text('$value'))
      ]));
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Client Payment Details')),
      body: FutureBuilder<Map<String, dynamic>>(
          future: api.clientPaymentDetails(session, payment.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('${snapshot.error}'));
            }
            final data = snapshot.data!;
            final header = Map<String, dynamic>.from(data['payment'] as Map);
            final summary = Map<String, dynamic>.from(data['summary'] as Map);
            final allocations = (data['allocations'] as List? ?? const [])
                .map((e) => Map<String, dynamic>.from(e as Map));
            double money(Object? value) => double.parse('$value');
            return ListView(padding: const EdgeInsets.all(18), children: [
              Text('${header['reference']}',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        metric('Client', header['client_name_snapshot']),
                        metric('Payment Date',
                            displayAccountsDate('${header['receipt_date']}')),
                        metric(
                            'Received Into', header['received_into_snapshot']),
                        metric(
                            'Bank Reference', header['bank_reference'] ?? '—'),
                        metric('Cash Received',
                            formatNaira(money(summary['cash_received']))),
                        metric('Cash Applied to Invoices',
                            formatNaira(money(summary['cash_applied']))),
                        metric('WHT Deducted by Client',
                            formatNaira(money(summary['wht_deducted']))),
                        metric('Total Invoice Settlement',
                            formatNaira(money(summary['invoice_settlement']))),
                        metric('Unallocated Client Credit / Advance',
                            formatNaira(money(summary['unallocated_credit'])))
                      ]))),
              const SizedBox(height: 12),
              Text('Invoice Allocations',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              for (final allocation in allocations)
                Card(
                    child: ListTile(
                        title: Text(
                            '${allocation['invoice_reference']} • ${allocation['project_names'] ?? 'General / No project'}'),
                        subtitle: Text(
                            'Cash ${formatNaira(money(allocation['cash_amount']))} • WHT ${formatNaira(money(allocation['wht_amount']))}${allocation['wht_code'] == null ? '' : ' • ${allocation['wht_code']} ${formatBillingTaxRate(allocation['rate_snapshot'])} • ${formatAccountsStatus('${allocation['certificate_status']}')}'}'),
                        trailing: Text(formatNaira(
                            money(allocation['cash_amount']) +
                                money(allocation['wht_amount']))))),
              const SizedBox(height: 15),
              FilledButton.icon(
                  onPressed: () => shareClientPaymentPdf(
                      context, api, session, payment.id, payment.reference),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('View / Share Receipt PDF'))
            ]);
          }));
}

class EstimatesScreen extends StatefulWidget {
  const EstimatesScreen({super.key, required this.session, required this.api});
  final CehSession session;
  final CehApiClient api;
  @override
  State<EstimatesScreen> createState() => _EstimatesScreenState();
}

class _EstimatesScreenState extends State<EstimatesScreen> {
  late Future<List<EstimateSummary>> future;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => future = widget.api.estimates(widget.session);
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Estimates')),
      floatingActionButton: FloatingActionButton.extended(
          key: const ValueKey('new-estimate'),
          icon: const Icon(Icons.add),
          label: const Text('New Estimate'),
          onPressed: () async {
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => EstimateEditorScreen(
                        session: widget.session, api: widget.api)));
            if (mounted) setState(reload);
          }),
      body: FutureBuilder<List<EstimateSummary>>(
          future: future,
          builder: (context, s) {
            if (s.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (s.hasError) return Center(child: Text('${s.error}'));
            final rows = s.data ?? const [];
            if (rows.isEmpty) {
              return const Center(child: Text('No Estimates yet.'));
            }
            return ListView(padding: const EdgeInsets.all(18), children: [
              for (final e in rows)
                Card(
                    child: ListTile(
                        key: ValueKey('estimate-${e.id}'),
                        title: Text('${e.reference} • ${e.client}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(
                            '${formatAccountsStatus(e.status)}${e.expiredWarning ? ' • Expired warning' : ''} • Valid until ${displayAccountsDate(e.validUntil)}'),
                        trailing: Text(formatNaira(e.total)),
                        onTap: () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => EstimateDetailsScreen(
                                      id: e.id,
                                      session: widget.session,
                                      api: widget.api)));
                          if (mounted) setState(reload);
                        }))
            ]);
          }));
}

class _EstimateLineDraft {
  _EstimateLineDraft(
      {String description = '',
      String quantity = '',
      String rate = '',
      this.accountId,
      this.projectId,
      this.mixerId})
      : description = TextEditingController(text: description),
        quantity = TextEditingController(text: quantity),
        rate = TextEditingController(text: rate);
  final TextEditingController description;
  final TextEditingController quantity;
  final TextEditingController rate;
  int? accountId;
  int? projectId;
  int? mixerId;
  void dispose() {
    description.dispose();
    quantity.dispose();
    rate.dispose();
  }
}

class EstimateEditorScreen extends StatefulWidget {
  const EstimateEditorScreen(
      {super.key, required this.session, required this.api, this.estimateId});
  final CehSession session;
  final CehApiClient api;
  final int? estimateId;
  @override
  State<EstimateEditorScreen> createState() => _EstimateEditorScreenState();
}

class _EstimateEditorScreenState extends State<EstimateEditorScreen> {
  List<CehClient> clients = const [];
  List<FinancialAccount> accounts = const [];
  List<CehProject> projects = const [];
  List<MixerContext> mixers = const [];
  List<Map<String, dynamic>> vat = const [];
  CehClient? client;
  String mode = 'NONE';
  int? vatId;
  final lines = [_EstimateLineDraft()];
  bool busy = false;
  late String date;
  late String valid;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    date = canonicalAccountsDate(now);
    valid = canonicalAccountsDate(now.add(const Duration(days: 30)));
    load();
  }

  Future<void> load() async {
    final r = await Future.wait([
      widget.api.clients(widget.session),
      widget.api.financialAccounts(widget.session),
      widget.api.taxConfiguration(widget.session),
      widget.api.mixerContexts(widget.session)
    ]);
    if (!mounted) return;
    setState(() {
      clients = r[0] as List<CehClient>;
      accounts = (r[1] as List<FinancialAccount>)
          .where((a) => a.accountType == 'INCOME' && a.isPostable && a.isActive)
          .toList();
      vat = ((r[2] as Map)['tax_codes'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) =>
              e['tax_type'] == 'VAT' &&
              ('${e['is_active']}' == '1' || e['is_active'] == true))
          .toList();
      mixers = r[3] as List<MixerContext>;
    });
    if (widget.estimateId != null) {
      final detail =
          await widget.api.estimateDetails(widget.session, widget.estimateId!);
      if (!mounted) return;
      final header = Map<String, dynamic>.from(detail['estimate'] as Map);
      final draftLines = detail['lines'] as List? ?? const [];
      CehClient? selected;
      for (final value in clients) {
        if (value.id == int.parse('${header['client_id']}')) {
          selected = value;
          break;
        }
      }
      if (selected != null) {
        final clientProjects =
            await widget.api.projects(widget.session, selected.id);
        if (!mounted) return;
        setState(() {
          client = selected;
          projects = clientProjects;
          date = '${header['estimate_date']}';
          valid = '${header['valid_until']}';
          mode = '${header['vat_mode']}';
          vatId = header['vat_tax_code_id'] == null
              ? null
              : int.parse('${header['vat_tax_code_id']}');
          for (final line in lines) {
            line.dispose();
          }
          lines
            ..clear()
            ..addAll(draftLines.map((raw) {
              final line = Map<String, dynamic>.from(raw as Map);
              return _EstimateLineDraft(
                  description: '${line['description']}',
                  quantity: '${line['quantity'] ?? ''}',
                  rate: '${line['unit_price'] ?? ''}',
                  accountId: int.parse('${line['revenue_account_id']}'),
                  projectId: line['project_id'] == null
                      ? null
                      : int.parse('${line['project_id']}'),
                  mixerId: line['mixer_id'] == null
                      ? null
                      : int.parse('${line['mixer_id']}'));
            }));
        });
      }
    }
  }

  Future<void> selectClient(CehClient? c) async {
    setState(() => client = c);
    if (c == null) return;
    final p = await widget.api.projects(widget.session, c.id);
    if (mounted) setState(() => projects = p);
  }

  Future<void> pickDate(bool validity) async {
    final current =
        DateTime.tryParse(validity ? valid : date) ?? DateTime.now();
    final picked = await showDatePicker(
        context: context,
        initialDate: current,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (picked != null && mounted) {
      setState(() {
        if (validity) {
          valid = canonicalAccountsDate(picked);
        } else {
          date = canonicalAccountsDate(picked);
        }
      });
    }
  }

  Future<void> save() async {
    if (client == null ||
        lines.any((l) =>
            l.accountId == null ||
            l.description.text.trim().isEmpty ||
            l.quantity.text.trim().isEmpty ||
            l.rate.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Complete Client and all Estimate lines.')));
      return;
    }
    setState(() => busy = true);
    try {
      final payload = {
        if (widget.estimateId != null) 'id': widget.estimateId,
        'client_id': client!.id,
        'estimate_date': date,
        'valid_until': valid,
        'vat_mode': mode,
        'vat_tax_code_id': vatId,
        'terms': 'Advance Payment',
        'lines': [
          for (final l in lines)
            {
              'description': l.description.text.trim(),
              'quantity': l.quantity.text.replaceAll(',', ''),
              'unit_name': 'm³',
              'unit_price': l.rate.text.replaceAll(',', ''),
              'amount': ((double.parse(l.quantity.text.replaceAll(',', '')) *
                      double.parse(l.rate.text.replaceAll(',', ''))))
                  .toStringAsFixed(2),
              'revenue_account_id': l.accountId,
              'project_id': l.projectId,
              'mixer_id': l.mixerId,
              'taxable': true
            }
        ]
      };
      final result = await widget.api.saveEstimate(widget.session, payload);
      if (mounted) Navigator.pop(context, result);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    for (final l in lines) {
      l.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(widget.estimateId == null
              ? 'New Estimate'
              : 'Edit Estimate Draft')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        DropdownButtonFormField<CehClient>(
            initialValue: client,
            decoration: const InputDecoration(labelText: 'Client'),
            items: clients
                .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                .toList(),
            onChanged: busy ? null : selectClient),
        const SizedBox(height: 10),
        TextFormField(
            key: ValueKey('estimate-date-$date'),
            initialValue: displayAccountsDate(date),
            decoration: const InputDecoration(labelText: 'Estimate Date'),
            readOnly: true,
            onTap: busy ? null : () => pickDate(false)),
        const SizedBox(height: 10),
        TextFormField(
            key: ValueKey('estimate-valid-$valid'),
            initialValue: displayAccountsDate(valid),
            decoration: const InputDecoration(labelText: 'Valid Until'),
            readOnly: true,
            onTap: busy ? null : () => pickDate(true)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
            initialValue: mode,
            decoration: const InputDecoration(labelText: 'VAT Treatment'),
            items: const [
              DropdownMenuItem(value: 'NONE', child: Text('No VAT')),
              DropdownMenuItem(
                  value: 'VAT_EXCLUSIVE', child: Text('VAT Exclusive')),
              DropdownMenuItem(
                  value: 'VAT_INCLUSIVE', child: Text('VAT Inclusive'))
            ],
            onChanged: (v) => setState(() {
                  mode = v!;
                  if (mode == 'NONE') vatId = null;
                })),
        if (mode != 'NONE')
          DropdownButtonFormField<int>(
              initialValue: vatId,
              decoration: const InputDecoration(labelText: 'VAT Code'),
              items: vat
                  .map((v) => DropdownMenuItem(
                      value: int.parse('${v['id']}'),
                      child: Text(
                          '${v['name']} ${formatBillingTaxRate(v['rate_percent'])}')))
                  .toList(),
              onChanged: (v) => setState(() => vatId = v)),
        const SizedBox(height: 16),
        for (int i = 0; i < lines.length; i++)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Line ${i + 1}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        TextField(
                            controller: lines[i].description,
                            decoration: const InputDecoration(
                                labelText: 'Description')),
                        Row(children: [
                          Expanded(
                              child: TextField(
                                  controller: lines[i].quantity,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Quantity / m³'))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: TextField(
                                  controller: lines[i].rate,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration:
                                      const InputDecoration(labelText: 'Rate')))
                        ]),
                        DropdownButtonFormField<int>(
                            initialValue: lines[i].accountId,
                            decoration: const InputDecoration(
                                labelText: 'Revenue Category'),
                            items: accounts
                                .map((a) => DropdownMenuItem(
                                    value: a.id, child: Text(a.name)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => lines[i].accountId = v)),
                        DropdownButtonFormField<int>(
                            initialValue: lines[i].projectId,
                            decoration: const InputDecoration(
                                labelText: 'Project / Site — optional'),
                            items: projects
                                .map((p) => DropdownMenuItem(
                                    value: p.id, child: Text(p.name)))
                                .toList(),
                            onChanged: (v) => setState(() {
                                  lines[i].projectId = v;
                                  lines[i].mixerId = null;
                                })),
                        DropdownButtonFormField<int>(
                            initialValue: lines[i].mixerId,
                            decoration: const InputDecoration(
                                labelText: 'Equipment — optional'),
                            items: mixers
                                .where((m) =>
                                    m.assignment?.clientId == client?.id &&
                                    (lines[i].projectId == null ||
                                        m.assignment?.projectId ==
                                            lines[i].projectId))
                                .map((m) => DropdownMenuItem(
                                    value: m.id,
                                    child: Text('${m.code} — ${m.name}')))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => lines[i].mixerId = v))
                      ]))),
        TextButton.icon(
            onPressed: busy
                ? null
                : () => setState(() => lines.add(_EstimateLineDraft())),
            icon: const Icon(Icons.add),
            label: const Text('Add another line')),
        const SizedBox(height: 18),
        FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Saving…' : 'Save Draft'))
      ]));
}

class EstimateDetailsScreen extends StatefulWidget {
  const EstimateDetailsScreen(
      {super.key, required this.id, required this.session, required this.api});
  final int id;
  final CehSession session;
  final CehApiClient api;
  @override
  State<EstimateDetailsScreen> createState() => _EstimateDetailsScreenState();
}

class _EstimateDetailsScreenState extends State<EstimateDetailsScreen> {
  late Future<Map<String, dynamic>> future;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() =>
      future = widget.api.estimateDetails(widget.session, widget.id);
  Future<void> action(String endpoint,
      {Map<String, dynamic> extra = const {}}) async {
    setState(() => busy = true);
    try {
      await widget.api.estimateAction(
          widget.session, endpoint, {'estimate_id': widget.id, ...extra});
      if (mounted) setState(reload);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> releaseDraftConversion(int invoiceId) async {
    final reason = TextEditingController();
    final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Release Invoice Draft Conversion'),
                content: TextField(
                    controller: reason,
                    maxLength: 500,
                    decoration: const InputDecoration(
                        labelText: 'Reason',
                        helperText:
                            'The Invoice Draft and audit history remain; Estimate capacity is restored.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Keep Draft')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Release Capacity'))
                ]));
    final value = reason.text.trim();
    reason.dispose();
    if (approved != true || value.isEmpty) return;
    setState(() => busy = true);
    try {
      await widget.api.estimateAction(
          widget.session,
          'estimate_conversion_release.php',
          {'invoice_id': invoiceId, 'reason': value});
      if (mounted) setState(reload);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> accept() async {
    final note = TextEditingController();
    XFile? evidence;
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
                    title: const Text('Record Client Acceptance'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: note,
                          decoration: const InputDecoration(
                              labelText:
                                  'Acceptance note / reference — optional')),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await ImagePicker().pickImage(
                                source: ImageSource.gallery, imageQuality: 92);
                            if (picked != null) {
                              setDialogState(() => evidence = picked);
                            }
                          },
                          icon: const Icon(Icons.attach_file),
                          label: Text(evidence == null
                              ? 'Attach acceptance evidence — optional'
                              : evidence!.name))
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Accept'))
                    ])));
    if (ok == true) {
      int? evidenceId;
      if (evidence != null) {
        final bytes = await evidence!.readAsBytes();
        final mime = evidence!.name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';
        evidenceId = await widget.api.uploadEstimateAcceptanceEvidence(
            widget.session, widget.id, evidence!.name, mime, bytes);
      }
      await action('estimate_accept.php', extra: {
        'acceptance_note': note.text,
        if (evidenceId != null) 'acceptance_evidence_id': evidenceId
      });
    }
    note.dispose();
  }

  Future<void> decline() async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Record Client Decline'),
                content: TextField(
                    controller: reason,
                    decoration:
                        const InputDecoration(labelText: 'Decline reason'),
                    maxLength: 500),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Record Decline'))
                ]));
    if (confirmed == true && reason.text.trim().isNotEmpty) {
      await action('estimate_decline.php',
          extra: {'reason': reason.text.trim()});
    }
    reason.dispose();
  }

  Future<void> convert(List<dynamic> raw) async {
    final controllers = <int, TextEditingController>{};
    for (final x in raw) {
      final l = Map<String, dynamic>.from(x as Map);
      controllers[int.parse('${l['id']}')] = TextEditingController();
    }
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Convert to Invoice Draft'),
                content: SizedBox(
                    width: 520,
                    child: ListView(shrinkWrap: true, children: [
                      for (final x in raw)
                        Builder(builder: (_) {
                          final l = Map<String, dynamic>.from(x as Map);
                          return TextField(
                              controller: controllers[int.parse('${l['id']}')],
                              decoration: InputDecoration(
                                  labelText:
                                      '${l['description']} — ${l['quantity'] == null ? 'Amount' : 'Quantity'}',
                                  helperText:
                                      'Estimated ${l['quantity'] ?? l['entered_amount']} • Previously converted ${l['quantity'] == null ? l['converted_amount'] : l['converted_quantity']} • Remaining ${l['quantity'] == null ? l['remaining_amount'] : l['remaining_quantity']}'));
                        })
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Create Invoice Draft'))
                ]));
    if (ok == true) {
      final lines = <Map<String, dynamic>>[];
      for (final x in raw) {
        final l = Map<String, dynamic>.from(x as Map);
        final id = int.parse('${l['id']}');
        if (controllers[id]!.text.trim().isNotEmpty) {
          lines.add({
            'estimate_line_id': id,
            l['quantity'] == null ? 'amount' : 'quantity':
                controllers[id]!.text.replaceAll(',', '')
          });
        }
      }
      setState(() => busy = true);
      try {
        final out = await widget.api.convertEstimate(
            widget.session, {'estimate_id': widget.id, 'lines': lines});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Invoice Draft ${(out['invoice'] as Map)['reference']} created.')));
        }
        if (mounted) setState(reload);
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.code)));
        }
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
    for (final c in controllers.values) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Estimate Details')),
      body: FutureBuilder<Map<String, dynamic>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('${snapshot.error}'));
            }
            final data = snapshot.data!;
            final estimate = Map<String, dynamic>.from(data['estimate'] as Map);
            final lines = data['lines'] as List? ?? const [];
            final generated = data['generated_invoices'] as List? ?? const [];
            final status = '${estimate['status']}';
            return ListView(padding: const EdgeInsets.all(18), children: [
              Text('${estimate['reference']}',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              Text(
                  '${estimate['client_name_snapshot']} • ${formatAccountsStatus(status)}${estimate['expired_warning'] == true ? ' • Expired warning' : ''}'),
              Text(
                  'Estimate ${displayAccountsDate('${estimate['estimate_date']}')} • Valid until ${displayAccountsDate('${estimate['valid_until']}')}'),
              Text(
                  'Total ${formatNaira(double.parse('${estimate['total_amount']}'))}'),
              if (estimate['revision_of_reference'] != null)
                Text('Revision of ${estimate['revision_of_reference']}'),
              const SizedBox(height: 12),
              for (final raw in lines)
                Builder(builder: (_) {
                  final line = Map<String, dynamic>.from(raw as Map);
                  final quantityLine = line['quantity'] != null;
                  return Card(
                      child: ListTile(
                          title: Text('${line['description']}'),
                          subtitle: Text(
                              'Estimated ${quantityLine ? line['quantity'] : line['entered_amount']} • Previously converted ${quantityLine ? line['converted_quantity'] : line['converted_amount']} • Remaining ${quantityLine ? line['remaining_quantity'] : line['remaining_amount']}'),
                          trailing: Text(formatNaira(
                              double.parse('${line['gross_amount']}')))));
                }),
              if (generated.isNotEmpty) ...[
                const Text('Generated Invoice Draft(s)',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                for (final raw in generated)
                  Builder(builder: (_) {
                    final invoice = Map<String, dynamic>.from(raw as Map);
                    return ListTile(
                        title: Text('${invoice['reference']}'),
                        subtitle:
                            Text(formatAccountsStatus('${invoice['status']}')),
                        trailing: '${invoice['status']}' == 'DRAFT'
                            ? TextButton(
                                onPressed: busy
                                    ? null
                                    : () => releaseDraftConversion(
                                        (invoice['id'] as num).toInt()),
                                child: const Text('Release Draft Capacity'))
                            : null);
                  })
              ],
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (status == 'DRAFT')
                  OutlinedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => EstimateEditorScreen(
                                          session: widget.session,
                                          api: widget.api,
                                          estimateId: widget.id)));
                              if (mounted) setState(reload);
                            },
                      child: const Text('Edit Draft')),
                if (status == 'DRAFT')
                  FilledButton(
                      onPressed:
                          busy ? null : () => action('estimate_send.php'),
                      child: const Text('Send Estimate')),
                if (status != 'DRAFT')
                  OutlinedButton.icon(
                      onPressed: () => _shareBillingPdf(
                          context,
                          widget.api.estimatePdf(widget.session, widget.id),
                          'ceh-estimates',
                          '${estimate['reference']}',
                          'ESTIMATE_PDF_SHARE_FAILED'),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('View / Share Estimate PDF')),
                if (status == 'SENT')
                  FilledButton(
                      onPressed: busy ? null : accept,
                      child: const Text('Record Client Acceptance')),
                if (status == 'SENT')
                  OutlinedButton(
                      onPressed: busy ? null : decline,
                      child: const Text('Record Client Decline')),
                if (status == 'SENT' && estimate['expired_warning'] == true)
                  OutlinedButton(
                      onPressed:
                          busy ? null : () => action('estimate_expire.php'),
                      child: const Text('Mark Expired')),
                if (status == 'ACCEPTED')
                  FilledButton(
                      onPressed: busy ? null : () => convert(lines),
                      child: const Text('Convert to Invoice')),
                if (status != 'DRAFT')
                  OutlinedButton(
                      onPressed:
                          busy ? null : () => action('estimate_revision.php'),
                      child: const Text('Create Revision'))
              ])
            ]);
          }));
}
