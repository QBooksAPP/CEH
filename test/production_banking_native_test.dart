import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('banking bridges accept production without opening staging updater', () {
    final source = File(
            'android/app/src/main/kotlin/com/concreteequipmenthire/ceh/MainActivity.kt')
        .readAsStringSync();
    expect(source, contains('packageName == UpdateTrust.PACKAGE'));
    expect(source, contains('else if (!isBankingPackage())'));
    expect(source, contains('check(isBankingPackage())'));
    final updater = source.substring(source.indexOf(
        'MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UpdateTrust.CHANNEL)'));
    expect(updater, contains('requireUpdateRuntime()'));
    expect(
        updater,
        contains(
            'check(applicationContext.packageName == UpdateTrust.PACKAGE)'));
    expect(source, contains('file.parentFile == root'));
    expect(source, contains('Intent.FLAG_GRANT_READ_URI_PERMISSION'));
    expect(source, isNot(contains('FLAG_GRANT_WRITE_URI_PERMISSION')));
  });
  test('both flavours inherit bank provider with separate updater providers',
      () {
    final main =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final staging =
        File('android/app/src/staging/AndroidManifest.xml').readAsStringSync();
    expect(main, contains(r'${applicationId}.bank_documents'));
    expect(main, contains('android:exported="false"'));
    expect(main, isNot(contains('REQUEST_INSTALL_PACKAGES')));
    expect(main, isNot(contains('.update_files')));
    expect(staging, contains('REQUEST_INSTALL_PACKAGES'));
    expect(staging, contains(r'${applicationId}.update_files'));
    expect(staging, isNot(contains('.bank_documents')));
    final paths =
        File('android/app/src/main/res/xml/ceh_bank_document_paths.xml')
            .readAsStringSync();
    expect(paths, contains('path="bank-originals/"'));
    expect(paths, isNot(contains('<external-path')));
  });
}
