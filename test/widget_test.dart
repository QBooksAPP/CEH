import 'package:flutter_test/flutter_test.dart';
import 'package:qbook/main.dart';

void main() {
  testWidgets('QBook launches', (tester) async {
    await tester.pumpWidget(const QBookApp());
    await tester.pumpAndSettle();
    expect(find.text('QBook'), findsOneWidget);
    expect(find.text('NEXT REFERENCE'), findsOneWidget);
  });
}
