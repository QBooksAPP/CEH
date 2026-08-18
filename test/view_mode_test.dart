import 'package:ceh/core/view_mode.dart';
import 'package:ceh/models/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const adminSession = CehSession(
  token: 'test-token',
  tokenType: 'Bearer',
  expiresAt: '',
  user: CehUser(
    id: 1,
    fullName: 'Admin',
    email: 'admin@example.test',
    role: 'ADMIN',
    isActive: true,
  ),
);

void main() {
  testWidgets('view as Operator hides Admin UI and return restores it',
      (tester) async {
    final controller = CehViewModeController();
    await tester.pumpWidget(MaterialApp(
      home: CehViewModeScope(
        controller: controller,
        child: Builder(builder: (context) {
          return Text(isUiAdmin(context, adminSession) ? 'ADMIN' : 'OPERATOR');
        }),
      ),
    ));

    expect(find.text('ADMIN'), findsOneWidget);
    controller.enableOperatorView();
    await tester.pump();
    expect(find.text('OPERATOR'), findsOneWidget);
    expect(adminSession.user.role, 'ADMIN');
    expect(adminSession.token, 'test-token');

    controller.returnToAdmin();
    await tester.pump();
    expect(find.text('ADMIN'), findsOneWidget);
  });
}
