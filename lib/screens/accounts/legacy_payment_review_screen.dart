import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/accounts_formatters.dart';
import '../../core/internal_navigation.dart';
import '../../models/session.dart';
import '../../models/accounts.dart';
import '../../widgets/accounts_widgets.dart';

class LegacyPaymentDraftsScreen extends StatefulWidget {
  const LegacyPaymentDraftsScreen({super.key, required this.api, required this.session});
  final CehApiClient api;
  final CehSession session;
  @override
  State<LegacyPaymentDraftsScreen> createState() => _LegacyPaymentDraftsState();
}
class _LegacyPaymentDraftsState extends State<LegacyPaymentDraftsScreen> {
  int page = 1;
  late Future<Map<String, dynamic>> data;
  @override
  void initState() { super.initState(); load(); }
  void load() { data = widget.api.ordinaryPaymentReview(widget.session, page: page); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Client Payment drafts'), actions: cehHomeAction(context)),
    body: FutureBuilder<Map<String, dynamic>>(future: data, builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: TextButton(onPressed: () => setState(load), child: const Text('Could not load drafts. Retry')));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final rows = snapshot.data!['drafts'] as List;
      return ListView(padding: const EdgeInsets.all(18), children: [
        if (rows.isEmpty) const Text('No ordinary Client Payment drafts.'),
        for (final raw in rows) ListTile(
          title: Text('${raw['reference']} • ${raw['client_name_snapshot']}'),
          subtitle: Text('${displayAccountsDate('${raw['receipt_date']}')}\n${raw['review_required'] == true ? 'Legacy payment draft — review required' : 'Payment draft'}'),
          trailing: Text(formatNaira(num.parse('${raw['cash_amount']}').toDouble())),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => LegacyPaymentReviewScreen(
                api: widget.api, session: widget.session, receiptId: int.parse('${raw['id']}'))));
            if (mounted) setState(load);
          }),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          TextButton(onPressed: page <= 1 ? null : () => setState(() { page--; load(); }), child: const Text('Previous')),
          Text('Page $page'),
          TextButton(onPressed: rows.length < 50 ? null : () => setState(() { page++; load(); }), child: const Text('Next'))
        ])
      ]);
    }));
}

