import 'package:ceh/core/view_mode.dart';
import 'package:ceh/models/mixer_context.dart';
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
const assignment = MixerAssignment(
    clientId: 4,
    clientName: 'ABC Construction',
    projectId: 9,
    projectName: 'Badagry Site',
    isActive: true);
const allocated = MixerContext(
    id: 306,
    code: '306',
    name: 'Mixer 306',
    activeAssignments: [assignment],
    assignmentHistory: [assignment]);
const unassigned = MixerContext(
    id: 808,
    code: '808',
    name: 'Mixer 808',
    activeAssignments: [],
    assignmentHistory: []);

Widget app(CehSession session,
    {bool viewAsOperator = false,
    Widget? home,
    List<MixerContext> mixers = const [allocated, unassigned]}) {
  final controller = CehViewModeController();
  if (viewAsOperator) controller.enableOperatorView();
  return CehViewModeScope(
      controller: controller,
      child: MaterialApp(
          home: home ??
              ConcreteOperationsScreen(
                  session: session, initialMixers: mixers)));
}

void main() {
  test('mixer context exposes one operational current assignment', () {
    expect(allocated.isOperational, isTrue);
    expect(allocated.assignment?.projectName, 'Badagry Site');
    expect(unassigned.isOperational, isFalse);
    const conflict = MixerContext(
        id: 1,
        code: '1',
        name: 'Conflict',
        activeAssignments: [assignment, assignment],
        assignmentHistory: []);
    expect(conflict.hasAssignmentConflict, isTrue);
    expect(conflict.assignment, isNull);
  });

  testWidgets('Admin sees allocated and unassigned mixer cards',
      (tester) async {
    await tester.pumpWidget(app(admin));
    expect(find.text('MIXERS'), findsOneWidget);
    expect(find.text('MIXER 306'), findsOneWidget);
    expect(find.text('MIXER 808'), findsOneWidget);
    expect(find.text('ABC Construction\nBadagry Site'), findsOneWidget);
    expect(find.text('Not Assigned'), findsOneWidget);
    expect(find.byTooltip('Client and Project Management'), findsOneWidget);
  });

  testWidgets('Operator and View-as-Operator hide unassigned mixers',
      (tester) async {
    await tester.pumpWidget(app(operator));
    expect(find.text('MIXER 306'), findsOneWidget);
    expect(find.text('MIXER 808'), findsNothing);
    expect(find.byTooltip('Client and Project Management'), findsNothing);
    await tester.pumpWidget(app(admin, viewAsOperator: true));
    expect(find.text('MIXER 306'), findsOneWidget);
    expect(find.text('MIXER 808'), findsNothing);
    expect(find.byTooltip('Client and Project Management'), findsNothing);
  });

  testWidgets('mixer submenu preserves context and role actions',
      (tester) async {
    await tester.pumpWidget(app(admin,
        home: const MixerOperationsScreen(session: admin, mixer: allocated)));
    expect(find.text('MIXER 306'), findsWidgets);
    expect(find.text('ABC Construction • Badagry Site'), findsOneWidget);
    expect(find.text('Client / Project'), findsOneWidget);
    expect(find.text('Calibration'), findsOneWidget);
    expect(find.text('Mix Designs'), findsOneWidget);
    expect(find.text('Mix Design Settings'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Production'), 150);
    expect(find.text('Production'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Settings History'), 150);
    expect(find.text('Settings History'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(app(operator,
        home:
            const MixerOperationsScreen(session: operator, mixer: allocated)));
    expect(find.text('Mixer Settings'), findsOneWidget);
    expect(find.text('Mix Design Settings'), findsNothing);
    expect(find.text('View current assignment'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Production'), 150);
    expect(find.text('Settings History'), findsNothing);
  });
}
