# Live-app snapshots — what the web app ACTUALLY looks like right now

Each file here is the real rendered HTML of one screen, captured from
production and made self-contained (styles inlined, LiveView plumbing
stripped). **This is the current implementation, not the design mockups** —
use these when you want Claude Design to edit against reality.

## How to use with Claude Design

1. Start your session by pasting the design brief (`docs/design-brief.md`).
2. Attach (or paste the contents of) the snapshot for the screen you're
   editing and say: *"This is the current live implementation of the <name>
   screen. Edit from this."*
3. When you're happy, export per screen as usual and hand it back.

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
