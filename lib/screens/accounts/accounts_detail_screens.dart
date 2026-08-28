import 'package:flutter/material.dart';

import '../../core/accounts_formatters.dart';
import '../../core/internal_navigation.dart';
import '../../core/view_mode.dart';
import '../../models/accounts_mock_data.dart';
import '../../models/session.dart';
import '../../widgets/accounts_widgets.dart';

class _AccountsPage extends StatelessWidget {
  const _AccountsPage({
    required this.session,
    required this.title,
    required this.children,
    this.floatingActionButton,
  });
  final CehSession session;
  final String title;
  final List<Widget> children;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    if (!isUiAdmin(context, session)) {
      return const Scaffold(
          body: Center(child: Text('Administrator access required.')));
    }
    return Scaffold(
      appBar: AppBar(
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          actions: cehHomeAction(context)),
      floatingActionButton: floatingActionButton,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
        children: [
          const PrototypeBanner(),
          const SizedBox(height: 18),
          ...children
        ],
      ),
    );
  }
}

class BillingPrototypeScreen extends StatelessWidget {
  const BillingPrototypeScreen({super.key, required this.session});
  final CehSession session;

  @override
  Widget build(BuildContext context) => _AccountsPage(
        session: session,
        title: 'Billing & Receivables',
        children: [
          const AccountsSectionTitle('Ready to Invoice',
              subtitle: 'Signed production grouped for future CEH billing'),
          for (final item in AccountsMockData.readyToInvoice)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(item.client,
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900))),
                        AccountsStatusChip(item.status),
                      ]),
                      Text(item.project,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 9),
                      Text(item.references.join(' • ')),
                      const Divider(height: 22),
                      AccountsMetricLine('Total signed production',
                          '${item.totalM3.toStringAsFixed(2)} m³',
                          prominent: true),
                    ]),
              ),
            ),
          const SizedBox(height: 20),
          const AccountsSectionTitle('Receivables',
              subtitle: 'Mock CEH invoice and payment status'),
          for (final invoice in AccountsMockData.invoices)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                title: Row(children: [
                  Expanded(
                      child: Text(invoice.number,
                          style: const TextStyle(fontWeight: FontWeight.w900))),
                  AccountsStatusChip(invoice.status),
                ]),
                subtitle: Text(
                    '${invoice.client}\n${invoice.project} • ${displayAccountsDate(invoice.date)}'),
                isThreeLine: true,
                trailing: Text(formatNaira(invoice.amount),
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
        ],
      );
}

class ExpensesPrototypeScreen extends StatelessWidget {
  const ExpensesPrototypeScreen({super.key, required this.session});
  final CehSession session;

  @override
  Widget build(BuildContext context) => _AccountsPage(
        session: session,
        title: 'Expenses',
        floatingActionButton: FloatingActionButton.extended(
          key: const ValueKey('add-expense'),
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AddExpensePrototypeScreen(session: session))),
          icon: const Icon(Icons.add),
          label: const Text('Add Expense'),
        ),
        children: [
          const AccountsSectionTitle('Expense register',
              subtitle: 'Approval, allocation and receipt visibility'),
          for (final expense in AccountsMockData.expenses)
            Card(
              child: ExpansionTile(
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                title: Row(children: [
                  Expanded(
                      child: Text(expense.supplier,
                          style: const TextStyle(fontWeight: FontWeight.w900))),
                  Text(formatNaira(expense.amount),
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ]),
                subtitle: Text(
                    '${expense.category} • ${displayAccountsDate(expense.date)}'),
                children: [
                  AccountsMetricLine('Project', expense.project),
                  AccountsMetricLine('Equipment', expense.equipment),
                  AccountsMetricLine('Payment method', expense.paymentMethod),
                  AccountsMetricLine(
                      'Receipt', expense.hasReceipt ? 'Attached' : 'Missing'),
                  Align(
                      alignment: Alignment.centerRight,
                      child: AccountsStatusChip(expense.status)),
                ],
              ),
            ),
        ],
      );
}

class AddExpensePrototypeScreen extends StatefulWidget {
  const AddExpensePrototypeScreen({super.key, required this.session});
  final CehSession session;
  @override
  State<AddExpensePrototypeScreen> createState() =>
      _AddExpensePrototypeScreenState();
}

class _AddExpensePrototypeScreenState extends State<AddExpensePrototypeScreen> {
  final _form = GlobalKey<FormState>();
  String _date = canonicalAccountsDate(DateTime.now());
  String? _supplier;
  String? _category;
  String? _payment;