class LegacyPaymentReviewScreen extends StatefulWidget {
  const LegacyPaymentReviewScreen({super.key, required this.api, required this.session, required this.receiptId});
  final CehApiClient api;
  final CehSession session;
  final int receiptId;
  @override
  State<LegacyPaymentReviewScreen> createState() => _LegacyPaymentReviewState();
}
class _ReviewLine {
  final cash = TextEditingController();
  final wht = TextEditingController();
  final base = TextEditingController();
  final reason = TextEditingController();
  int? code;
  void dispose() { cash.dispose(); wht.dispose(); base.dispose(); reason.dispose(); }
}
class _LegacyPaymentReviewState extends State<LegacyPaymentReviewScreen> {
  Map<String, dynamic>? receipt;
  List<BillingInvoice> invoices = [];
  List<Map<String, dynamic>> taxCodes = [];
  final Map<int, _ReviewLine> lines = {};
  List<Map<String, dynamic>> saved = [];
  bool loading = true, busy = false, dirty = true, reviewed = false, credit = false;
  String? error;
  Map<String, dynamic>? pendingSave;
  String requestKey() => List.generate(32, (_) => Random.secure().nextInt(256)).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { for (final l in lines.values) { l.dispose(); } super.dispose(); }
  int minor(String value) {
    if (value.trim().isEmpty) return 0;
    final parsed = parseNgnMinorUnits(value);
    if (parsed == null || parsed < 0) throw const FormatException('Enter a valid amount');
    return parsed;
  }
  Future<void> load() async {
    try {
      final result = await widget.api.ordinaryPaymentReview(widget.session, receiptId: widget.receiptId);
      final r = Map<String, dynamic>.from(result['receipt'] as Map);
      final list = await widget.api.outstandingInvoices(widget.session, int.parse('${r['client_id']}'));
      final tax = await widget.api.taxConfiguration(widget.session);
      if (!mounted) return;
      receipt = r; invoices = list;
      taxCodes = (tax['tax_codes'] as List? ?? []).map((v) => Map<String, dynamic>.from(v as Map)).where((c) {
        final date = '${r['receipt_date']}';
        return (c['is_active'] == true || '${c['is_active']}' == '1') && c['tax_type'] == 'WHT' &&
            '${c['effective_from']}'.compareTo(date) <= 0 &&
            (c['effective_to'] == null || '${c['effective_to']}'.isEmpty || '${c['effective_to']}'.compareTo(date) >= 0);
      }).toList();
      saved = (r['reviewed_allocations'] as List? ?? []).map((v) => Map<String, dynamic>.from(v as Map)).toList();
      for (final i in invoices) { lines.putIfAbsent(i.id, _ReviewLine.new); }
      for (final a in saved) {
        final id = int.parse('${a['invoice_id']}');
        final l = lines.putIfAbsent(id, _ReviewLine.new);
        l.cash.text = '${a['cash_amount'] ?? '0'}'; l.wht.text = '${a['wht_amount'] ?? '0'}';
        l.base.text = '${a['wht_calculation_base_amount'] ?? ''}';
        l.reason.text = '${a['wht_override_reason'] ?? ''}';
        l.code = int.tryParse('${a['wht_tax_code_id']}');
      }
      credit = r['client_credit_confirmed'] == true;
      // Opening never records review or silently removes stale saved intent.
      dirty = true; reviewed = false;
      setState(() { loading = false; error = null; });
    } catch (_) { if (mounted) setState(() { loading = false; error = 'Could not load authoritative draft. Retry.'; }); }
  }
  void changed() => setState(() { dirty = true; reviewed = false; });
  List<Map<String, dynamic>> allocations() => [
    for (final e in lines.entries)
      if (minor(e.value.cash.text) > 0 || minor(e.value.wht.text) > 0) {
        'invoice_id': e.key, 'cash_amount': ngnMinorUnitsForApi(minor(e.value.cash.text)),
        if (minor(e.value.wht.text) > 0) ...{
          'wht_amount': ngnMinorUnitsForApi(minor(e.value.wht.text)),
          'wht_tax_code_id': e.value.code,
          'wht_calculation_base_amount': ngnMinorUnitsForApi(minor(e.value.base.text)),
          'wht_override_reason': e.value.reason.text.trim(),
          'certificate_status': 'CERTIFICATE_PENDING',
        }
      }
  ];
  Future<void> save() async {
    if (!reviewed || busy) return;
    try {
      pendingSave ??= {'action':'SAVE_REVIEW','receipt_id':widget.receiptId,
        'draft_revision':receipt!['draft_revision'],'request_key':requestKey(),
        'review_completed':true,'client_credit_confirmed':credit,'allocations':allocations()};
      setState(() { busy = true; error = null; });
      final result = await widget.api.ordinaryPaymentReview(widget.session, action: pendingSave);
      if (!mounted) return;
      receipt = Map<String, dynamic>.from(result['receipt'] as Map);
      saved = (receipt!['reviewed_allocations'] as List).map((v) => Map<String, dynamic>.from(v as Map)).toList();
      setState(() { pendingSave = null; dirty = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { pendingSave = null; error = e.code; dirty = true; });
    } catch (_) { if (mounted) setState(() => error = 'Save outcome uncertain. Retry the same saved request or reopen the draft.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> post() async {
    if (dirty || busy || pendingSave != null) return;
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Post reviewed Client Payment?'),
      content: Text('Post ${receipt!['reference']} using the saved invoice/WHT allocations.${credit ? ' Unallocated cash is intentionally retained as Client Credit.' : ''} One payment journal will be created.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Back')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Post payment'))]));
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.postCustomerPayment(widget.session, {'receipt_id':widget.receiptId,
        'draft_revision':receipt!['draft_revision'],'allocations':saved});
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) { setState(() { error = '${e.code} — review the allocation again.'; dirty = true; reviewed = false; });
        final fresh = await widget.api.outstandingInvoices(widget.session, int.parse('${receipt!['client_id']}'));
        if (mounted) setState(() => invoices = fresh);
      }
    } catch (_) { if (mounted) setState(() => error = 'Posting outcome uncertain. Retry without changing the saved intent.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> cancel() async {
    var reason = '';
    final value = await showDialog<String>(context: context, builder: (c) => AlertDialog(
      title: const Text('Cancel unposted draft'),
      content: TextField(onChanged: (v) => reason = v, decoration: const InputDecoration(labelText: 'Reason')),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Back')),
        FilledButton(onPressed: () { if (reason.trim().isNotEmpty) Navigator.pop(c, reason.trim()); }, child: const Text('Cancel draft'))]));
    if (value == null || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.ordinaryPaymentReview(widget.session, action: {'action':'CANCEL','receipt_id':widget.receiptId,
        'draft_revision':receipt!['draft_revision'],'request_key':requestKey(),'reason':value});
      if (mounted) Navigator.pop(context);
    } catch (_) { if (mounted) setState(() => error = 'Cancellation outcome uncertain. Reopen to verify state.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Widget field(String label, TextEditingController c) => Padding(padding: const EdgeInsets.only(top: 14),
    child: TextField(controller: c, enabled: !busy && pendingSave == null,
      decoration: InputDecoration(labelText: label), onChanged: (_) => changed()));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Review Client Payment draft'), actions: cehHomeAction(context)),
    body: loading ? const Center(child: CircularProgressIndicator()) : receipt == null
      ? Center(child: TextButton(onPressed: load, child: Text(error ?? 'Retry')))
      : ListView(padding: const EdgeInsets.all(18), children: [
        const Text('Legacy payment draft — review required', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const Text('This draft predates the current allocation workflow. Historical destinations are context only. Review the intended allocations before posting.'),
        const SizedBox(height: 16),
        Text('${receipt!['reference']} • ${receipt!['client_name_snapshot']}'),
        Text('Payment date: ${displayAccountsDate('${receipt!['receipt_date']}')}'),
        Text('Amount: ${formatNaira(num.parse('${receipt!['cash_amount']}').toDouble())}'),
        Text('Bank: ${receipt!['current_bank_name']}'),
        Text('Reference: ${receipt!['bank_reference'] ?? '—'}'),
        Text('Narration: ${receipt!['narration'] ?? '—'}'),
        Text('Historical destination: ${receipt!['destination']}'),
        if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(error!)),
        if (receipt!['status'] != 'DRAFT') Text('Status: ${receipt!['status']}'),
        if (receipt!['status'] == 'DRAFT') ...[
          for (final e in lines.entries.where((e) => !invoices.any((i) => i.id == e.key))) Card(child: ListTile(
            title: const Text('Previously reviewed invoice is no longer eligible'),
            subtitle: Text('Saved cash ${e.value.cash.text}; WHT ${e.value.wht.text}. Remove explicitly to reallocate.'),
            trailing: TextButton(onPressed: busy || pendingSave != null ? null : () { e.value.cash.clear(); e.value.wht.clear(); changed(); }, child: const Text('Remove allocation')))),
          for (final i in invoices) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${i.reference} — outstanding ${formatNaira(i.outstanding)}'),
            field('Cash allocation', lines.putIfAbsent(i.id, _ReviewLine.new).cash),
            DropdownButtonFormField<int>(initialValue: taxCodes.any((c) => int.parse('${c['id']}') == lines[i.id]!.code) ? lines[i.id]!.code : null,
              decoration: const InputDecoration(labelText: 'WHT code (optional)'), isExpanded: true,
              items: [for (final c in taxCodes) DropdownMenuItem(value: int.parse('${c['id']}'), child: Text('${c['code']} • ${c['rate_percent']}%', overflow: TextOverflow.ellipsis))],
              onChanged: busy || pendingSave != null ? null : (v) { lines[i.id]!.code = v; changed(); }),
            field('WHT calculation base', lines[i.id]!.base), field('WHT amount', lines[i.id]!.wht),
            field('WHT override reason (if required)', lines[i.id]!.reason),
            const Text('Any WHT certificate remains Pending. Certificate receipt is a separate workflow.')
          ]))),
          CheckboxListTile(value: credit, onChanged: busy || pendingSave != null ? null : (v) { credit = v!; changed(); }, title: const Text('Intentionally retain any unallocated cash as Client Credit')),
          CheckboxListTile(value: reviewed, onChanged: busy || pendingSave != null ? null : (v) => setState(() => reviewed = v!), title: const Text('I have reviewed and reconstructed the intended allocation')),
          FilledButton(onPressed: busy || !reviewed ? null : save, child: Text(pendingSave != null ? 'Retry same save' : 'Save reviewed draft')),
          const SizedBox(height: 12),
          FilledButton(onPressed: busy || dirty ? null : post, child: const Text('Post saved reviewed payment')),
          TextButton(onPressed: busy || pendingSave != null ? null : cancel, child: const Text('Cancel unposted draft')),
        ]
      ]));
}
