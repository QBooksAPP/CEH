"""CI-only artifact build; no publication or deployment operations."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from apk_trust_isolation import inspect as inspect_apk_trust

PACKAGE = 'com.concreteequipmenthire.ceh'
SIGNER = 'f859045aba784241fd33f6df182a484d716012350ac9de64c88c9799cb79a30e'
VERSION = '0.4.0'
CODE = 97

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def run(args, capture=False):
    return subprocess.run(args, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout

def main():
    require(os.environ.get('GITHUB_ACTIONS') == 'true', 'CI runner only')
    require(os.environ.get('GITHUB_EVENT_NAME') == 'workflow_dispatch', 'Manual only')
    require(os.environ.get('GITHUB_REF') == 'refs/heads/main', 'Reviewed main only')
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    require(event.get('repository', {}).get('private') is True, 'Private artifact repository required')
    inputs = event.get('inputs', {})
    require(str(inputs.get('confirm_candidate_only')).lower() == 'true', 'Explicit candidate confirmation required')
    approved = inputs.get('approved_commit', '')
    require(re.fullmatch(r'[0-9a-f]{40}', approved) and
            run(['git', 'rev-parse', 'HEAD'], True).strip() == approved == os.environ['GITHUB_SHA'],
            'Exact approved source required')
    for key in ['CEH_KEYSTORE_BASE64','CEH_KEYSTORE_PASSWORD','CEH_KEY_PASSWORD','CEH_KEY_ALIAS']:
        require(bool(os.environ.get(key)), 'Production signing secret missing')
    require(CODE > 96, 'Version must exceed 96')
    gradle = Path('android/app/build.gradle.kts')
    original = gradle.read_bytes()
    output = Path('candidate-output')
    require(not output.exists(), 'Output already exists')
    try:
        with tempfile.TemporaryDirectory(prefix='ceh-candidate-', dir=os.environ['RUNNER_TEMP']) as temporary:
            keyfile = Path(temporary)/'production.jks'
            keyfile.write_bytes(base64.b64decode(os.environ['CEH_KEYSTORE_BASE64'], validate=True))
            keyfile.chmod(0o600)
            os.environ['CEH_CANDIDATE_KEYSTORE'] = str(keyfile)
            text = original.decode()
            marker = '    signingConfigs {'
            fallback = 'signingConfig = signingConfigs.getByName("debug")'
            require(text.count(marker)==1 and text.count(fallback)==1, 'Unexpected Gradle signing layout')
            text = text.replace(marker, marker+'''
        create("candidateProduction") {
            storeFile = file(System.getenv("CEH_CANDIDATE_KEYSTORE"))
            storePassword = System.getenv("CEH_KEYSTORE_PASSWORD")
            keyPassword = System.getenv("CEH_KEY_PASSWORD")
            keyAlias = System.getenv("CEH_KEY_ALIAS")
        }
''',1).replace(fallback,'signingConfig = signingConfigs.getByName("candidateProduction")')
            gradle.write_text(text)
            run(['flutter','build','apk','--release','--flavor','production',
                 '--build-name='+VERSION,'--build-number='+str(CODE),
                 '--dart-define=CEH_ENVIRONMENT=production',
                 '--dart-define=CEH_API_BASE_URL=https://qbook.concretehireng.com',
                 '--dart-define=CEH_UPDATE_CHECKS=true'])
            apk = Path('build/app/outputs/flutter-apk/app-production-release.apk')
            require(apk.is_file(), 'APK missing')
            sdk = Path(os.environ.get('ANDROID_HOME') or os.environ['ANDROID_SDK_ROOT'])
            versions = [p for p in (sdk/'build-tools').iterdir() if re.fullmatch(r'\d+\.\d+\.\d+',p.name)]
            tools = max(versions,key=lambda p:tuple(map(int,p.name.split('.'))))
            certs = run([str(tools/'apksigner'),'verify','--verbose','--print-certs',str(apk)],True)
            signers = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]+)$',certs,re.M)
            require([s.lower() for s in signers]==[SIGNER], 'STOP: signer mismatch')
            badging = run([str(tools/'aapt'),'dump','badging',str(apk)],True)
            match = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'",badging)
            require(match and match.groups()==(PACKAGE,str(CODE),VERSION), 'Package/version mismatch')
            require('application-debuggable' not in badging, 'Debug APK forbidden')
            manifest = run([str(tools/'aapt'),'dump','xmltree',str(apk),'AndroidManifest.xml'],True)
            require('.staging' not in manifest and '.update_files' not in manifest, 'Staging provider leakage')
            require(PACKAGE+'.production_update_files' in manifest, 'Production updater provider missing')
            require(PACKAGE+'.bank_documents' in manifest, 'Production bank provider missing')
            isolation = inspect_apk_trust(apk, 'production')
            output.mkdir()
            target = output/('CEH-'+VERSION+'-'+str(CODE)+'.apk')
            target.write_bytes(apk.read_bytes())
            record = {'package':PACKAGE,'version_name':VERSION,'version_code':CODE,
                      'signer_sha256':SIGNER,'apk_sha256':hashlib.sha256(target.read_bytes()).hexdigest(),
                      'bytes':target.stat().st_size,'source_commit':os.environ['GITHUB_SHA'],
                      'environment':'production','api_origin':'https://qbook.concretehireng.com',
                      'updater':'https://qbook.concretehireng.com/updates/production/manifest.json','publication':False,
                      'binary_isolation':isolation,
                      'flutter_version':run(['flutter','--version','--machine'],True)}
            (output/'manifest.json').write_text(json.dumps(record,indent=2))
            print(json.dumps(record,indent=2))
    finally:
        gradle.write_bytes(original)
        os.environ.pop('CEH_CANDIDATE_KEYSTORE',None)

if __name__ == '__main__':
    main()
