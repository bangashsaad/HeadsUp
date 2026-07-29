# HeadsUp app icon — handoff

Master mark: **5a Pulse H** — white condensed-italic H + glowing volt heartbeat on ink.
Source of truth: `HeadsUp App Icon.dc.html` (badge 5a). Primary app accent is volt `#C8FF2E`.

## Files (in this folder)
| File | Use |
| --- | --- |
| `app-icon-1024.png` | iOS + store icon (`expo.icon`) |
| `splash-icon-1024.png` | Splash / launch mark (`expo.splash.image`) |
| `android-adaptive-foreground-1024.png` | Android adaptive foreground (art inside the 66% safe zone) |
| `android-adaptive-background-1024.png` | Android adaptive background |
| `favicon-256.png` | Web favicon (`expo.web.favicon`) |

## Drop into the Expo repo
1. Copy all five PNGs into `assets/` in the app repo.
2. Point `app.json` at them:
```json
{
  "expo": {
    "icon": "./assets/app-icon-1024.png",
    "splash": { "image": "./assets/splash-icon-1024.png", "backgroundColor": "#080A06" },
    "android": {
      "adaptiveIcon": {
        "foregroundImage": "./assets/android-adaptive-foreground-1024.png",
        "backgroundImage": "./assets/android-adaptive-background-1024.png"
      }
    },
    "web": { "favicon": "./assets/favicon-256.png" }
  }
}
```
3. `npx expo prebuild --clean` (or an EAS build) regenerates every density — no manual slicing.

## Brand colors
- Accent (primary): `#C8FF2E` volt
- Icon field: radial `#26330E → #080A06`
- Ink: `#0A0B10`  ·  Surface: `#12141D`  ·  Border: `#252A3A`
- Text: `#F4F5F7` primary, `#8B91A7` secondary, `#565D73` tertiary
- Rival violet: `#7C5CFF`  ·  Live red: `#FF4557`
- Alternates kept in the icon file: blue `#22E5FF` (3a/3b), red `#FF3B30` (4a/4b)

## Pulling the designs later
- `HeadsUp Reimagined.dc.html` — the full app mockup (home, duels, draft, live duel w/ trash-talk chat + share card, profile w/ rivalry pages)
- `HeadsUp Live Scores.dc.html`, `HeadsUp Duel Night.dc.html`, `HeadsUp Crew.dc.html` — parked concepts (game slate, win-probability graph, weekly ladder)
- `HeadsUp Players.dc.html`, `HeadsUp Current.dc.html`, `HeadsUp Home Laterals.dc.html`, `HeadsUp Changes Review.dc.html`
- `HeadsUp Reimagined (Standalone).html` — single self-contained file, opens offline
- Type: Archivo / Archivo Black / Barlow Condensed (Google Fonts). Team logos: `a.espncdn.com/i/teamlogos/<league>/500/<abbrev>.png`; headshot ids in `players-data.js`.
