import 'dart:io';

import 'package:ceh/core/ceh_theme.dart';
import 'package:ceh/core/view_mode.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/accounts_home_screen.dart';
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
    await tester
        .pumpWidget(app(const AccountsHomeScreen(session: operatorSession)));
    expect(find.text('Administrator access required.'), findsOneWidget);
    expect(find.text('Financial overview'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(app(const AccountsHomeScreen(session: adminSession),
        viewAsOperator: true));
    expect(find.text('Administrator access required.'), findsOneWidget);
  });

  testWidgets('Accounts dashboard summary cards and all menu areas render',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(app(const AccountsHomeScreen(session: adminSession)));

    for (final label in [
      'Cash / Bank',
      'Receivables',
      'Expenses This Month',
      'Net Operating Position',
      'Billing',
      'Expenses',
      'Petty Cash',
      'Projects / Job Costing',
      'Equipment Costing',
      'Suppliers',
      'Reports',
      'QuickBooks',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Prototype • sample data only'), findsOneWidget);
  });

  testWidgets('Accounts dashboard remains usable at Android phone width',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(app(const AccountsHomeScreen(session: adminSession)));
    expect(find.text('Cash / Bank'), findsOneWidget);
    final quickBooks = find.byKey(const ValueKey('accounts-menu-quickbooks'));
    await tester.scrollUntilVisible(quickBooks, 300,
        scrollable: find.byType(Scrollable).first);
    expect(quickBooks, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigation opens every Accounts prototype area', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(app(const AccountsHomeScreen(session: adminSession)));

    const destinations = <String, String>{
      'billing': 'Ready to Invoice',
      'expenses': 'Expense register',
      'petty-cash': 'Transaction history',
      'projects-job-costing': 'Project performance',
      'equipment-costing': 'Equipment profitability',
      'suppliers': 'Supplier directory',
      'reports': 'Management reports',
      'quickbooks': 'Integration status',
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
      'lib/models/accounts_mock_data.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');
    expect(files, isNot(contains('CehApiClient')));
    expect(files, isNot(contains('package:http')));
    expect(files, isNot(contains('quickbooks.com')));
  });
}
