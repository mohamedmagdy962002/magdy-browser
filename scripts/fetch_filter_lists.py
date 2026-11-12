"""Downloads the real filter lists and converts them to Safari/WebKit content-blocker rules.

Usage:
    python scripts/fetch_filter_lists.py

Writes:
    Resources/blocklist_full.json   (ad + tracker domains from EasyList / EasyPrivacy)

Only the domain-based rules are converted: WebKit's WKContentRuleList works on
domain matching, while the cosmetic/exception rules of the upstream lists are
handled by Magdy's own cosmetic rule.
"""

import json
import os
import re
import urllib.request

SOURCES = {
    "ads": "https://easylist.to/easylist/easylist.txt",
    "trackers": "https://easylist.to/easylist/easyprivacy.txt",
}

DOMAIN_RE = re.compile(r"^(?:\|\|)?([a-z0-9][a-z0-9.\-]*\.[a-z]{2,})(?:\^)?$")
HEADER_RE = re.compile(r"^\[!|^!|^\[", re.IGNORECASE)


def fetch(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": "MagdyBrowser/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8", errors="ignore")


def domains_from(text: str) -> set:
    found = set()
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("!") or line.startswith("["):
            continue
        if "/" in line:  # path rules are out of scope for domain matching
            continue
        match = DOMAIN_RE.match(line)
        if not match:
            continue
        domain = match.group(1)
        if domain.count(".") >= 1 and len(domain) <= 100:
            found.add(domain)
    return found


def build(domains):
    rules = []
    for domain in sorted(domains):
        rules.append(
            {
                "trigger": {"url-filter": ".*", "if-domain": ["*" + domain]},
                "action": {"type": "block"},
            }
        )
    rules.append(
        {
            "trigger": {"url-filter": ".*"},
            "action": {
                "type": "css-display-none",
                "selector": ".ad, .ads, .ad-banner, .adslot, .adsbygoogle, "
                ".advertisement, .banner-ad, .sponsored, .promo-banner, "
                "[id^='google_ads_'], [id^='div-gpt-ad'], .taboola, .outbrain",
            },
        }
    )
    return rules


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    resources = os.path.join(root, "Resources")

    all_domains = set()
    for name, url in SOURCES.items():
        try:
            text = fetch(url)
        except Exception as error:  # network may be unavailable
            print(f"! could not fetch {url}: {error}")
            continue
        domains = domains_from(text)
        print(f"{url}: {len(domains)} domains")
        all_domains |= domains

    if not all_domains:
        print("! no domains fetched, keeping existing curated lists")
        return

    rules = build(all_domains)
    path = os.path.join(resources, "blocklist_full.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(rules, handle, separators=(",", ":"))
    print(f"wrote {path} ({os.path.getsize(path) // 1024} KB, {len(rules)} rules)")


if __name__ == "__main__":
    main()
