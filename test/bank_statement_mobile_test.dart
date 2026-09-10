import 'dart:async';
import 'package:ceh/core/api_client.dart';
import 'package:ceh/core/bank_statement_upload.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/bank_statement_import_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const admin = CehSession(token: 'test', tokenType: 'Bearer', expiresAt: '',
 user: CehUser(id: 1, fullName: 'Admin', email: '', role: 'ADMIN', isActive: true));
class ImportApi extends CehApiClient {
 int uploads = 0, commits = 0;
 bool fail = false, imported = false, blocked = false, stale = false;
 @override
 Future<Map<String,dynamic>> uploadBankStatement(CehSession s, int bank,
 BankStatementFile f, void Function(double) progress) async {
   uploads++; progress(0.5);
   if(fail) throw TimeoutException('test');
   return {'document_id': 4};
 }
 @override
 Future<Map<String,dynamic>> bankingRead(CehSession s, String endpoint, Map<String,String> query) async => {
  'document': {'id': 4,'bank_account_id': 1,'original_filename':'qa.csv'},
  'batch_id': imported ? 2 : null,
  'confirmation_sha256': List.filled(64,'a').join(),
  'summary': {'can_import': !blocked,'invalid_rows': blocked ? 1 : 0,
    'ambiguous_overlap_rows': blocked ? 1 : 0,'total_rows': 4,'debits_count': 3,
    'credits_count': 1,'debits_value':'153.75','credits_value':'500.00',
    'opening_balance':'1000.00','closing_balance':'1346.25','balance_reconciles':true,
    'already_imported_source_rows':imported ? 4 : 0,'statement_from':'2026-09-10',
    'statement_to':'2026-09-10','errors': []},
 };
 @override
 Future<Map<String,dynamic>> confirmBankStatement(CehSession s,int id,String hash) async {
   commits++; if(stale) throw const ApiException('PREVIEW_CHANGED');
   return {'batch_id': 3,'imported':4,'journal_posted':false};
 }
}
void main() {
 final file=BankStatementFile('qa.csv', Uint8List.fromList([1,2,3]));
 Future<void> mount(WidgetTester t, ImportApi api,{Future<BankStatementFile?> Function()? picker}) async {
  await t.pumpWidget(MaterialApp(home: BankStatementImportScreen(session:admin,
    bank:const {'id':1,'name':'Zenith Bank','currency':'NGN'},api:api,picker:picker ?? () async => file)));
  await t.pumpAndSettle();
 }
 Future<void> press(WidgetTester t,String label) async {
   await t.scrollUntilVisible(find.text(label),150,scrollable:find.byType(Scrollable).first);
   await t.tap(find.text(label));await t.pumpAndSettle();
 }
 test('picker returns typed bytes and cancellation through native bridge', () async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel=MethodChannel('com.concreteequipmenthire.ceh/bank_picker');
  final messenger=TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (_) async => {'name':'qa.xlsx','bytes':Uint8List.fromList([1])});
  expect((await pickBankStatement())!.name,'qa.xlsx');
  messenger.setMockMethodCallHandler(channel, (_) async => null);
  expect(await pickBankStatement(),isNull);
  messenger.setMockMethodCallHandler(channel,null);
 });
 test('file types and size are bounded', () {
  for(final name in ['qa.csv','qa.XLSX']) { BankStatementFile(name,Uint8List(1)).validate(); }
  expect(()=>BankStatementFile('bad.exe',Uint8List(1)).validate(),throwsFormatException);
  expect(()=>BankStatementFile('empty.csv',Uint8List(0)).validate(),throwsFormatException);
 });
 testWidgets('picker cancellation has no busy overlay or upload', (t) async {
  final api=ImportApi();final pending=Completer<BankStatementFile?>();
  await mount(t,api,picker:()=>pending.future);await t.tap(find.text('Choose CSV/XLSX'));await t.pump();
  expect(find.byType(LinearProgressIndicator),findsNothing);
  pending.complete(null);await t.pumpAndSettle();expect(api.uploads,0);
 });
 testWidgets('upload preview never auto-imports; explicit confirm succeeds', (t) async {
  final api=ImportApi();await mount(t,api);await press(t,'Choose CSV/XLSX');
  await press(t,'Upload & Preview');expect(api.commits,0);
  await press(t,'Confirm Import');expect(api.commits,1);
  expect(find.text('Statement import completed.'),findsOneWidget);
 });
 testWidgets('timeout retry clears busy and reuses safe upload path', (t) async {
  final api=ImportApi()..fail=true;await mount(t,api);await press(t,'Choose CSV/XLSX');
  await press(t,'Upload & Preview');expect(find.byType(LinearProgressIndicator),findsNothing);
  api.fail=false;await press(t,'Upload & Preview');expect(api.uploads,2);expect(api.commits,0);
 });
 testWidgets('already imported statement has no confirmation action', (t) async {
  final api=ImportApi()..imported=true;await mount(t,api);await press(t,'Choose CSV/XLSX');await press(t,'Upload & Preview');
  expect(find.text('Confirm Import'),findsNothing);expect(api.commits,0);
 });
 testWidgets('ambiguous overlap disables confirmation', (t) async {
  final api=ImportApi()..blocked=true;await mount(t,api);await press(t,'Choose CSV/XLSX');await press(t,'Upload & Preview');
  await t.scrollUntilVisible(find.text('Confirm Import'),150,scrollable:find.byType(Scrollable).first);
  expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,'Confirm Import')).onPressed,isNull);
 });
 testWidgets('stale confirmation removes action until fresh preview', (t) async {
  final api=ImportApi()..stale=true;await mount(t,api);await press(t,'Choose CSV/XLSX');await press(t,'Upload & Preview');await press(t,'Confirm Import');
  expect(find.text('Confirm Import'),findsNothing);expect(find.byType(LinearProgressIndicator),findsNothing);
 });
}
