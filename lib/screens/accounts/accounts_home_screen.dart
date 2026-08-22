import 'package:flutter/material.dart';

import '../../core/internal_navigation.dart';
import '../../core/view_mode.dart';
import '../../models/accounts_mock_data.dart';
import '../../models/session.dart';
import '../../widgets/accounts_widgets.dart';
import 'accounts_detail_screens.dart';
import 'accounts_live_screens.dart';
import 'accounts_phase1_screens.dart';

class AccountsHomeScreen extends StatelessWidget {
  const AccountsHomeScreen({
    super.key,
    required this.session,
    this.liveData = true,
  });
  final CehSession session;
  final bool liveData;

  @override
  Widget build(BuildContext context) {
    if (!isUiAdmin(context, session)) {
      return const Scaffold(
          body: Center(child: Text('Administrator access required.')));
    }
    final destinations = <_AccountsDestination>[
      _AccountsDestination(
          'Banking',
          'Balances, statements and reconciliation',
          Icons.account_balance_outlined,
          liveData
              ? AccountsBankingScreen(session: session)
              : BankingPrototypeScreen(session: session)),
      _AccountsDestination(
          'Billing & Receivables',
          'Production reports and client balances',
          Icons.receipt_long_outlined,
          BillingPrototypeScreen(session: session)),
      _AccountsDestination(
          'Expenses',
          'Operating costs and receipts',
          Icons.payments_outlined,
          liveData
              ? AccountsExpensesScreen(session: session)
              : ExpensesPrototypeScreen(session: session)),
      _AccountsDestination(
          'Petty Cash',
          'Independent custodian balances',
          Icons.account_balance_wallet_outlined,
          liveData
              ? AccountsPettyCashScreen(session: session)
              : PettyCashCustodianPrototypeScreen(session: session)),
      _AccountsDestination('Payroll', 'Future payroll and staff payments',
          Icons.badge_outlined, PayrollPrototypeScreen(session: session)),
      _AccountsDestination(
          'Projects / Job Costing',
          'Production and project contribution',
          Icons.business_center_outlined,
          ProjectCostingPrototypeScreen(session: session)),
      _AccountsDestination(
          'Equipment Costing',
          'Mixer and equipment profitability',
          Icons.precision_manufacturing_outlined,
          EquipmentCostingPrototypeScreen(session: session)),
      _AccountsDestination(
          'Suppliers',
          'Supplier directory and spend',
          Icons.local_shipping_outlined,
          SuppliersPrototypeScreen(session: session)),
      _AccountsDestination('Reports', 'Management reporting workspace',
          Icons.bar_chart_outlined, ReportsPrototypeScreen(session: session)),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts',
            style: TextStyle(fontWeight: FontWeight.w900)),
        actions: cehHomeAction(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const PrototypeBanner(),
          const SizedBox(height: 18),
          const AccountsSectionTitle('Financial overview',
              subtitle: 'Illustrative figures for layout review'),
          AccountsResponsiveGrid(
            mobileColumns: 1,
            tabletColumns: 2,
            desktopColumns: 4,
            childAspectRatio: 1.4,
            children: [
              for (var i = 0; i < AccountsMockData.summaries.length; i++)
                AccountsSummaryCard(
                  label: AccountsMockData.summaries[i].label,
                  value: AccountsMockData.summaries[i].value,
                  detail: AccountsMockData.summaries[i].detail,
                  emphasized: i == AccountsMockData.summaries.length - 1,
                  icon: const [
                    Icons.account_balance_outlined,
                    Icons.request_quote_outlined,
                    Icons.trending_down,
                    Icons.trending_up,
                  ][i],
                ),
            ],
          ),
          const SizedBox(height: 24),
          const AccountsSectionTitle('Management areas'),
          AccountsResponsiveGrid(
            tabletColumns: 2,
            desktopColumns: 3,
            childAspectRatio: 2.15,
            children: [
              for (final destination in destinations)
                AccountsMenuCard(
                  key: ValueKey(
                      'accounts-menu-${destination.title.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '-').replaceAll(RegExp(r'-$'), '')}'),
                  title: destination.title,
                  subtitle: destination.subtitle,
                  icon: destination.icon,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => destination.screen)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountsDestination {
  const _AccountsDestination(this.title, this.subtitle, this.icon, this.screen);
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget screen;
}
