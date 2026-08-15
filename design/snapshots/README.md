# Live-app snapshots — what the web app ACTUALLY looks like right now

Each file here is the real rendered HTML of one screen, captured from
production and made self-contained (styles inlined, LiveView plumbing
stripped). **This is the current implementation, not the design mockups** —
use these when you want Claude Design to edit against reality.

## How to use with Claude Design

These files are deliberately SMALL and READABLE — clean markup plus a compact
stylesheet of the app's real design tokens. That's the format a design tool
actually consumes (earlier fully-embedded versions were unreadable to it).

1. **Getting a file out of GitHub the right way:** open the file → click the
   **Raw** button → select-all and copy (or Save As). Do NOT copy from
   GitHub's normal file viewer — that includes GitHub's own page markup.
2. Start your Claude Design session by pasting the brief
   (`docs/design-brief.md`).
3. Paste (or attach) the snapshot for the screen you're editing and say:
   *"This is the current live implementation of the <name> screen — real
   markup and real design tokens. Edit from this."*
4. Images show as empty placeholders marked `data-note="player-or-team-image"`
   — that's intentional; the markup and styles are the design, the photos are
   content.
5. When you're happy, export per screen as usual and hand it back.

Snapshots were captured with demo accounts (`snap_sp1ke` vs `snap_mike`, plus
a fresh account for the empty states), since deleted. Names/scores in the
files are demo data; the markup and styles are the real thing.

## The files

| File | Screen | Captured state |
|---|---|---|
| `landing.html` | Landing page | Signed out |
| `login.html` / `signup.html` | Auth | Signed out |
| `home-filled.html` | Home | Account with a live draft going |
| `home-empty.html` | Home | Brand-new account (ALL QUIET) |
| `duels-filled.html` | Duels list | One drafting duel (◎ 25 stake) |
| `duels-empty.html` | Duels list | Empty (NO BEEF YET) |
| `draft-room-active.html` | Draft room | Mid-draft, 3 picks in, clock running |
| `draft-empty.html` | DRAFT tab | No draft (WAR ROOM'S DARK) |
| `live-empty.html` | LIVE tab | Nothing live (NOTHING ON THE LINE) |
| `new-challenge.html` | New challenge | Terms + THE TERMS rail, 1 friend |
| `scoreboard.html` | Scoreboard | Real slate (live/schedule/final mix varies by capture time) |
| `game-detail.html` | Game detail | A real WNBA game (state varies by capture time) |
| `profile.html` | Profile / YOU | Account with a friend + record |
| `profile-empty.html` | Profile / YOU | Brand-new account (RIDING SOLO) |
| `verify-email.html` | Verify email | Unverified account |

Missing states worth knowing about (no snapshot yet): results/receipt screen
(needs a settled duel), live matchup with real scores (needs a drafted duel
during games), group-duel variants.

## Keeping these fresh

These are regenerated after visual changes ship — if you're editing and the
snapshot looks older than the live site, ask for a refresh before designing
against it.
