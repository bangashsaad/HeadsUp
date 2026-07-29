# New Challenge screen — canonical design (locked)

Status: **default design for the app**. Build this, not the old flat-list flow.
Live reference: `HeadsUp Reimagined.dc.html` → DUELS tab → **+ NEW CHALLENGE**.
Explorations + rejected alternates: `HeadsUp Challenge.dc.html` (1a search-first, 1b open challenge, 1c terms-first — 1c is the one that shipped).

## Why it changed
The previous flow assumed a handful of friends and put a flat roster list first. It breaks past ~10 friends: no search, no grouping, and it invites you to select everyone. The canonical design is **terms first, audience second**, with a hard participant cap.

## Structure

**Header** — back chevron + `NEW CHALLENGE` (Archivo Black italic 17px).

**Step 1 — THE DUEL** (numbered volt pip + label, then one card, rows separated by `#1A1E2B`):

| Row | Options | Notes |
| --- | --- | --- |
| LEAGUE | `WNBA`, `MLB` | Single-league only. **No "BOTH"** — mixed-league scoring is out of scope. |
| ROSTER | `3`, `5`, `7` | Has an **i** info button → Roster Shapes modal. Default `5`. |
| STAKE | `PRIDE`, `50`, `250` | Coins come from the existing coins API. |
| PICK CLOCK | `15s`, `30s`, `60s` | Default `30s`. |

Selected option = accent fill + ink text; unselected = transparent with `#2E3547` border.

**Roster Shapes modal** (the **i** button) — three cards, one per roster size, current size highlighted with the accent. Every roster ends in one FLEX slot; positions lock as you draft.

- WNBA — 3: 1 GUARD / 1 FORWARD / 1 FLEX · 5: 2 GUARD / 2 FORWARD / 1 FLEX · 7: 3 GUARD / 3 FORWARD / 1 FLEX
- MLB — 3: 1 PITCHER / 1 INFIELD / 1 FLEX · 5: 1 PITCHER / 2 INFIELD / 1 OUTFIELD / 1 FLEX · 7: 2 PITCHER / 2 INFIELD / 2 OUTFIELD / 1 FLEX

Copy is league-aware: the modal shows the shapes for the league selected in step 1.

**Step 2 — SEND IT TO**

- Group tabs, pill row, horizontally scrollable, each with a count: **EVERYONE (always first)**, CREW, WORK, COLLEGE.
- Group shortcut (dashed card): "Send to all of WORK (7)" when the group fits the cap, otherwise "Send to the first 7 in EVERYONE". Subtitle: *First to accept plays · rest expire.*
- Person rows below: avatar (tint + green online dot), username, record/last-played line, check circle. Sorted **A–Z by username**.
- Tapping a person while the group shortcut is on switches to manual select with that person only.

**Participant cap — hard rule**

- Max **7 rivals** per challenge = **8 drafters** per duel (7 + you). Enforce server-side too.
- At the cap, unselected rows drop to 40% opacity and stop responding.
- Counter next to the step-2 header reads `n / 7 SELECTED`; footer note reads *7 rivals max — 8 drafters per duel*.

**Footer (fixed, over a fade)** — summary line (`WNBA · 5 slots · 30s clock`) + stake on the right, then the CTA:

- 0 selected → `PICK WHO GETS IT`, outline-only, disabled.
- 1 selected → `SEND TO 1`.
- 2+ → `SEND TO n · FIRST TAKES IT` (multi-send is a race; the first accept opens the draft, the rest expire).

Sending drops the user straight into the draft room.

## Visual tokens
Accent `var(--acc)` = volt `#C8FF2E` (default) · Ink `#0A0B10` · Surface `#12141D` · Raised `#191C28` · Border `#252A3A` / `#2E3547` · Text `#F4F5F7` / `#8B91A7` / `#565D73` · Online `#39D98A` · Live red `#FF4557`.
Type: Archivo (UI), Archivo Black italic (titles), Barlow Condensed 800 italic (numbers, buttons, labels).
Radii: cards 16px, rows 12–13px, pills 999px. Row padding 8–12px. Hit areas: person rows / group shortcut / CTA ≥44px tall; option pills ≥36px; the ROSTER **i** is a 24px circle inside a padded row (tap slop to 44px in native).

## Kept from the alternates (not built yet)
- **1a search-first**: search field + "Unfinished business" + A–Z letter rail — worth adding on top of step 2 once friend counts pass ~40.
- **1b open challenge**: post one slot to an audience, first to tap takes it — a second entry point, not a replacement.
