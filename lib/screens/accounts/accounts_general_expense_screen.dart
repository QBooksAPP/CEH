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
  final _bankReference = TextEditingController();
  final _oneOffPayee = TextEditingController();
  final _noReceiptReason = TextEditingController();
  final List<_ExpenseLineDraft> _lines = [];
  late Future<_GeneralExpenseLookups> _lookups;
  int? _bank, _supplier;
  String _date = canonicalAccountsDate(DateTime.now());
  bool _oneOff = false, _bankCharge = false, _noReceipt = false;
  bool _saving = false;
  XFile? _receipt;

  double get _headerTotal =>
      _lines.fold(0, (sum, line) => sum + (line.total ?? 0));

  @override
  void initState() {
    super.initState();
    final statement = widget.statement;
    if (statement != null) {
      _date = statement.date;
      _bankReference.text = statement.reference;
      _lines.add(_ExpenseLineDraft(
          description: statement.narration,
          totalText: statement.amount.abs().toStringAsFixed(2)));
    }
    final expense = widget.expense;
    if (expense != null) {
      _bank = (expense['bank_account_id'] as num?)?.toInt();
      _supplier = (expense['supplier_id'] as num?)?.toInt();
      final snapshot = '${expense['supplier_name_snapshot'] ?? ''}'.trim();
      _bankCharge = _supplier == null && snapshot.isEmpty;
      _oneOff = !_bankCharge && _supplier == null && snapshot.isNotEmpty;
      if (_oneOff) _oneOffPayee.text = snapshot;
      _date = '${expense['expense_date'] ?? _date}';
      _bankReference.text = '${expense['bank_reference'] ?? ''}';
      _noReceiptReason.text = '${expense['no_receipt_reason'] ?? ''}';
      _noReceipt = _noReceiptReason.text.trim().isNotEmpty;
      _lines
        ..clear()
        ..addAll((expense['lines'] as List? ?? const []).map((item) =>
            _ExpenseLineDraft.fromMap(Map<String, dynamic>.from(item as Map))));
    }
    if (_lines.isEmpty) _lines.add(_ExpenseLineDraft());
    _lookups = _load();
  }

  Future<_GeneralExpenseLookups> _load() async {
    final banks = await _api.bankAccounts(widget.session);
    final suppliers = await _api.expenseSuppliers(widget.session);
    final accounts = (await _api.financialAccounts(widget.session))
        .where((a) => a.accountType == 'EXPENSE' && a.isActive && a.isPostable)
        .toList();
    final clients = await _api.clients(widget.session);
    final projects = (await Future.wait(
            clients.map((client) => _api.projects(widget.session, client.id))))
        .expand((items) => items)
        .toList();
    return _GeneralExpenseLookups(
        banks: banks,
        suppliers: suppliers,
        costCentres: await _api.costCentres(widget.session),
        accounts: accounts,
        clients: clients,
        projects: projects,
        mixers: await _api.mixers(widget.session));
  }

  @override
  void dispose() {
    _bankReference.dispose();
    _oneOffPayee.dispose();
    _noReceiptReason.dispose();
    super.dispose();
  }

  Future<void> _newSupplier() async {
    final name = TextEditingController(),
        contact = TextEditingController(),
        phone = TextEditingController(),
        email = TextEditingController(),
        address = TextEditingController();
    var details = false, creating = false;
    String? error;
    final result = await showDialog<ExpenseSupplier>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
                    title: const Text('New Supplier'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          autofocus: true,
                          decoration: const InputDecoration(
                              labelText: 'Supplier Name')),
                      TextButton(
                          onPressed: () => setLocal(() => details = !details),
                          child: Text(details
                              ? 'Hide optional details'
                              : 'Add optional details')),
                      if (details) ...[
                        TextField(
                            controller: contact,
                            decoration: const InputDecoration(
                                labelText: 'Contact Person')),
                        TextField(
                            controller: phone,
                            decoration:
                                const InputDecoration(labelText: 'Phone')),
                        TextField(
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            decoration:
                                const InputDecoration(labelText: 'Email')),
                        TextField(
                            controller: address,
                            maxLines: 2,
                            decoration:
                                const InputDecoration(labelText: 'Address')),
                      ],
                      if (error != null)
                        Text(error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))
                    ])),
                    actions: [
                      TextButton(
                          onPressed: creating
                              ? null
                              : () => Navigator.pop(dialogContext),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: creating
                              ? null
                              : () async {
                                  if (name.text.trim().isEmpty) {
                                    setLocal(() =>
                                        error = 'Supplier name is required');
                                    return;
                                  }
                                  setLocal(() {
                                    creating = true;
                                    error = null;
                                  });
                                  try {
                                    final supplier = await _api
                                        .createExpenseSupplier(widget.session, {
                                      'canonical_name': name.text.trim(),
                                      if (contact.text.trim().isNotEmpty)
                                        'contact_person': contact.text.trim(),
                                      if (phone.text.trim().isNotEmpty)
                                        'phone': phone.text.trim(),
                                      if (email.text.trim().isNotEmpty)
                                        'email': email.text.trim(),
                                      if (address.text.trim().isNotEmpty)
                                        'address': address.text.trim(),
                                    });
                                    if (dialogContext.mounted) {
                                      Navigator.pop(dialogContext, supplier);
                                    }
                                  } on ApiException catch (e) {
                                    setLocal(() {
                                      creating = false;
                                      error = e.code ==
                                              'SUPPLIER_NAME_OR_ALIAS_CONFLICT'
                                          ? 'A supplier with this name or alias already exists.'
                                          : e.code;
                                    });
                                  }
                                },
                          child: Text(creating ? 'Creating…' : 'Create'))
                    ])));
    for (final controller in [name, contact, phone, email, address]) {
      controller.dispose();
    }
    if (result != null && mounted) {
      setState(() {
        _supplier = result.id;
        _oneOff = false;
        _lookups = _load();
      });
    }
  }

  Future<void> _pickReceipt(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 90);
    if (file != null && mounted) {
      setState(() {
        _receipt = file;
        _noReceipt = false;
      });
    }
  }

  Future<void> _save(bool submit) async {
    setState(() => _saving = true);
    try {
      if (submit &&
          _lines.any(
              (line) => line.costCentreId == null || line.accountId == null)) {
        throw const ApiException('COST_CENTRE_AND_CATEGORY_REQUIRED');
      }
      final lines = _lines
          .where((line) => line.isPersistable)
          .map((line) => line.toPayload())
          .toList();
      final total = lines.fold<double>(
          0, (sum, line) => sum + (line['amount'] as num).toDouble());
      final payload = <String, dynamic>{
        'bank_account_id': _bank,
        'expense_date': _date,
        'amount': total > 0 ? total : null,
        'supplier_id': _bankCharge ? null : _supplier,
        if (!_bankCharge && _oneOff) 'one_off_payee': _oneOffPayee.text,
        'is_bank_charge': _bankCharge,
        'description': lines.isEmpty ? '' : '${lines.first['description']}',
        'bank_reference': _bankReference.text.trim(),
        'lines': lines,
        if (!_bankCharge && _noReceipt)
          'no_receipt_reason': _noReceiptReason.text,
        if (widget.statement != null) 'statement_row_id': widget.statement!.id,
      };
      final CreatedPettyCashExpense saved;
      if (widget.expense == null) {
        saved = await _api.createGeneralExpense(widget.session, payload);
      } else {
        final id = (widget.expense!['id'] as num).toInt();
        await _api.updateGeneralExpense(widget.session, id, payload);
        saved = CreatedPettyCashExpense(
            id: id, reference: '${widget.expense!['reference_no']}');
      }
      if (_receipt != null) {
        final bytes = await _receipt!.readAsBytes();
        await _api.uploadFinancialEvidence(widget.session,
            sourceType: 'GENERAL_EXPENSE',
            sourceRecordId: saved.id,
            filename: _receipt!.name,
            mimeType: _receipt!.name.toLowerCase().endsWith('.png')
                ? 'image/png'
                : 'image/jpeg',
            bytes: bytes);
      }
      if (submit) await _api.submitGeneralExpense(widget.session, saved.id);
      if (mounted) Navigator.pop(context);
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
          title: const Text('New Bank Expense',
              style: TextStyle(fontWeight: FontWeight.w900)),
          actions: cehHomeAction(context,
              canLeave: () => confirmCehDiscardChanges(context))),
      body: FutureBuilder<_GeneralExpenseLookups>(
          future: _lookups,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            if (data.banks.isEmpty ||
                data.accounts.isEmpty ||
                data.costCentres.isEmpty) {
              return const Center(
                  child: Text(
                      'Bank, Cost Centre and expense accounts are required.'));
            }
            _bank ??= data.banks.first.id;
            return ListView(padding: const EdgeInsets.all(18), children: [
              DropdownButtonFormField<int>(
                  initialValue: _bank,
                  decoration: const InputDecoration(labelText: 'Paid From'),
                  items: data.banks
                      .map((bank) => DropdownMenuItem(
                          value: bank.id, child: Text(bank.name)))
                      .toList(),
                  onChanged: widget.statement == null
                      ? (value) => _bank = value
                      : null),
              const SizedBox(height: 12),
              AccountsDatePickerField(
                  initialCanonicalDate: _date,
                  onChanged: (value) => _date = value),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _bankCharge,
                  title: const Text('Bank Charge quick entry'),
                  subtitle: const Text(
                      'For Zenith fees, stamp duty, NIP and alert charges'),
                  onChanged: (value) => setState(() {
                        _bankCharge = value;
                        if (value) {
                          _supplier = null;
                          _oneOff = false;
                          _noReceipt = false;
                          for (final line in _lines) {
                            line.accountId = null;
                          }
                        }
                      })),
              if (!_bankCharge) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                      child: DropdownButtonFormField<int?>(
                          initialValue: _supplier,
                          decoration:
                              const InputDecoration(labelText: 'Paid To'),
                          items: data.suppliers
                              .where((supplier) => supplier.isActive)
                              .map((supplier) => DropdownMenuItem<int?>(
                                  value: supplier.id,
                                  child: Text(supplier.name)))
                              .toList(),
                          onChanged:
                              _oneOff ? null : (value) => _supplier = value)),
                  TextButton.icon(
                      onPressed: _newSupplier,
                      icon: const Icon(Icons.add),
                      label: const Text('New Supplier'))
                ]),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _oneOff,
                    title: const Text('One-off / Other Payee'),
                    onChanged: (value) => setState(() {
                          _oneOff = value ?? false;
                          if (_oneOff) _supplier = null;
                        })),
                if (_oneOff)
                  TextField(
                      controller: _oneOffPayee,
                      decoration:
                          const InputDecoration(labelText: 'Payee name')),
              ],
              TextField(
                  controller: _bankReference,
                  enabled: widget.statement == null,
                  decoration: const InputDecoration(
                      labelText: 'Bank Reference (optional)')),
              const SizedBox(height: 20),
              AccountsSectionTitle('Expense Lines',
                  subtitle: 'Header Total: ${formatNaira(_headerTotal)}'),
              for (var index = 0; index < _lines.length; index++)
                _CompactExpenseLine(
                    key: ValueKey(
                        Object.hash(_lines[index].identity, _bankCharge)),
                    index: index,
                    line: _lines[index],
                    accounts: _bankCharge
                        ? bankChargeExpenseAccounts(data.accounts)
                        : data.accounts,
                    costCentres: data.costCentres,
                    clients: data.clients,
                    projects: data.projects,
                    mixers: data.mixers,
                    bankCharge: _bankCharge,
                    onChanged: () => setState(() {}),
                    onRemove: index == 0
                        ? null
                        : () => setState(() => _lines.removeAt(index))),
              OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _lines.add(_ExpenseLineDraft())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add another line')),
              if (!_bankCharge) ...[
                const SizedBox(height: 20),
                const AccountsSectionTitle('Receipt / Evidence'),
                Wrap(spacing: 8, children: [
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
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Choose File / Photo'))
                ]),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
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
                          labelText: 'No receipt reason')),
              ],
              const SizedBox(height: 20),
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

