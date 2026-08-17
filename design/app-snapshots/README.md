# iPhone-app snapshots — what the APP actually looks like right now

One file per screen of the iOS app, each **self-sufficient**: a summary of the
design tokens, the UI-kit cheat sheet, and the screen's real React Native
source (plus any shared components it uses). This is the current
implementation — use these to have Claude Design edit the app against reality.
(Website versions live in `../snapshots/`.)

## How to use with Claude Design

1. Start the session by pasting the design brief (`docs/design-brief.md`).
2. Paste the screen's file from this folder (or ask Claude Code to paste it
   in chat) and say: *"This is the current iPhone screen — real source.
   Redesign it as a phone-frame mockup."*
3. Export per screen as usual and hand it back — it gets ported into React
   Native.

`00-design-tokens.md` is the full design system (complete theme.js + every UI
primitive's source) for sessions that redesign the primitives themselves.

## The screens (tab bar: HOME · DUELS · DRAFT · LIVE · FRIENDS · YOU)

| File | Screen | Size |
|---|---|---|
| `01-home.md` | Home (HOME tab) | 31 KB |
| `02-duels.md` | Duels list (DUELS tab) | 26 KB |
| `03-new-challenge.md` | New challenge | 30 KB |
| `04-duel-detail.md` | Duel detail | 24 KB |
| `05-counter.md` | Counter offer | 16 KB |
| `06-draft-hub.md` | Draft hub (DRAFT tab) | 12 KB |
| `07-draft-room.md` | Draft room (the centerpiece) | 59 KB |
| `08-live-hub.md` | Live hub (LIVE tab) | 13 KB |
| `09-scoreboard.md` | Scoreboard (inside the LIVE tab) | 22 KB |
| `10-game-detail.md` | Game detail | 33 KB |
| `11-compare.md` | Compare players | 12 KB |
| `12-player-profile.md` | Player profile | 12 KB |
| `13-live-matchup.md` | Live matchup | 24 KB |
| `14-results.md` | Results / receipt | 24 KB |
| `15-you.md` | Profile (YOU tab) | 21 KB |
| `16-friends.md` | Friends (its own tab) | 8 KB |
| `17-friend-groups.md` | Friend groups | 13 KB |
| `18-add-friends.md` | Add friends (search) | 8 KB |
| `19-requests.md` | Friend requests | 7 KB |
| `20-rival-profile.md` | Rival profile | 13 KB |
| `21-leaderboard.md` | Friend standings | 7 KB |
| `22-coin-wallet.md` | Coin wallet | 10 KB |
| `23-settings.md` | Settings | 10 KB |
| `24-change-password.md` | Change password | 6 KB |
| `25-verify-email.md` | Verify email | 6 KB |
| `26-login.md` | Log in | 7 KB |
| `27-signup.md` | Sign up | 8 KB |
| `28-forgot-password.md` | Forgot password | 7 KB |

| `29-rivalry.md` | Rivalry page | 14 KB |

Not included: `PlayersScreen`, `PlayerSearchScreen`, `SportsHomeScreen` —
legacy files no navigator reaches anymore.
