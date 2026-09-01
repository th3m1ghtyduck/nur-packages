"""
Auto-updater for IDA Pro from hexrays.su
Scrapes https://hexrays.su/ for latest torrent/magnet and updates source.json
Usage: python3 update.py [--prefetch]  ( --prefetch tries to compute new hash via nix build )
"""

import re
import json
import urllib.request
import urllib.parse
import html
import os
import sys
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SOURCE_JSON = os.path.join(SCRIPT_DIR, "source.json")
HEXRAYS_URL = "https://hexrays.su/"
BASE_URL = "https://hexrays.su/"

HEADERS = {"User-Agent": "Mozilla/5.0 (Nix Updater)"}

def fetch_page(url):
    print(f"Fetching {url} ...")
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=15) as resp:
        return resp.read().decode("utf-8", errors="replace")

def parse_latest(html_text):
    # Find first release block
    # Extract version, date, torrent, magnet

    # version like <span class="ver">IDA Pro 9.4 (Hotfix)</span>
    ver_match = re.search(r'<span class="ver">([^<]+)</span>', html_text)
    date_match = re.search(r'<span class="date">([^<]+)</span>', html_text)
    # first torrent href ending with .torrent
    torrent_match = re.search(r'href="([^"]+\.torrent)"', html_text)
    # first magnet
    magnet_match = re.search(r'href="(magnet:[^"]+)"', html_text)

    if not torrent_match or not magnet_match:
        print("Failed to find torrent or magnet links", file=sys.stderr)
        print(f"torrent_match={torrent_match}, magnet_match={magnet_match}", file=sys.stderr)
        sys.exit(1)

    display_version = html.unescape(ver_match.group(1).strip()) if ver_match else "unknown"
    date = html.unescape(date_match.group(1).strip()) if date_match else "unknown"

    torrent_rel = html.unescape(torrent_match.group(1).strip())
    torrent_url = urllib.parse.urljoin(BASE_URL, torrent_rel)

    magnet_raw = magnet_match.group(1).strip()
    # HTML entities like &amp;
    magnet_url = html.unescape(magnet_raw)

    # Derive version for nix (e.g. "IDA Pro 9.4 (Hotfix)" -> "9.4.0-hotfix")
    # Keep displayVersion, but version should be nix-friendly
    # Extract numeric version
    m = re.search(r"(\d+\.\d+(?:\.\d+)?)", display_version)
    if m:
        base_ver = m.group(1)
        # Normalize to x.y.z form for nix
        parts = base_ver.split(".")
        while len(parts) < 3:
            parts.append("0")
        norm_ver = ".".join(parts[:3])
        if "hotfix" in display_version.lower():
            version = f"{norm_ver}-hotfix"
        elif "beta" in display_version.lower():
            # Extract beta number if present
            bm = re.search(r"beta\s*(\d+)", display_version, re.I)
            beta = bm.group(1) if bm else "1"
            version = f"{norm_ver}-beta{beta}"
        else:
            version = norm_ver
    else:
        version = display_version.lower().replace(" ", "-")

    return {
        "displayVersion": display_version,
        "version": version,
        "date": date,
        "torrentUrl": torrent_url,
        "magnetUrl": magnet_url,
    }

def main():
    prefetch = "--prefetch" in sys.argv

    page = fetch_page(HEXRAYS_URL)
    latest = parse_latest(page)

    print(f"Latest: {latest['displayVersion']} ({latest['date']})")
    print(f"  torrent: {latest['torrentUrl']}")
    print(f"  magnet: {latest['magnetUrl'][:80]}...")

    # Load existing source.json if present
    existing = {}
    if os.path.exists(SOURCE_JSON):
        with open(SOURCE_JSON, "r") as f:
            existing = json.load(f)

    # Compare
    needs_update = (
        existing.get("torrentUrl") != latest["torrentUrl"]
        or existing.get("magnetUrl") != latest["magnetUrl"]
        or existing.get("version") != latest["version"]
        or existing.get("displayVersion") != latest["displayVersion"]
    )

    if not needs_update and not prefetch:
        print("source.json is already up to date.")
        return 0

    # Prepare new source.json
    new_data = {
        "version": latest["version"],
        "date": latest["date"],
        "displayVersion": latest["displayVersion"],
        "torrentUrl": latest["torrentUrl"],
        "magnetUrl": latest["magnetUrl"],
        "hash": existing.get("hash", "") if not needs_update else "",
    }

    # If prefetch requested, try to get hash via nix build with fakeHash
    if prefetch:
        print("\nPrefetching hash via nix build (this will download ~3.6GB via torrent) ...")
        # Write temp source.json with fake hash
        tmp_data = dict(new_data)
        tmp_data["hash"] = ""
        with open(SOURCE_JSON, "w") as out:
            json.dump(tmp_data, out, indent=2)
            out.write("\n")
        # Try build and capture hash mismatch
        expr = 'let pkgs = import <nixpkgs> { config.allowUnfree = true; }; in (pkgs.callPackage ./default.nix { inherit pkgs; }).hotfixSrc'
        # This is fragile, we use nix build --impure
        cmd = ["nix", "build", "--impure", "--expr", expr, "--no-link", "--print-out-paths"]
        # Use NIXPKGS_ALLOW_UNFREE=1 as fallback
        env = os.environ.copy()
        env["NIXPKGS_ALLOW_UNFREE"] = "1"
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=SCRIPT_DIR, env=env)
        if result.returncode == 0:
            print("Build succeeded without hash mismatch")
        else:
            # Parse hash from stderr: look for "got:    sha256-..."
            combined = result.stderr + result.stdout
            m = re.search(r"got:\s+(sha256-[A-Za-z0-9+/=]+)", combined)
            if not m:
                m = re.search(r"sha256:([A-Za-z0-9+/=]+)", combined)
                if m:
                    new_hash = "sha256-" + m.group(1)
                else:
                    print("Failed to parse hash from nix build output", file=sys.stderr)
                    print(combined[-2000:], file=sys.stderr)
                    sys.exit(1)
            else:
                new_hash = m.group(1)
            print(f"Discovered hash: {new_hash}")
            new_data["hash"] = new_hash

    # Write source.json
    with open(SOURCE_JSON, "w") as out:
        json.dump(new_data, out, indent=2)
        out.write("\n")

    if needs_update:
        print(f"\nUpdated {SOURCE_JSON}")
        print(json.dumps(new_data, indent=2))
        if not prefetch:
            print("\nHash is set to \"\" (fake). Run one of:")
            print("  python3 update.py --prefetch   # to auto-fetch hash (heavy, 3.6GB download)")
            print("  NIXPKGS_ALLOW_UNFREE=1 nix build --impure -A ida-pro-personal  # will show correct hash, then paste into source.json")
    else:
        if prefetch:
            print(f"Updated hash in {SOURCE_JSON}")

    return 0

if __name__ == "__main__":
    sys.exit(main())
