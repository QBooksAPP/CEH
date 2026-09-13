"""Synthetic ZIP inspector tests; these do not build an Android APK."""
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from apk_trust_isolation import inspect, PRODUCTION_PIN, STAGING_PIN

class IsolationTest(unittest.TestCase):
    def fixture(self, directory, flavour='production', leak=b'', entry='classes.dex', omit=False):
        path = Path(directory)/'inspection-fixture.zip'
        pin = PRODUCTION_PIN if flavour == 'production' else STAGING_PIN
        host = 'qbook.concretehireng.com' if flavour == 'production' else 'staging.concretehireng.com'
        data = {'AndroidManifest.xml': b'fixture', 'classes.dex': pin.encode(),
                'lib/arm64-v8a/libapp.so': ('https://'+host+'/updates/'+flavour+'/manifest.json').encode()}
        if omit:
            data['classes.dex'] = b'no trust value'
        data[entry] = data.get(entry,b'') + b'\0' + leak
        with zipfile.ZipFile(path,'w',compression=zipfile.ZIP_DEFLATED) as archive:
            for name, value in data.items():
                archive.writestr(name,value)
        return path

    def test_selected_trust_passes_both_flavours(self):
        with tempfile.TemporaryDirectory() as directory:
            for flavour in ['production','staging']:
                self.assertTrue(inspect(self.fixture(directory,flavour),flavour)['forbidden_trust_absent'])

    def test_pin_leaks_fail_in_compiled_payload_encodings(self):
        with tempfile.TemporaryDirectory() as directory:
            for flavour, pin in [('production',STAGING_PIN),('staging',PRODUCTION_PIN)]:
                for entry in ['classes.dex','lib/arm64-v8a/libapp.so','resources.arsc','assets/nested.bin']:
                    for data in [pin.encode(), pin.lower().encode(), pin.encode('utf-16-le'),
                                 pin.encode('utf-16-be'), bytes.fromhex(pin)]:
                        with self.subTest(flavour=flavour,entry=entry,bytes=len(data)):
                            with self.assertRaisesRegex(ValueError,'Forbidden'):
                                inspect(self.fixture(directory,flavour,data,entry),flavour)

    def test_staging_package_channel_provider_leaks_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            for leak in ['com.concreteequipmenthire.ceh.staging', 'staging.concretehireng.com',
                         '/updates/staging/', 'com.concreteequipmenthire.ceh/staging_update',
                         'com.concreteequipmenthire.ceh.update_files', 'ceh-staging-updates']:
                with self.subTest(leak=leak), self.assertRaises(ValueError):
                    inspect(self.fixture(directory,leak=leak.encode()),'production')

    def test_missing_expected_trust_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory, self.assertRaisesRegex(ValueError,'not observable'):
            inspect(self.fixture(directory,omit=True),'production')

    def test_source_zip_not_accepted_as_compiled_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'source.zip'
            with zipfile.ZipFile(path,'w') as archive:
                archive.writestr('AndroidManifest.xml','fixture')
            with self.assertRaisesRegex(ValueError,'Compiled DEX'):
                inspect(path,'production')

if __name__ == '__main__':
    unittest.main()
