import 'dart:io';

import 'package:ceh/core/ceh_theme.dart';
import 'package:ceh/core/view_mode.dart';
import 'package:ceh/models/accounts_mock_data.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/accounts_home_screen.dart';
import 'package:ceh/screens/accounts/accounts_phase1_screens.dart';
import 'package:ceh/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const adminSession = CehSession(
  token: 'test',
  tokenType: 'Bearer',
  expiresAt: '',
  user: CehUser(
    id: 1,
    fullName: 'Admin User',
    email: 'admin@example.test',
    role: 'ADMIN',
    isActive: true,
  ),
);

const operatorSession = CehSession(
  token: 'test',
  tokenType: 'Bearer',
  expiresAt: '',
  user: CehUser(
    id: 2,
    fullName: 'Operator User',
    email: '',
    role: 'OPERATOR',
    isActive: true,
  ),
);

Widget app(Widget home, {bool viewAsOperator = false}) {
  final controller = CehViewModeController();
  if (viewAsOperator) controller.enableOperatorView();
  return CehViewModeScope(
    controller: controller,
    child: MaterialApp(theme: CehTheme.light(), home: home),
  );
}

DashboardScreen dashboard(CehSession session) => DashboardScreen(
      session: session,
      checkForUpdates: false,
      onLogout: () async {},
    );

void main() {
  testWidgets('Accounts is visible to Admin on the company dashboard',
      (tester) async {
    await tester.pumpWidget(app(dashboard(adminSession)));
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('COMING SOON'), findsOneWidget);
  });

  testWidgets('Accounts is hidden from Operator and Admin View-as-Operator',
      (tester) async {
    await tester.pumpWidget(app(dashboard(operatorSession)));
    expect(find.text('Accounts'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(app(dashboard(adminSession), viewAsOperator: true));
    expect(find.text('Accounts'), findsNothing);
  });

  testWidgets('Accounts screen independently enforces Admin UI access',
      (tester) async {
    await tester.pumpWidget(app(
        const AccountsHomeScreen(session: operatorSession, liveData: false)));
    expect(find.text('Administrator access required.'), findsOneWidget);
    expect(find.text('Financial overview'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(app(
        const AccountsHomeScreen(session: adminSession, liveData: false),
        viewAsOperator: true));
    expect(find.text('Administrator access required.'), findsOneWidget);
  });

  testWidgets('Accounts dashboard summary cards and all menu areas render',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        app(const AccountsHomeScreen(session: adminSession, liveData: false)));

    for (final label in [
      'Cash / Bank',
      'Receivables',
      'Expenses This Month',
      'Net Operating Position',
      'Banking',
      'Billing & Receivables',
      'Expenses',
      'Petty Cash',
      'Payroll',
      'Projects / Job Costing',
      'Equipment Costing',
      'Suppliers',
      'Reports',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('QuickBooks'), findsNothing);
    expect(find.text('Prototype • sample data only'), findsOneWidget);
  });

  testWidgets('Accounts dashboard remains usable at Android phone width',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        app(const AccountsHomeScreen(session: adminSession, liveData: false)));
    expect(find.text('Cash / Bank'), findsOneWidget);
    final reports = find.byKey(const ValueKey('accounts-menu-reports'));
    await tester.scrollUntilVisible(reports, 300,
        scrollable: find.byType(Scrollable).first);
    expect(reports, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigation opens every Accounts prototype area', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        app(const AccountsHomeScreen(session: adminSession, liveData: false)));

    const destinations = <String, String>{
      'banking': 'Bank accounts',
      'billing-receivables': 'Ready to Invoice',
      'expenses': 'Expense register',
      'petty-cash': 'TOTAL PETTY CASH',
      'payroll': 'Payroll foundation',
      'projects-job-costing': 'Project performance',
      'equipment-costing': 'Equipment profitability',
      'suppliers': 'Supplier directory',
      'reports': 'Management reports',
    };
    for (final entry in destinations.entries) {
      final menu = find.byKey(ValueKey('accounts-menu-${entry.key}'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget,
          reason: 'Failed to open ${entry.key}');
      expect(find.text('Prototype • sample data only'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  test('Accounts prototype has no backend or QuickBooks client dependency', () {
    final files = [
      'lib/screens/accounts/accounts_home_screen.dart',
      'lib/screens/accounts/accounts_detail_screens.dart',
      'lib/screens/accounts/accounts_phase1_screens.dart',
      'lib/models/accounts_mock_data.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');
    expect(files, isNot(contains('CehApiClient')));
    expect(files, isNot(contains('package:http')));
    expect(files, isNot(contains('quickbooks.com')));
  });

  test('pending petty cash expense reserves available custodian balance', () {
    final segun = AccountsMockData.pettyCashCustodians
        .singleWhere((item) => item.name == 'Segun');
    expect(segun.balance, 110000);
    expect(segun.pendingApproval, 30000);
    expect(segun.availableBalance, 80000);
    expect(
      AccountsMockData.pettyCashCustodians
          .fold<double>(0, (sum, item) => sum + item.balance),
      175000,
    );
  });

  testWidgets('Banking demonstrates matching and duplicate states',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(app(const BankingPrototypeScreen(session: adminSession)));
    expect(find.text('Zenith Bank'), findsOneWidget);
    expect(find.text('Potential Match'), findsOneWidget);
    expect(find.text('Possible Duplicate'), findsOneWidget);
    final importButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('import-bank-statement')));
    expect(importButton.onPressed, isNull);
  });

  testWidgets('Petty Cash uses independent custodians and prototype forms',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        app(const PettyCashCustodianPrototypeScreen(session: adminSession)));
    expect(find.byKey(const ValueKey('custodian-felix')), findsOneWidget);
    expect(find.byKey(const ValueKey('custodian-segun')), findsOneWidget);
    expect(find.text('₦175,000'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fund-petty-cash')));
    await tester.pumpAndSettle();
    expect(find.text('Asset transfer'), findsOneWidget);
    expect(find.text('Admin User'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-petty-cash-expense')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('take-receipt-photo')), findsOneWidget);
    expect(find.byKey(const ValueKey('choose-receipt-photo')), findsOneWidget);
    await tester.tap(find.text('No Receipt'));
    await tester.pump();
    expect(find.byKey(const ValueKey('no-receipt-reason')), findsOneWidget);
  });
}
