# Magdy Browser — Design System

Generated with **Google Stitch** (project `projects/6614988887356774659`, device MOBILE 780×1768 @2x).
Applied in code by `Sources/Design/Theme.swift`.

## Brand & style

Tactile, premium iOS-first browsing experience. Pure iOS HIG naturalism, an editorial
luminous workspace: light-lavender canvas, pristine white floating surfaces, one intense
indigo focal anchor. No clutter.

## Palette

| Token | Value | Use |
|---|---|---|
| Canvas | `#F5F5FB` | app background |
| Card | `#FFFFFF` | resting surfaces |
| Primary | `#4A47F0` | accent, active tab, CTA |
| Primary alt | `#6C63FF` | gradient end |
| Violet | `#8A3FFC` | media / audio badges |
| Text primary | `#1C1C1E` | titles, labels |
| Text secondary | `#8E8E93` | subtitles, captions |
| Hairline | `rgba(0,0,0,0.04)` | dividers |

Gradient: `linear-gradient(135deg, #4A47F0 0%, #6C63FF 100%)`.

## Elevation

| Tier | Shadow |
|---|---|
| Level 0 — canvas | flat `#F5F5FB` |
| Level 1 — resting card | `0 2px 8px rgba(74,71,240,0.04), 0 8px 24px rgba(28,28,30,0.06)` |
| Level 2 — floating chrome | `0 4px 20px rgba(28,28,30,0.08)` + `blur(20px) saturate(180%)` on `rgba(255,255,255,0.88)` |
| Level 3 — primary action | `0 8px 22px rgba(74,71,240,0.35)` |

## Geometry

- 44pt minimum touch target.
- Bottom nav dock: 16px lateral margins, 12px above the home indicator.
- Cards: 20pt corner radius, white, Level 1 shadow.
- Omnibox: 50px tall, 20px radius, white surface, Level 2 shadow.
- Speed-dial grid: 3 columns on iPhone, 16px gutters.

## Typography

Stitch specifies Inter (body) and Space Grotesk (headlines). iOS ships neither, so the
implementation maps them to the system face:

- Headlines → `UIFont.systemFont(...).withDesign(.rounded)` (SF Rounded) — closest native
  match to Space Grotesk's geometric, friendly character.
- Body/labels → `UIFont.systemFont(...)` (SF Pro) — metrically and stylistically equivalent
  to Inter for UI text.

## Screens designed in Stitch

| Screen | Status |
|---|---|
| Speed Dial Home | implemented (start page + omnibox + FAB) |
| Downloads | implemented |
| Media Tab | implemented (gradient CTA card + file list) |
| Settings | implemented |
| History | implemented |
| Favorites | implemented |
| Video Downloader | implemented (sheet) |

## Regenerating

```powershell
# project + design system live at projects/6614988887356774659
gh run download  # builds the app from Sources/Design/Theme.swift
```
