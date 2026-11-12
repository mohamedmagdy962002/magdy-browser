"""Generates the content-blocker filter lists shipped with Magdy Browser.

Format: Safari/WebKit content blocker JSON.
Run:  python scripts/generate_blocklists.py
"""

import json
import os

ADS = """
doubleclick.net googlesyndication.com googleadservices.com google-analytics.com
adservice.google.com 2mdn.net adnxs.com adsrvr.org taboola.com outbrain.com
popads.net popcash.net propellerads.com adsterra.com exoclick.com juicyads.com
clickadu.com hilltopads.net trafficjunky.com mgid.com media.net revcontent.com
zedo.com adform.net smartadserver.com casalemedia.com openx.net pubmatic.com
rubiconproject.com criteo.com criteo.net 33across.com sharethrough.com
indexww.com bidswitch.net adroll.com adblade.com adiquity.com amazon-adsystem.com
aaxads.com moatads.com sscore.com teads.tv spotxchange.com freewheel.tv
yieldmo.com adcolony.com inmobi.com applovin.com mopub.com startappservice.com
vungle.com unityads.unity3d.com ads.unityads.unity3d.com admob.com adsense.com
adsrvr.org adcash.com adf.ly sh.st exoclick.com juicyads.com propellerads.com
adservice.google.com adwords-info.com static.clevertap-prod.com ads-twitter.com
ads.linkedin.com ad.atdmt.com ads.braun.com adv.ms ads.everesttech.net
advertising.com yieldmanager.com mediaflash.com adsafeprotected.com
""".split()

TRACKERS = """
google-analytics.com googletagmanager.com ssl.google-analytics.com
connect.facebook.net facebook.net scorecardresearch.com quantserve.com
hotjar.com hotjar.io mouseflow.com mixpanel.com api.mixpanel.com amplitude.com
api2.amplitude.com segment.io cdn.segment.com segment.com api.segment.io
fullstory.com cr.fullstory.com crazyegg.com script.crazyegg.com clarity.ms
newrelic.com js-agent.newrelic.com kissmetrics.com statcounter.com
histogram.com chartbeat.com chartbeat.net comscore.com omtrdc.net demdex.net
everesttech.net bluekai.com krxd.net rlcdn.com tapad.com mparticle.com
mparticle.com branching.io kochava.com appsflyer.com adjust.com
analytics.icloud.com icloud.com/cdn 2o7.net adroll.com spinr.net
quantcount.com quantserve.com moatads.com adsrvr.org bluekai.com
""".split()


def build(domains):
    rules = []
    for domain in sorted(set(domains)):
        rules.append(
            {
                "trigger": {"url-filter": ".*", "if-domain": ["*" + domain]},
                "action": {"type": "block"},
            }
        )
    # Generic cosmetic rules: hide common ad containers on any site.
    rules.append(
        {
            "trigger": {"url-filter": ".*"},
            "action": {
                "type": "css-display-none",
                "selector": ".ad, .ads, .ad-banner, .adslot, .adsbygoogle, "
                ".advertisement, .banner-ad, .sponsored, .promo-banner, "
                "[id^='google_ads_'], [id^='div-gpt-ad']",
            },
        }
    )
    return rules


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    resources = os.path.join(root, "Resources")
    os.makedirs(resources, exist_ok=True)

    for name, domains in (("ads", ADS), ("trackers", TRACKERS)):
        path = os.path.join(resources, f"blocklist_{name}.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(build(domains), handle, indent=2)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
