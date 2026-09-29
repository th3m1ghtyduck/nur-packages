import urllib.request
import json
import urllib.parse
import subprocess
import os
import sys
import base64
import hashlib
import tempfile
import shutil

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SOURCE_JSON = os.path.join(SCRIPT_DIR, 'source.json')
API_URL = 'https://od.cloudsploit.top/api/?path=/tools/BinaryNinja'
HEADERS = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'}


def fetch(url):
    req = urllib.request.Request(url, headers=HEADERS)
    return urllib.request.urlopen(req)


def list_folder(path_suffix=''):
    with fetch(API_URL + path_suffix) as resp:
        data = json.loads(resp.read().decode('utf-8'))
    return data.get('folder', {}).get('value', [])


def parse_ver(v):
    parts = []
    for p in v.split('.'):
        try:
            parts.append(int(p))
        except ValueError:
            pass
    return tuple(parts)


def quick_xor_hash(path):
    # OneDrive's quickXorHash shifts byte i by (11*i) % 160 bits, which repeats every
    # 160 bytes, so XOR-folding the file into one 160-byte block first gives the same
    # result in seconds instead of a per-byte loop over the whole zip.
    block = 0
    length = 0
    tail = b''
    with open(path, 'rb') as f:
        while chunk := f.read(160 * 65536):
            chunk = tail + chunk
            usable = len(chunk) - len(chunk) % 160
            tail = chunk[usable:]
            length += usable
            view = memoryview(chunk)
            for off in range(0, usable, 160):
                block ^= int.from_bytes(view[off:off + 160], 'little')
    length += len(tail)
    block ^= int.from_bytes(tail, 'little')

    mask = (1 << 160) - 1
    h = 0
    for k, b in enumerate(block.to_bytes(160, 'little')):
        s = (k * 11) % 160
        h ^= ((b << s) | (b >> (160 - s))) & mask
    out = bytearray(h.to_bytes(20, 'little'))
    for i, b in enumerate(length.to_bytes(8, 'little')):
        out[12 + i] ^= b
    return base64.b64encode(bytes(out)).decode()


def find_latest():
    versions = [item['name'] for item in list_folder() if item['name'][0].isdigit()]
    versions.sort(key=parse_ver, reverse=True)

    for v in versions:
        for f in list_folder('/' + urllib.parse.quote(v)):
            name = f['name'].lower()
            if 'linux' in name and name.endswith('.zip') and 'arm' not in name:
                path = f'/tools/BinaryNinja/{v}/{f["name"]}'
                return {
                    'version': v,
                    'url': f'https://od.cloudsploit.top/api/raw?path={urllib.parse.quote(path)}',
                    'quickXorHash': f.get('file', {}).get('hashes', {}).get('quickXorHash'),
                    'size': f.get('size'),
                }
    return None



def check_official_hash(file_path, version):
    print('Fetching official hashes from binary.ninja...')
    try:
        req = urllib.request.Request("https://binary.ninja/js/hashes.json", headers=HEADERS)
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode('utf-8'))
        
        official_version = data.get('version')
        if official_version != version:
            print(f"Warning: Official hashes.json version ({official_version}) does not match downloaded version ({version}). Cannot verify hash.")
            return True
            
        official_hashes = data.get('hashes', {})
        # Try to find the correct hash, usually stable personal
        official_hash = official_hashes.get('binaryninja_linux_stable_personal.zip')
        if not official_hash:
            print("Warning: Could not find official hash for binaryninja_linux_stable_personal.zip.")
            return True
            
        print('Computing local SHA256 (hex)...')
        h = hashlib.sha256()
        with open(file_path, 'rb') as f:
            while chunk := f.read(65536):
                h.update(chunk)
        local_hash = h.hexdigest()
        
        if local_hash != official_hash:
            print(f"Error: Local hash ({local_hash}) does not match official hash ({official_hash})!")
            return False
            
        print(f"Official hash verified: {local_hash}")
        return True
    except Exception as e:
        print(f"Warning: Failed to check official hashes: {e}")
        return True

