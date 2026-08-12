import 'package:flutter_test/flutter_test.dart';
import 'package:qbook/main.dart';

void main() {
  testWidgets('QBook launches', (WidgetTester tester) async {
    await tester.pumpWidget(const QBookApp());

    // Allow the initial UI to render without waiting indefinitely
    // for every animation/timer to settle.
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('QBook'), findsWidgets);
  });
}
