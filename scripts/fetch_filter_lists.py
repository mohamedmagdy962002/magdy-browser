"""Downloads the full filter-list ecosystem into Resources/filters for the in-app manager.

Usage:
    python scripts/fetch_filter_lists.py

The app compiles the selected lists into WKContentRuleLists at runtime, so the
raw ABP syntax (including path rules) is shipped rather than a pre-converted subset.
"""

import json
import os
import re
import urllib.request

LISTS = {
    "easylist": "https://easylist.to/easylist/easylist.txt",
    "easyprivacy": "https://easylist.to/easylist/easyprivacy.txt",
    "easylist_germany": "https://easylist.to/easylistgermany/easylistgermany.txt",
    "fanboy_annoyance": "https://secure.fanboy.co.nz/fanboy-annoyance.txt",
    "fanboy_social": "https://secure.fanboy.co.nz/fanboy-social.txt",
    "peter_lowe": "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=0&mimetype=plaintext",
}

DOMAIN_RE = re.compile(r"^(?:\|\|)?([a-z0-9][a-z0-9.\-]*\.[a-z]{2,})(?:\^)?$")


def fetch(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": "MagdyBrowser/1.0"})
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.read().decode("utf-8", errors="ignore")


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    resources = os.path.join(root, "Resources")
    filters = os.path.join(resources, "filters")
    os.makedirs(filters, exist_ok=True)

    manifest = []
    for name, url in LISTS.items():
        try:
            text = fetch(url)
        except Exception as error:
            print(f"! {name}: {error}")
            continue
        path = os.path.join(filters, f"{name}.txt")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)

        domains = set()
        for line in text.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith(("!", "[")) or "/" in stripped:
                continue
            match = DOMAIN_RE.match(stripped)
            if match:
                domains.add(match.group(1))

        manifest.append({
            "id": name,
            "title": name.replace("_", " ").title(),
            "source": url,
            "bytes": os.path.getsize(path),
            "domains": len(domains),
        })
        print(f"{name}: {os.path.getsize(path) // 1024} KB, {len(domains)} domains")

    manifest_path = os.path.join(filters, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)
    print(f"wrote {manifest_path}")


if __name__ == "__main__":
    main()