class _CompactExpenseLine extends StatefulWidget {
  const _CompactExpenseLine(
      {super.key,
      required this.index,
      required this.line,
      required this.accounts,
      required this.costCentres,
      required this.clients,
      required this.projects,
      required this.mixers,
      required this.bankCharge,
      required this.onChanged,
      this.onRemove});
  final int index;
  final _ExpenseLineDraft line;
  final List<FinancialAccount> accounts;
  final List<CostCentre> costCentres;
  final List<CehClient> clients;
  final List<CehProject> projects;
  final List<Map<String, dynamic>> mixers;
  final bool bankCharge;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  @override
  State<_CompactExpenseLine> createState() => _CompactExpenseLineState();
}

class _CompactExpenseLineState extends State<_CompactExpenseLine> {
  late final TextEditingController _description, _quantity, _price, _total;
  @override
  void initState() {
    super.initState();
    _description = TextEditingController(text: widget.line.description);
    _quantity = TextEditingController(text: widget.line.quantityText);
    _price = TextEditingController(text: widget.line.priceText);
    _total = TextEditingController(text: widget.line.totalText);
  }

  @override
  void dispose() {
    for (final controller in [_description, _quantity, _price, _total]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changed() {
    widget.line
      ..description = _description.text
      ..quantityText = _quantity.text
      ..priceText = _price.text;
    final calculated = calculateExpenseLineTotal(_quantity.text, _price.text);
    if (calculated != null) {
      widget.line.totalText = calculated.toStringAsFixed(2);
      _total.text = widget.line.totalText;
    } else {
      widget.line.totalText = _total.text;
    }
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final calculated = widget.line.usesQuantityPrice;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: Text('Line ${widget.index + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                if (widget.onRemove != null)
                  IconButton(
                      onPressed: widget.onRemove,
                      icon: const Icon(Icons.delete_outline))
              ]),
              DropdownButtonFormField<int>(
                  initialValue: widget.line.costCentreId,
                  decoration: const InputDecoration(labelText: 'Cost Centre'),
                  hint: const Text('Select Cost Centre'),
                  items: widget.costCentres
                      .where((centre) => centre.isActive)
                      .map((centre) => DropdownMenuItem(
                          value: centre.id, child: Text(centre.name)))
                      .toList(),
                  onChanged: (value) {
                    widget.line.costCentreId = value;
                    widget.onChanged();
                  }),
              DropdownButtonFormField<int>(
                  initialValue: widget.line.accountId,
                  decoration:
                      const InputDecoration(labelText: 'Account / Category'),
                  hint: const Text('Select Category'),
                  items: widget.accounts
                      .map((account) => DropdownMenuItem(
                          value: account.id,
                          child: Text('${account.code} • ${account.name}')))
                      .toList(),
                  onChanged: (value) {
                    widget.line.accountId = value;
                    widget.onChanged();
                  }),
              TextField(
                  controller: _description,
                  onChanged: (_) => _changed(),
                  decoration: const InputDecoration(labelText: 'Description')),
              if (!widget.bankCharge)
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _quantity,
                          onChanged: (_) => _changed(),
                          decoration: const InputDecoration(
                              labelText: 'Qty (optional)'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: _price,
                          onChanged: (_) => _changed(),
                          inputFormatters: const [NgnAmountInputFormatter()],
                          decoration: const InputDecoration(
                              labelText: 'Price (optional)')))
                ]),
              TextField(
                  controller: _total,
                  enabled: !calculated,
                  onChanged: (_) => _changed(),
                  inputFormatters: const [NgnAmountInputFormatter()],
                  decoration: InputDecoration(
                      labelText: calculated ? 'Total (calculated)' : 'Total')),
              if (!widget.bankCharge) ...[
                DropdownButtonFormField<int?>(
                    initialValue: widget.line.clientId,
                    decoration: const InputDecoration(
                        labelText: 'Client / Project (optional)'),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('Not allocated')),
                      ...widget.clients.map((client) => DropdownMenuItem<int?>(
                          value: client.id, child: Text(client.name)))
                    ],
                    onChanged: (value) => setState(() {
                          widget.line.clientId = value;
                          widget.line.projectId = null;
                          widget.onChanged();
                        })),
                DropdownButtonFormField<int?>(
                    key: ValueKey('line-project-${widget.line.clientId}'),
                    initialValue: widget.line.projectId,
                    decoration:
                        const InputDecoration(labelText: 'Project (optional)'),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('Not allocated')),
                      ...widget.projects
                          .where((project) =>
                              project.clientId == widget.line.clientId)
                          .map((project) => DropdownMenuItem<int?>(
                              value: project.id, child: Text(project.name)))
                    ],
                    onChanged: widget.line.clientId == null
                        ? null
                        : (value) {
                            widget.line.projectId = value;
                            widget.onChanged();
                          }),
                DropdownButtonFormField<int?>(
                    initialValue: widget.line.mixerId,
                    decoration: const InputDecoration(
                        labelText: 'Equipment (optional)'),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('Not allocated')),
                      ...widget.mixers.map((mixer) => DropdownMenuItem<int?>(
                          value: (mixer['id'] as num).toInt(),
                          child: Text(
                              '${mixer['code'] ?? mixer['name'] ?? mixer['id']}')))
                    ],
                    onChanged: (value) {
                      widget.line.mixerId = value;
                      widget.onChanged();
                    })
              ]
            ])));
  }
}

