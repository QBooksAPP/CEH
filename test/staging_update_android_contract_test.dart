import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('installer permission and FileProvider exist only in staging manifest',
      () {
    final mainManifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final stagingManifest =
        File('android/app/src/staging/AndroidManifest.xml').readAsStringSync();

    expect(mainManifest, isNot(contains('REQUEST_INSTALL_PACKAGES')));
    expect(mainManifest, isNot(contains('update_files')));
    expect(stagingManifest, contains('REQUEST_INSTALL_PACKAGES'));
    expect(stagingManifest, contains('androidx.core.content.FileProvider'));
    expect(stagingManifest, contains(r'${applicationId}.update_files'));
    expect(stagingManifest, contains('android:exported="false"'));
    expect(stagingManifest, contains('android:value="STAGING"'));
  });

  test('native installer pins staging package, signer and private cache', () {
    final kotlin = File(
      'android/app/src/main/kotlin/com/concreteequipmenthire/ceh/MainActivity.kt',
    ).readAsStringSync();

    expect(kotlin, contains('com.concreteequipmenthire.ceh.staging'));
    expect(
      kotlin,
      contains(
        'AFAFCE4A89211E7CBE6F0F665DB977F78CD96EF9343002F0A892B42F3FCDD057',
      ),
    );
    expect(kotlin, contains('GET_SIGNING_CERTIFICATES'));
    expect(kotlin, contains('apkContentsSigners'));
    expect(kotlin, contains('versionCode > installedVersion'));
    expect(kotlin, contains('ceh-staging-updates'));
    expect(kotlin, contains('canRequestPackageInstalls'));
    expect(kotlin, contains('FLAG_GRANT_READ_URI_PERMISSION'));
  });

  test('release signing is selected only for staging release tasks', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('buildsStagingRelease'));
    expect(gradle, contains('stagingPermanent'));
    expect(gradle, contains('CEH_STAGING_KEYSTORE_PATH'));
    expect(gradle, contains('CEH_STAGING_KEYSTORE_PASSWORD'));
    expect(gradle, contains('CEH_STAGING_KEY_ALIAS'));
    expect(gradle, contains('Production retains its existing'));
  });
}
