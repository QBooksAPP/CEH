import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/accounts_formatters.dart';
import '../../core/api_client.dart';
import '../../core/internal_navigation.dart';
import '../../models/accounts.dart';
import '../../models/client.dart';
import '../../models/project.dart';
import '../../models/session.dart';
import '../../widgets/accounts_widgets.dart';

class AccountsGeneralExpenseScreen extends StatefulWidget {
  const AccountsGeneralExpenseScreen(
      {super.key, required this.session, this.statement, this.expense});
  final CehSession session;
  final CehBankTransaction? statement;
  final Map<String, dynamic>? expense;
  @override
  State<AccountsGeneralExpenseScreen> createState() =>
      _AccountsGeneralExpenseScreenState();
}

class _AccountsGeneralExpenseScreenState
    extends State<AccountsGeneralExpenseScreen> {
  final _api = const CehApiClient();
  final _picker = ImagePicker();
  final _total = TextEditingController(),
      _description = TextEditingController(),
      _bankReference = TextEditingController(),
      _oneOffPayee = TextEditingController(),
      _noReceiptReason = TextEditingController();
  final List<Map<String, dynamic>> _lines = [];
  late Future<
      ({
        List<CehBankAccount> banks,
        List<ExpenseSupplier> suppliers,
        List<FinancialAccount> accounts,
        List<CehClient> clients,
        List<CehProject> projects,
        List<Map<String, dynamic>> mixers
      })> _lookups;
  int? _bank, _supplier;
  String _date = canonicalAccountsDate(DateTime.now());
  bool _noReceipt = false, _saving = false;
  bool _oneOff = false;
  XFile? _receipt;
  @override
  void initState() {
    super.initState();
    final s = widget.statement;
    if (s != null) {
      _date = s.date;
      _total.text = s.amount.abs().toStringAsFixed(2);
      _description.text = s.narration;
      _bankReference.text = s.reference;
    }
    final expense = widget.expense;
    if (expense != null) {
      _bank = (expense['bank_account_id'] as num?)?.toInt();
      _supplier = (expense['supplier_id'] as num?)?.toInt();
      _oneOff = _supplier == null &&
          '${expense['supplier_name_snapshot'] ?? ''}'.trim().isNotEmpty;
      if (_oneOff) {
        _oneOffPayee.text = '${expense['supplier_name_snapshot']}';
      }
      _date = '${expense['expense_date'] ?? _date}';
      _total.text = '${expense['amount'] ?? ''}';
      _description.text = '${expense['description'] ?? ''}';
      _bankReference.text = '${expense['bank_reference'] ?? ''}';
      _noReceiptReason.text = '${expense['no_receipt_reason'] ?? ''}';
      _noReceipt = _noReceiptReason.text.trim().isNotEmpty;
      _lines.addAll((expense['lines'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)));
    }
    _lookups = _load();
  }

  Future<
      ({
        List<CehBankAccount> banks,
        List<ExpenseSupplier> suppliers,
        List<FinancialAccount> accounts,
        List<CehClient> clients,
        List<CehProject> projects,
        List<Map<String, dynamic>> mixers
      })> _load() async {
    final b = await _api.bankAccounts(widget.session);
    final s = await _api.expenseSuppliers(widget.session);
    final a = await _api.financialAccounts(widget.session);
    final clients = await _api.clients(widget.session);
    final projects = (await Future.wait(
            clients.map((c) => _api.projects(widget.session, c.id))))
        .expand((x) => x)
        .toList();
    final mixers = await _api.mixers(widget.session);
    return (
      banks: b,
      suppliers: s,
      accounts: a
          .where(
              (x) => x.accountType == 'EXPENSE' && x.isActive && x.isPostable)
          .toList(),
      clients: clients,
      projects: projects,
      mixers: mixers
    );
  }

  @override
  void dispose() {
    _total.dispose();
    _description.dispose();
    _bankReference.dispose();
    _oneOffPayee.dispose();
    _noReceiptReason.dispose();
    super.dispose();
  }

  Future<void> _newSupplier() async {
    final c = TextEditingController();
    final result = await showDialog<ExpenseSupplier>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Create Supplier'),
                content: TextField(
                    controller: c,
                    decoration:
                        const InputDecoration(labelText: 'Canonical name')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back')),
                  FilledButton(
                      onPressed: () async {
                        if (c.text.trim().isEmpty) return;
                        try {
                          final s = await _api.createExpenseSupplier(
                              widget.session,
                              {'canonical_name': c.text.trim()});
                          if (context.mounted) {
                            Navigator.pop(context, s);
                          }
                        } on ApiException catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(e.code)));
                          }
                        }
                      },
                      child: const Text('Create'))
                ]));
    c.dispose();
    if (result != null && mounted) {
      setState(() {
        _supplier = result.id;
        _lookups = _load();
      });
    }
  }

  Future<void> _addLine(dynamic data) async {
    final d = TextEditingController(),
        a = TextEditingController(),
        q = TextEditingController(),
        u = TextEditingController();
    int account = (data.accounts as List<FinancialAccount>).first.id;
    int? client;
    int? project;
    int? mixer;
    final line = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
                    title: const Text('Add Expense Line'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: d,
                          decoration: const InputDecoration(
                              labelText: 'Item / description')),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                          initialValue: account,
                          decoration: const InputDecoration(
                              labelText: 'Expense category'),
                          items: (data.accounts as List<FinancialAccount>)
                              .map((x) => DropdownMenuItem(
                                  value: x.id, child: Text(x.name)))
                              .toList(),
                          onChanged: (v) => account = v ?? account),
                      const SizedBox(height: 10),
                      TextField(
                          controller: a,
                          inputFormatters: const [NgnAmountInputFormatter()],
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Line amount (₦)')),
                      const SizedBox(height: 10),
                      TextField(
                          controller: q,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Quantity (optional)')),
                      const SizedBox(height: 10),
                      TextField(
                          controller: u,
                          inputFormatters: const [NgnAmountInputFormatter()],
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
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
                            ...(data.clients as List<CehClient>).map((item) =>
                                DropdownMenuItem<int?>(
                                    value: item.id, child: Text(item.name)))
                          ],
                          onChanged: (value) => setLocal(() {
                                client = value;
                                project = null;
                              })),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int?>(
                          key: ValueKey('general-line-project-${client ?? 0}'),
                          initialValue: project,
                          decoration: const InputDecoration(
                              labelText: 'Project (optional)'),
                          items: [
                            const DropdownMenuItem<int?>(
                                value: null, child: Text('Not allocated')),
                            ...(data.projects as List<CehProject>)
                                .where((item) => item.clientId == client)
                                .map((item) => DropdownMenuItem<int?>(
                                    value: item.id, child: Text(item.name)))
                          ],
                          onChanged: client == null
                              ? null
                              : (value) => setLocal(() => project = value)),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int?>(
                          initialValue: mixer,
                          decoration: const InputDecoration(
                              labelText: 'Equipment (optional)'),
                          items: [
                            const DropdownMenuItem<int?>(
                                value: null, child: Text('Not allocated')),
                            ...(data.mixers as List<Map<String, dynamic>>).map(
                                (item) => DropdownMenuItem<int?>(
                                    value: (item['id'] as num).toInt(),
                                    child: Text(
                                        '${item['code'] ?? item['name'] ?? item['id']}')))
                          ],
                          onChanged: (value) => mixer = value)
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Back')),
                      FilledButton(
                          onPressed: () {
                            final amount = parseNgnInput(a.text);
                            if (amount == null || d.text.trim().isEmpty) return;
                            Navigator.pop(context, {
                              'description': d.text.trim(),
                              'amount': amount,
                              'expense_account_id': account,
                              if (q.text.trim().isNotEmpty)
                                'quantity': q.text.trim(),
                              if (u.text.trim().isNotEmpty)
                                'unit_price': parseNgnInput(u.text),
                              if (client != null) 'client_id': client,
                              if (project != null) 'project_id': project,
                              if (mixer != null) 'mixer_id': mixer,
                            });
                          },
                          child: const Text('Add Line'))
                    ])));
    d.dispose();
    a.dispose();
    q.dispose();
    u.dispose();
    if (line != null && mounted) setState(() => _lines.add(line));
  }

  Future<void> _save(bool submit) async {
    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'bank_account_id': _bank,
        'expense_date': _date,
        'amount': parseNgnInput(_total.text),
        'supplier_id': _supplier,
        if (_oneOff) 'one_off_payee': _oneOffPayee.text,
        'description': _description.text,
        'bank_reference': _bankReference.text,
        'lines': _lines,
        if (_noReceipt) 'no_receipt_reason': _noReceiptReason.text,
        if (widget.statement != null) 'statement_row_id': widget.statement!.id
      };
      final CreatedPettyCashExpense created;
      if (widget.expense == null) {
        created = await _api.createGeneralExpense(widget.session, payload);
      } else {
        final id = (widget.expense!['id'] as num).toInt();
        await _api.updateGeneralExpense(widget.session, id, payload);
        created = CreatedPettyCashExpense(
            id: id, reference: '${widget.expense!['reference_no']}');
      }
      if (_receipt != null) {
        final bytes = await _receipt!.readAsBytes();
        await _api.uploadFinancialEvidence(widget.session,
            sourceType: 'GENERAL_EXPENSE',
            sourceRecordId: created.id,
            filename: _receipt!.name,
            mimeType: _receipt!.name.toLowerCase().endsWith('.png')
                ? 'image/png'
                : 'image/jpeg',
            bytes: bytes);
      }
      if (submit) await _api.submitGeneralExpense(widget.session, created.id);
      if (mounted) {
        await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
                    title: Text(created.reference),
                    content: Text(submit
                        ? 'Submitted for explicit approval.'
                        : 'Saved as Draft.'),
                    actions: [
                      FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Done'))
                    ]));
        if (mounted) Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Bank-Paid Expense',
              style: TextStyle(fontWeight: FontWeight.w900)),
          actions: cehHomeAction(context)),
      body: FutureBuilder(
          future: _lookups,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final x = snapshot.data!;
            if (x.banks.isEmpty || x.accounts.isEmpty) {
              return const Center(
                  child: Text('Bank and expense accounts are required.'));
            }
            _bank ??= x.banks.first.id;
            return ListView(padding: const EdgeInsets.all(18), children: [
              const AccountsSectionTitle('Expense header',
                  subtitle: 'CEH-EX reference is issued server-side'),
              TextFormField(
                  initialValue: widget.expense?['reference_no']?.toString() ??
                      'Issued automatically after creation',
                  enabled: false,
                  decoration:
                      const InputDecoration(labelText: 'CEH reference')),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                  initialValue: _bank,
                  decoration: const InputDecoration(labelText: 'Paid From'),
                  items: x.banks
                      .map((b) =>
                          DropdownMenuItem(value: b.id, child: Text(b.name)))
                      .toList(),
                  onChanged:
                      widget.statement == null ? (v) => _bank = v : null),
              const SizedBox(height: 10),
              AccountsDatePickerField(
                  initialCanonicalDate: _date, onChanged: (v) => _date = v),
              const SizedBox(height: 10),
              TextField(
                  controller: _total,
                  inputFormatters: const [NgnAmountInputFormatter()],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Header total (₦)')),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                  initialValue: _supplier,
                  decoration:
                      const InputDecoration(labelText: 'Supplier / Paid To'),
                  items: x.suppliers
                      .where((s) => s.isActive)
                      .map((s) => DropdownMenuItem<int?>(
                          value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: _oneOff ? null : (v) => _supplier = v),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _oneOff,
                  title: const Text('One-off / Other Payee'),
                  subtitle: const Text(
                      'Admin-only; does not create a Supplier Master record'),
                  onChanged: (value) => setState(() {
                        _oneOff = value ?? false;
                        if (_oneOff) _supplier = null;
                      })),
              if (_oneOff)
                TextField(
                    controller: _oneOffPayee,
                    decoration:
                        const InputDecoration(labelText: 'One-off payee name')),
              TextButton.icon(
                  onPressed: _newSupplier,
                  icon: const Icon(Icons.add_business),
                  label: const Text('Create Supplier Inline')),
              TextField(
                  controller: _description,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Overall description / notes')),
              const SizedBox(height: 10),
              TextField(
                  controller: _bankReference,
                  enabled: widget.statement == null,
                  decoration: const InputDecoration(
                      labelText: 'Zenith reference (optional)')),
              const SizedBox(height: 18),
              const AccountsSectionTitle('Expense lines',
                  subtitle: 'Line amounts must equal the header total'),
              for (var i = 0; i < _lines.length; i++)
                Card(
                    child: ListTile(
                        title: Text('${i + 1}. ${_lines[i]['description']}'),
                        subtitle: Text(formatNaira(
                            (_lines[i]['amount'] as num).toDouble())),
                        trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () =>
                                setState(() => _lines.removeAt(i))))),
              OutlinedButton.icon(
                  onPressed: () => _addLine(x),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Expense Line')),
              const SizedBox(height: 18),
              const AccountsSectionTitle('Receipt / Invoice'),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                    onPressed: _noReceipt
                        ? null
                        : () async {
                            final f = await _picker.pickImage(
                                source: ImageSource.camera);
                            if (f != null) setState(() => _receipt = f);
                          },
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Take Photo')),
                OutlinedButton.icon(
                    onPressed: _noReceipt
                        ? null
                        : () async {
                            final f = await _picker.pickImage(
                                source: ImageSource.gallery);
                            if (f != null) setState(() => _receipt = f);
                          },
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose Existing Photo'))
              ]),
              CheckboxListTile(
                  value: _noReceipt,
                  title: const Text('No Receipt / Document'),
                  onChanged: (v) => setState(() => _noReceipt = v ?? false)),
              if (_noReceipt)
                TextField(
                    controller: _noReceiptReason,
                    decoration: const InputDecoration(
                        labelText: 'Reason (required at Submit)')),
              const SizedBox(height: 10),
              TextFormField(
                  initialValue: widget.session.user.fullName,
                  enabled: false,
                  decoration: const InputDecoration(labelText: 'Entered by')),
              const SizedBox(height: 16),
              Wrap(spacing: 10, children: [
                OutlinedButton.icon(
                    onPressed: _saving ? null : () => _save(false),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save Draft')),
                FilledButton.icon(
                    onPressed: _saving ? null : () => _save(true),
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Submit Expense'))
              ])
            ]);
          }));
}