List<FinancialAccount> bankChargeExpenseAccounts(
    List<FinancialAccount> accounts) {
  final matches = accounts.where((account) {
    final searchable = '${account.code} ${account.name}'.toLowerCase();
    return const [
      'bank',
      'charge',
      'stamp',
      'nip',
      'transfer fee',
      'sms',
      'alert fee',
    ].any(searchable.contains);
  }).toList();
  return matches.isEmpty ? accounts : matches;
}

class _ExpenseLineDraft {
  _ExpenseLineDraft(
      {this.description = '',
      this.quantityText = '',
      this.priceText = '',
      this.totalText = '',
      this.costCentreId,
      this.accountId,
      this.clientId,
      this.projectId,
      this.mixerId});
  factory _ExpenseLineDraft.fromMap(Map<String, dynamic> value) =>
      _ExpenseLineDraft(
          description:
              '${value['item_description'] ?? value['description'] ?? ''}',
          quantityText: '${value['quantity'] ?? ''}',
          priceText: '${value['unit_price'] ?? ''}',
          totalText: '${value['amount'] ?? ''}',
          costCentreId: (value['cost_centre_id'] as num?)?.toInt(),
          accountId: (value['expense_account_id'] as num?)?.toInt(),
          clientId: (value['client_id'] as num?)?.toInt(),
          projectId: (value['project_id'] as num?)?.toInt(),
          mixerId: (value['mixer_id'] as num?)?.toInt());
  final Object identity = Object();
  String description, quantityText, priceText, totalText;
  int? accountId, costCentreId, clientId, projectId, mixerId;
  double? get total => parseNgnInput(totalText);
  bool get usesQuantityPrice =>
      double.tryParse(quantityText.trim()) != null &&
      parseNgnInput(priceText) != null;
  bool get isPersistable =>
      accountId != null &&
      costCentreId != null &&
      description.trim().isNotEmpty &&
      (total ?? 0) > 0;
  Map<String, dynamic> toPayload() => {
        'expense_account_id': accountId,
        'cost_centre_id': costCentreId,
        'description': description.trim(),
        'amount': total,
        if (quantityText.trim().isNotEmpty) 'quantity': quantityText.trim(),
        if (priceText.trim().isNotEmpty) 'unit_price': parseNgnInput(priceText),
        if (clientId != null) 'client_id': clientId,
        if (projectId != null) 'project_id': projectId,
        if (mixerId != null) 'mixer_id': mixerId,
      };
}

class _GeneralExpenseLookups {
  const _GeneralExpenseLookups(
      {required this.banks,
      required this.suppliers,
      required this.costCentres,
      required this.accounts,
      required this.clients,
      required this.projects,
      required this.mixers});
  final List<CehBankAccount> banks;
  final List<ExpenseSupplier> suppliers;
  final List<CostCentre> costCentres;
  final List<FinancialAccount> accounts;
  final List<CehClient> clients;
  final List<CehProject> projects;
  final List<Map<String, dynamic>> mixers;
}