def check_official_hash(file_path, version):
    print('Fetching official hashes from binary.ninja...')
    try:
        req = urllib.request.Request("https://binary.ninja/js/hashes.json", headers=HEADERS)
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode('utf-8'))
        
        official_version = data.get('version')
        if official_version != version:
            print(f"Warning: Official hashes.json version ({official_version}) does not match downloaded version ({version}). Cannot verify hash.")
            return True
            
        official_hashes = data.get('hashes', {})
        # Try to find the correct hash, usually stable personal
        official_hash = official_hashes.get('binaryninja_linux_stable_personal.zip')
        if not official_hash:
            print("Warning: Could not find official hash for binaryninja_linux_stable_personal.zip.")
            return True
            
        print('Computing local SHA256 (hex)...')
        h = hashlib.sha256()
        with open(file_path, 'rb') as f:
            while chunk := f.read(65536):
                h.update(chunk)
        local_hash = h.hexdigest()
        
        if local_hash != official_hash:
            print(f"Error: Local hash ({local_hash}) does not match official hash ({official_hash})!")
            return False
            
        print(f"Official hash verified: {local_hash}")
        return True
    except Exception as e:
        print(f"Warning: Failed to check official hashes: {e}")
        return True

def main():
    latest = find_latest()
    if latest is None:
        print('Could not find any linux zip!')
        return 1
    print(f"Found latest linux zip in version {latest['version']}: {latest['url']}")

    existing = {}
    if os.path.exists(SOURCE_JSON):
        with open(SOURCE_JSON) as f:
            existing = json.load(f)

    if (
        existing.get('hash')
        and latest['quickXorHash']
        and existing.get('version') == latest['version']
        and existing.get('url') == latest['url']
        and existing.get('quickXorHash') == latest['quickXorHash']
    ):
        print(f"Remote quickXorHash matches source.json ({latest['quickXorHash']}), nothing to do.")
        return 0

    zip_name = f"binaryninja_linux_{latest['version']}_personal.zip"

    # Downloading locally instead of letting nix-prefetch-url fetch the URL avoids the
    # 403 the mirror returns to it from GitHub Actions, and lets us verify the file.
    print('Downloading zip...')
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = os.path.join(tmpdir, zip_name)
        with fetch(latest['url']) as resp, open(tmp_path, 'wb') as out:
            shutil.copyfileobj(resp, out)

        size = os.path.getsize(tmp_path)
        if latest['size'] is not None and size != latest['size']:
            print(f"Size mismatch: downloaded {size} bytes, server reports {latest['size']}")
            return 1

        local_qxh = quick_xor_hash(tmp_path)
        if latest['quickXorHash'] and local_qxh != latest['quickXorHash']:
            print(f"quickXorHash mismatch: downloaded {local_qxh}, server reports {latest['quickXorHash']}")
            return 1
        print(f'quickXorHash verified: {local_qxh}')

        if not check_official_hash(tmp_path, latest['version']):
            return 1

        print('Prefetching SHA256 hash with nix-prefetch-url...')
        result = subprocess.run(
            ['nix-prefetch-url', '--name', zip_name, f'file://{tmp_path}'],
            capture_output=True, text=True,
        )
    if result.returncode != 0:
        print('Failed to prefetch hash!')
        print(result.stderr)
        return 1

    sha256 = result.stdout.strip()
    print(f'SHA256: {sha256}')

    if existing.get('version') == latest['version'] and existing.get('hash'):
        if existing['hash'] == sha256:
            print('SHA256 unchanged, only refreshing mirror metadata.')
        else:
            print(f"Warning: version {latest['version']} was re-uploaded, SHA256 changed from {existing['hash']}")

    new_data = {
        'version': latest['version'],
        'url': latest['url'],
        'hash': sha256,
        'quickXorHash': local_qxh,
        'size': size,
    }
    if new_data == existing:
        print('source.json already up to date.')
        return 0

    with open(SOURCE_JSON, 'w') as out:
        json.dump(new_data, out, indent=2)
        out.write('\n')
    print(f'Wrote {SOURCE_JSON}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
