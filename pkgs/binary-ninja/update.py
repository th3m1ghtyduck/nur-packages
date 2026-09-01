import urllib.request
import json
import urllib.parse
import subprocess
import os

base_url = 'https://od.cloudsploit.top/api/?path=/tools/BinaryNinja'
req = urllib.request.Request(base_url, headers={'User-Agent': 'Mozilla/5.0'})
resp = urllib.request.urlopen(req)
data = json.loads(resp.read().decode('utf-8'))

versions = []
for item in data.get('folder', {}).get('value', []):
    name = item['name']
    if name[0].isdigit():
        versions.append(name)

def parse_ver(v):
    parts = []
    for p in v.split('.'):
        try:
            parts.append(int(p))
        except ValueError:
            pass
    return tuple(parts)

versions.sort(key=parse_ver, reverse=True)

for v in versions:
    v_url = f'https://od.cloudsploit.top/api/?path=/tools/BinaryNinja/{urllib.parse.quote(v)}'
    req = urllib.request.Request(v_url, headers={'User-Agent': 'Mozilla/5.0'})
    resp = urllib.request.urlopen(req)
    v_data = json.loads(resp.read().decode('utf-8'))
    
    for f in v_data.get('folder', {}).get('value', []):
        name = f['name'].lower()
        if 'linux' in name and name.endswith('.zip') and 'arm' not in name:
            path = f'/tools/BinaryNinja/{v}/{f["name"]}'
            download_url = f'https://od.cloudsploit.top/api/raw?path={urllib.parse.quote(path)}'
            print(f"Found latest linux zip in version {v}: {download_url}")
            
            print("Prefetching SHA256 hash with nix-prefetch-url...")
            zip_name = f'binaryninja_linux_{v}_personal.zip'
            result = subprocess.run(['nix-prefetch-url', '--name', zip_name, download_url], capture_output=True, text=True)
            if result.returncode != 0:
                print("Failed to prefetch hash!")
                print(result.stderr)
                exit(1)
            
            sha256 = result.stdout.strip()
            print(f"SHA256: {sha256}")
            
            with open('source.json', 'w') as out:
                json.dump({"version": v, "url": download_url, "hash": sha256}, out, indent=2)
            
            print("Wrote source.json successfully!")
            exit(0)
print("Could not find any linux zip!")
exit(1)