  @override
  Widget build(BuildContext context) => _AccountsPage(
        session: widget.session,
        title: 'Add Expense',
        children: [
          const AccountsSectionTitle('Expense details',
              subtitle: 'UI preview—entries are not saved'),
          Form(
            key: _form,
            child: Column(children: [
              AccountsDatePickerField(
                  initialCanonicalDate: _date,
                  onChanged: (value) => _date = value),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _supplier,
                decoration: const InputDecoration(labelText: 'Supplier'),
                items: AccountsMockData.suppliers
                    .where((s) => s.isActive)
                    .map((s) =>
                        DropdownMenuItem(value: s.name, child: Text(s.name)))
                    .toList(),
                onChanged: (value) => setState(() => _supplier = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: const [
                  'Diesel',
                  'Repairs & Parts',
                  'Labour',
                  'Transport',
                  'Other'
                ]
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (value) => setState(() => _category = value),
              ),
              const SizedBox(height: 12),
              const TextField(
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [NgnAmountInputFormatter()],
                  decoration: InputDecoration(labelText: 'Amount')),
              const SizedBox(height: 12),
              const TextField(
                  maxLines: 3,
                  decoration: InputDecoration(labelText: 'Description')),
              const SizedBox(height: 12),
              const TextField(
                  decoration: InputDecoration(
                      labelText: 'Client / Project allocation')),
              const SizedBox(height: 12),
              const TextField(
                  decoration:
                      InputDecoration(labelText: 'Equipment allocation')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _payment,
                decoration: const InputDecoration(labelText: 'Payment method'),
                items: const ['Bank Transfer', 'Cash', 'Petty Cash', 'Card']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (value) => setState(() => _payment = value),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Attach Receipt (prototype)')),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Prototype only—expense was not saved.'))),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Preview Expense'),
              ),
            ]),
          ),
        ],
      );
}

class ProjectCostingPrototypeScreen extends StatelessWidget {
  const ProjectCostingPrototypeScreen({super.key, required this.session});
  final CehSession session;
  @override
  Widget build(BuildContext context) => _AccountsPage(
        session: session,
        title: 'Projects / Job Costing',
        children: [
          const AccountsSectionTitle('Project performance',
              subtitle: 'Production, cost and contribution overview'),
          AccountsResponsiveGrid(
            tabletColumns: 2,
            desktopColumns: 3,
            childAspectRatio: 1.15,
            children: [
              for (final project in AccountsMockData.projects)
                Card(
                    child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ProjectCostDetailPrototypeScreen(
                              session: session, project: project))),
                  child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(project.client,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 17)),
                            Text(project.project),
                            const Spacer(),
                            AccountsMetricLine('Production',
                                '${project.productionM3.toStringAsFixed(0)} m³'),
                            AccountsMetricLine(
                                'Revenue', formatNaira(project.revenue)),
                            AccountsMetricLine(
                                'Total cost', formatNaira(project.totalCost)),
                            const Divider(),
                            AccountsMetricLine('Gross contribution',
                                formatNaira(project.contribution),
                                prominent: true),
                          ])),
                )),
            ],
          ),
        ],
      );
}

class ProjectCostDetailPrototypeScreen extends StatelessWidget {
  const ProjectCostDetailPrototypeScreen(
      {super.key, required this.session, required this.project});
  final CehSession session;
  final ProjectCosting project;
  @override
  Widget build(BuildContext context) => _AccountsPage(
        session: session,
        title: project.project,
        children: [
          AccountsSectionTitle(project.client,
              subtitle: 'Detailed mock job-cost breakdown'),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(children: [
                    AccountsMetricLine('Production',
                        '${project.productionM3.toStringAsFixed(0)} m³'),
                    AccountsMetricLine('Revenue / billed amount',
                        formatNaira(project.revenue)),
                    const Divider(),
                    AccountsMetricLine('Diesel', formatNaira(project.diesel)),
                    AccountsMetricLine('Repairs', formatNaira(project.repairs)),
                    AccountsMetricLine('Labour', formatNaira(project.labour)),
                    AccountsMetricLine(
                        'Transport', formatNaira(project.transport)),
                    AccountsMetricLine(
                        'Other costs', formatNaira(project.other)),
                    const Divider(),
                    AccountsMetricLine(
                        'Total cost', formatNaira(project.totalCost),
                        prominent: true),
                    AccountsMetricLine(
                        'Gross contribution', formatNaira(project.contribution),
                        prominent: true),
                  ]))),
        ],
      );
}

