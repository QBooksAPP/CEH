"""Read-only compiled APK trust inspection. Never builds, signs or publishes."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

PRODUCTION_PIN = 'F859045ABA784241FD33F6DF182A484D716012350AC9DE64C88C9799CB79A30E'
STAGING_PIN = 'AFAFCE4A89211E7CBE6F0F665DB977F78CD96EF9343002F0A892B42F3FCDD057'

def variants(value):
    for text in {value, value.lower(), value.upper()}:
        for encoding in ('utf-8', 'utf-16-le', 'utf-16-be'):
            yield text.encode(encoding)
    if len(value) == 64 and all(c in '0123456789abcdefABCDEF' for c in value):
        yield bytes.fromhex(value)

def inspect(apk, flavour):
    if flavour not in ('production', 'staging'):
        raise ValueError('Unknown flavour')
    production = flavour == 'production'
    own_pin = PRODUCTION_PIN if production else STAGING_PIN
    other_pin = STAGING_PIN if production else PRODUCTION_PIN
    own_host = 'qbook.concretehireng.com' if production else 'staging.concretehireng.com'
    other_host = 'staging.concretehireng.com' if production else 'qbook.concretehireng.com'
    other = 'staging' if production else 'production'
    forbidden = [other_pin, other_host, '/updates/'+other+'/',
                 'com.concreteequipmenthire.ceh/'+other+'_update',
                 'ceh-'+other+'-updates', 'api.github.com/repos/QBooksAPP/CEH/releases']
    if production:
        forbidden += ['com.concreteequipmenthire.ceh.staging',
                      'com.concreteequipmenthire.ceh.update_files']
    else:
        forbidden += ['com.concreteequipmenthire.ceh.production_update_files']
    required = [own_pin, 'https://'+own_host+'/updates/'+flavour+'/manifest.json']
    seen = set()
    entries = []
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or 'AndroidManifest.xml' not in names:
            raise ValueError('Invalid APK entry inventory')
        if not any(n.endswith('.dex') for n in names) or not any(n.endswith('/libapp.so') for n in names):
            raise ValueError('Compiled DEX and Flutter AOT payload required')
        if sum(i.file_size for i in archive.infolist()) > 1024 * 1024 * 1024:
            raise ValueError('APK expanded size limit exceeded')
        for info in archive.infolist():
            if info.is_dir():
                continue
            data = archive.read(info)
            for token in forbidden:
                if any(value in data for value in variants(token)):
                    raise ValueError('Forbidden '+other+' trust material in '+info.filename)
            for token in required:
                if any(value in data for value in variants(token)):
                    seen.add(token)
            entries.append({'path':info.filename, 'sha256':hashlib.sha256(data).hexdigest(), 'bytes':len(data)})
    if seen != set(required):
        raise ValueError('Expected flavour trust material not observable; inspection cannot pass')
    return {'flavour':flavour, 'apk_sha256':hashlib.sha256(Path(apk).read_bytes()).hexdigest(),
            'forbidden_trust_absent':True, 'expected_trust_present':True, 'entries':entries}

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--apk', required=True)
    parser.add_argument('--flavour', required=True, choices=['production','staging'])
    args = parser.parse_args()
    print(json.dumps(inspect(args.apk, args.flavour), indent=2))
