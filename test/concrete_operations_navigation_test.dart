import 'package:ceh/core/view_mode.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/concrete_operations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const admin = CehSession(
    token: 't',
    tokenType: 'Bearer',
    expiresAt: '',
    user: CehUser(
        id: 1, fullName: 'Admin', email: 'a@a', role: 'ADMIN', isActive: true));
const operator = CehSession(
    token: 't',
    tokenType: 'Bearer',
    expiresAt: '',
    user: CehUser(
        id: 2,
        fullName: 'Operator',
        email: 'o@a',
        role: 'OPERATOR',
        isActive: true));

Widget app(CehSession session, {bool viewAsOperator = false}) {
  final controller = CehViewModeController();
  if (viewAsOperator) controller.enableOperatorView();
  return CehViewModeScope(
      controller: controller,
      child: MaterialApp(home: ConcreteOperationsScreen(session: session)));
}

void main() {
  testWidgets('operator navigation uses Mixer Settings and hides admin entries',
      (tester) async {
    await tester.pumpWidget(app(operator));
    expect(find.text('CALIBRATION'), findsOneWidget);
    expect(find.text('PRODUCTION'), findsOneWidget);
    expect(find.text('Mixer Settings'), findsOneWidget);
    expect(find.text('Mix Design Settings'), findsNothing);
    expect(find.text('Mix Designs'), findsNothing);
    expect(find.text('Settings History'), findsNothing);
    expect(find.text('Production Log'), findsOneWidget);
  });

  testWidgets('admin retains engineering navigation', (tester) async {
    await tester.pumpWidget(app(admin));
    await tester.scrollUntilVisible(find.text('Settings History'), 200);
    expect(find.text('Mix Design Settings'), findsOneWidget);
    expect(find.text('Mix Designs'), findsOneWidget);
    expect(find.text('Settings History'), findsOneWidget);
  });

  testWidgets('view as operator reproduces operator navigation',
      (tester) async {
    await tester.pumpWidget(app(admin, viewAsOperator: true));
    expect(find.text('Mixer Settings'), findsOneWidget);
    expect(find.text('Mix Design Settings'), findsNothing);
    expect(find.text('Mix Designs'), findsNothing);
  });
}
