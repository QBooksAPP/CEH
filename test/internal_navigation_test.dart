import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ceh/core/internal_navigation.dart';

void main() {
  Widget app({required Widget page}) => MaterialApp(
        home: const Scaffold(body: Center(child: Text('CEH Dashboard'))),
        routes: {'/page': (_) => page},
        initialRoute: '/page',
      );

  testWidgets('Home action is unique and returns directly to dashboard',
      (tester) async {
    await tester.pumpWidget(app(
      page: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            leading: const BackButton(),
            title: const Text('Child page'),
            actions: cehHomeAction(context),
          ),
        ),
      ),
    ));

    expect(find.byKey(const ValueKey('ceh-home-action')), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ceh-home-action')));
    await tester.pumpAndSettle();
    expect(find.text('CEH Dashboard'), findsOneWidget);
    expect(find.text('Child page'), findsNothing);
  });

  testWidgets('Home respects unsaved-form protection', (tester) async {
    var checks = 0;
    await tester.pumpWidget(app(
      page: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Unsaved form'),
            actions: cehHomeAction(
              context,
              canLeave: () async {
                checks += 1;
                return false;
              },
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('ceh-home-action')));
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect(find.text('Unsaved form'), findsOneWidget);
    expect(find.text('CEH Dashboard'), findsNothing);
  });
}
