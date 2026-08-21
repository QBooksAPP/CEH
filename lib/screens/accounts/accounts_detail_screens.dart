import 'package:flutter/material.dart';

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
        title: 'Billing',
        children: [
          const AccountsSectionTitle('Ready to Invoice',
              subtitle:
                  'Signed production grouped for future QuickBooks invoicing'),
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
          const AccountsSectionTitle('QuickBooks Invoices',
              subtitle:
                  'Mock external invoice status—no QuickBooks connection'),
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
                    '${invoice.client}\n${invoice.project} • ${invoice.date}'),
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
                subtitle: Text('${expense.category} • ${expense.date}'),
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
              const TextField(
                  decoration: InputDecoration(
                      labelText: 'Date',
                      suffixIcon: Icon(Icons.calendar_today_outlined))),
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
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'Amount (₦)')),
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

class PettyCashPrototypeScreen extends StatelessWidget {
  const PettyCashPrototypeScreen({super.key, required this.session});
  final CehSession session;

  void _add(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
            padding: EdgeInsets.fromLTRB(
                18, 18, 18, MediaQuery.viewInsetsOf(context).bottom + 24),
            child: const Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Add Petty Cash Transaction',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              SizedBox(height: 14),
              TextField(
                  decoration: InputDecoration(labelText: 'Cash In / Cash Out')),
              SizedBox(height: 12),
              TextField(decoration: InputDecoration(labelText: 'Amount (₦)')),
              SizedBox(height: 12),
              TextField(decoration: InputDecoration(labelText: 'Description')),
              SizedBox(height: 16),
              PrototypeBanner(),
            ]),
          ));

  @override
  Widget build(BuildContext context) => _AccountsPage(
        session: session,
        title: 'Petty Cash',
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _add(context),
            icon: const Icon(Icons.add),
            label: const Text('Add Transaction')),
        children: [
          const AccountsSectionTitle('Cash position'),
          AccountsResponsiveGrid(
            mobileColumns: 2,
            tabletColumns: 4,
            desktopColumns: 4,
            childAspectRatio: 1.25,
            children: const [
              AccountsSummaryCard(
                  label: 'Opening Balance',
                  value: 300000,
                  detail: 'Start of August',
                  icon: Icons.lock_open_outlined),
              AccountsSummaryCard(
                  label: 'Cash In',
                  value: 750000,
                  detail: 'August inflows',
                  icon: Icons.south_west),
              AccountsSummaryCard(
                  label: 'Cash Out',
                  value: 592500,
                  detail: 'August payments',
                  icon: Icons.north_east),
              AccountsSummaryCard(
                  label: 'Current Balance',
                  value: 457500,
                  detail: 'Mock available cash',
                  icon: Icons.account_balance_wallet_outlined,
                  emphasized: true),
            ],
          ),
          const SizedBox(height: 22),
          const AccountsSectionTitle('Transaction history'),
          for (final entry in AccountsMockData.pettyCash)
            Card(
                child: ListTile(
              leading: CircleAvatar(
                  child:
                      Icon(entry.type == 'Cash In' ? Icons.add : Icons.remove)),
              title: Text(entry.description,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${entry.date} • ${entry.type}'),
              trailing: Text(formatNaira(entry.amount),
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: entry.type == 'Cash In'
                          ? Colors.green.shade700
                          : Colors.red.shade700)),
            )),
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
            childAspectRatio: 1.1,
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

class QuickBooksPrototypeScreen extends StatelessWidget {
  const QuickBooksPrototypeScreen({super.key, required this.session});
  final CehSession session;
  @override
  Widget build(BuildContext context) => _AccountsPage(
        session: session,
        title: 'QuickBooks',
        children: [
          const AccountsSectionTitle('Integration status',
              subtitle: 'Visual status only—QuickBooks is not connected'),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    const Icon(Icons.sync_lock_outlined, size: 52),
                    const SizedBox(height: 10),
                    const AccountsStatusChip('Not Connected'),
                    const SizedBox(height: 14),
                    const AccountsMetricLine('Last Sync', 'Never'),
                    const AccountsMetricLine(
                        'Customers Matched / Unmatched', '0 / 12'),
                    const AccountsMetricLine(
                        'Invoices Synced / Pending', '0 / 3'),
                    const AccountsMetricLine(
                        'Expenses Synced / Pending', '0 / 24'),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                        onPressed: null,
                        icon: Icon(Icons.sync),
                        label: Text('Sync Now')),
                    const SizedBox(height: 8),
                    const Text(
                        'QuickBooks integration will be designed and approved separately.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54)),
                  ]))),
        ],
      );
}