class EquipmentCostingPrototypeScreen extends StatelessWidget {
  const EquipmentCostingPrototypeScreen({super.key, required this.session});
  final CehSession session;
  @override
  Widget build(BuildContext context) => _AccountsPage(
        session: session,
        title: 'Equipment Costing',
        children: [
          const AccountsSectionTitle('Equipment profitability',
              subtitle: 'Mixer-first cards with supporting equipment'),
          AccountsResponsiveGrid(
            tabletColumns: 2,
            desktopColumns: 3,
            childAspectRatio: .9,
            children: [
              for (final equipment in AccountsMockData.equipment)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                CircleAvatar(
                                    child: Text(equipment.name.split(' ').first,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900))),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(equipment.name,
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900)),
                                      Text(equipment.type),
                                    ])),
                              ]),
                              const Spacer(),
                              AccountsMetricLine(
                                  'Revenue', formatNaira(equipment.revenue)),
                              AccountsMetricLine(
                                  'Diesel', formatNaira(equipment.diesel)),
                              AccountsMetricLine(
                                  'Repairs', formatNaira(equipment.repairs)),
                              AccountsMetricLine(
                                  'Parts', formatNaira(equipment.parts)),
                              AccountsMetricLine(
                                  'Labour', formatNaira(equipment.labour)),
                              AccountsMetricLine('Total Cost',
                                  formatNaira(equipment.totalCost)),
                              const Divider(),
                              AccountsMetricLine('Profitability',
                                  formatNaira(equipment.profitability),
                                  prominent: true),
                            ]))),
            ],
          ),
        ],
      );
}

class SuppliersPrototypeScreen extends StatelessWidget {
  const SuppliersPrototypeScreen({super.key, required this.session});
  final CehSession session;
  @override
  Widget build(BuildContext context) => _AccountsPage(
        session: session,
        title: 'Suppliers',
        floatingActionButton: FloatingActionButton.extended(
            key: const ValueKey('add-supplier'),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        AddSupplierPrototypeScreen(session: session))),
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Add Supplier')),
        children: [
          const AccountsSectionTitle('Supplier directory'),
          for (final supplier in AccountsMockData.suppliers)
            Card(
                child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading:
                  const CircleAvatar(child: Icon(Icons.storefront_outlined)),
              title: Row(children: [
                Expanded(
                    child: Text(supplier.name,
                        style: const TextStyle(fontWeight: FontWeight.w900))),
                AccountsStatusChip(supplier.isActive ? 'Active' : 'Inactive'),
              ]),
              subtitle: Text('${supplier.category}\n${supplier.contact}'),
              isThreeLine: true,
              trailing: Text(formatNaira(supplier.totalSpend),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            )),
        ],
      );
}

class AddSupplierPrototypeScreen extends StatelessWidget {
  const AddSupplierPrototypeScreen({super.key, required this.session});
  final CehSession session;
  @override
  Widget build(BuildContext context) => _AccountsPage(
        session: session,
        title: 'Add Supplier',
        children: [
          const AccountsSectionTitle('Supplier details',
              subtitle: 'UI preview—supplier is not saved'),
          const TextField(
              decoration: InputDecoration(labelText: 'Supplier name')),
          const SizedBox(height: 12),
          const TextField(
              decoration: InputDecoration(labelText: 'Category / type')),
          const SizedBox(height: 12),
          const TextField(decoration: InputDecoration(labelText: 'Contact')),
          const SizedBox(height: 12),
          const TextField(
              decoration: InputDecoration(labelText: 'Reference / notes'),
              maxLines: 3),
          const SizedBox(height: 18),
          FilledButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Prototype only—supplier was not saved.'))),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview Supplier')),
        ],
      );
}

class ReportsPrototypeScreen extends StatelessWidget {
  const ReportsPrototypeScreen({super.key, required this.session});
  final CehSession session;
  static const reports = [
    ('Receivables', Icons.request_quote_outlined),
    ('Expenses by Month', Icons.calendar_month_outlined),
    ('Expenses by Category', Icons.donut_large_outlined),
    ('Project Profitability', Icons.business_center_outlined),
    ('Equipment Profitability', Icons.precision_manufacturing_outlined),
    ('Supplier Spend', Icons.local_shipping_outlined),
    ('Petty Cash', Icons.account_balance_wallet_outlined),
    ('Billing Status', Icons.receipt_long_outlined),
  ];
  @override
  Widget build(BuildContext context) => _AccountsPage(
        session: session,
        title: 'Reports',
        children: [
          const AccountsSectionTitle('Management reports',
              subtitle: 'Report destinations for the future Accounts backend'),
          AccountsResponsiveGrid(
              tabletColumns: 2,
              desktopColumns: 3,
              childAspectRatio: 2.3,
              children: [
                for (final report in reports)
                  AccountsMenuCard(
                      title: report.$1,
                      subtitle: 'Prototype report • calculations not connected',
                      icon: report.$2,
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('${report.$1} is a prototype.')))),
              ]),
        ],
      );
}
