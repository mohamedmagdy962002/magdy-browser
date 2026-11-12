# Magdy Browser

A free, no-subscription iOS browser. Original implementation — no Aloha code, assets,
branding or third-party SDKs were copied.

- **No account, no subscription, no trial, no paywall.** Every feature is on from install.
- **Unlimited downloads** — no count cap, no speed cap, no "upgrade to remove limits" gate.
- **Private mode** — non-persistent data store, nothing written to history or cookies.
- **Built-in ad/tracker blocking** — WebKit content rule lists, no extension needed.
- **Media grabber** — scans the current page for video/audio/file links and downloads them.
- **Favorites, tab switcher, DuckDuckGo search, cache/cookie cleanup.**

## Project layout

```
MagdyBrowser/
├── project.yml                     # XcodeGen project definition
├── Resources/
│   ├── Assets.xcassets             # app icon + accent color
│   ├── blocklist_ads.json          # generated filter list
│   └── blocklist_trackers.json     # generated filter list
├── Sources/
│   ├── App/                        # AppDelegate, RootViewController
│   ├── Browser/                    # BrowserTab, BrowserViewController, MediaPicker
│   ├── Blocking/                   # ContentBlocker (WKContentRuleList)
│   ├── Downloads/                  # DownloadManager, DownloadsViewController
│   ├── Favorites/                  # FavoritesStore, FavoritesViewController
│   ├── Settings/                   # SettingsViewController
│   └── Support/                    # shared helpers
└── scripts/
    ├── build.sh                    # generate project → archive → export IPA
    ├── ExportOptions.plist
    ├── generate_blocklists.py      # regenerates the filter JSON
    └── generate_icon.py            # regenerates the 1024px icon
```

## Requirements

- macOS with Xcode 14+ (iOS 15 deployment target)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- An Apple ID. A **free personal team** is enough for the app as shipped (no extensions,
  no special entitlements). Signing then expires after 7 days and must be refreshed.

## Get an IPA without a Mac (Windows)

The project builds on GitHub's macOS runners and hands you a ready-to-sideload IPA.

```powershell
# 1. Create an empty repo at https://github.com/new  (name: magdy-browser, public = unlimited free minutes)

# 2. From this folder:
.\scripts\push_and_build.ps1 -RepoUrl https://github.com/<your-user>/magdy-browser.git
#    (GitHub asks for username + Personal Access Token as the password)

# 3. The Actions tab opens automatically. Wait for "Build IPA" to finish,
#    then download the artifact "MagdyBrowser-ipa" (a .zip containing MagdyBrowser-unsigned.ipa).
```

The CI builds **unsigned** on purpose — no Apple credentials live in anyone else's CI.
Your Apple ID signs the app locally at install time.

### Install on a Windows PC + iPhone

**Sideloadly** (simplest, works from Windows):
1. Install [Apple Devices](https://apps.apple.com/app/apple-devices/id1101183) (or iTunes) for the USB driver.
2. Install [Sideloadly](https://sideloadly.io).
3. Connect the iPhone by USB, tap "Trust" on the phone.
4. Drag `MagdyBrowser-unsigned.ipa` into Sideloadly, enter your Apple ID, press **Start**.

**AltStore**: import the IPA, then AltStore re-signs it automatically on the same Wi-Fi
(same Apple ID) every 7 days.

**TrollStore**: on a TrollStore device, install the IPA directly — no Apple ID needed.

> A free Apple ID's signature expires after 7 days. AltStore refreshes automatically;
> with Sideloadly you re-run the install once a week. A paid developer account ($99/yr)
> gives 1 year.

## Build on a Mac

```bash
cd MagdyBrowser
chmod +x scripts/build.sh
./scripts/build.sh
# -> build/ipa/MagdyBrowser.ipa
```

The script runs `xcodegen generate`, archives with `xcodebuild`, and exports the IPA with
automatic signing.

### Install on a device

- **Sideloadly / AltStore / TrollStore**: drag the `.ipa` in; the app is signed with your
  personal team and runs like any sideloaded app.
- **Xcode**: open `MagdyBrowser.xcodeproj`, pick your device, press Run.

### Regenerate assets

```bash
python scripts/generate_blocklists.py   # filter lists
python scripts/generate_icon.py         # 1024x1024 app icon
```

## Feature notes

| Area | Behaviour |
|---|---|
| Downloads | `WKDownload` for page downloads, `URLSession` for direct media links. Progress is polled from the destination file. Files land in `Documents/Downloads` and are visible in the Files app (`UIFileSharingEnabled`). |
| Media grabber | Injects JS into the current page, collects `<video>`/`<source>` and links ending in mp4/m4v/mov/webm/mkv/mp3/m4a/aac/wav/flac/zip/pdf/apk, then hands them to the download queue with the page cookies and Referer attached. |
| Blocking | Ads and trackers are two compiled `WKContentRuleList`s (~180 domains + a cosmetic rule). Toggle in Settings; new tabs pick up changes. |
| Private mode | Private tabs use `WKWebsiteDataStore.nonPersistent()`. |

## What is deliberately not included

These need infrastructure or entitlements that cannot be shipped inside a free
personal-team build:

- **System-wide VPN.** iOS requires `NEPacketTunnelProvider` +
  `com.apple.developer.networking.networkextension`, which needs a **paid Apple Developer
  account ($99/yr)** and a real tunnel server. There is no client-side workaround, and
  any VPN provider also enforces its own server-side throughput policy — that is
  something the app owner controls, not the app binary.
- **Account sync** (Aloha syncs tabs/bookmarks through its servers). Magdy keeps data on
  device; adding sync means adding a backend.
- **Chromecast / third-party SDKs.** Casting needs the Google Cast SDK and an app ID
  issued per developer account.

## Legal

Magdy is an independent application. Do not redistribute Aloha Browser (or any
commercially licensed app) as your own build; the copy in this repository's parent
folder came from a third-party store with DRM removed and is not yours to ship.
