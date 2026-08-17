# Heads Up Fantasy — Design Brief

**Paste this whole document into Claude Design at the start of any design
session.** It is the source of truth for what the product actually does. Design
against these facts exactly — do not invent values, features, or stats that
aren't listed here. Where you have a better product idea, flag it in a note
next to the design instead of silently drawing it.

## What this is

1-on-1 (up to 4-player) fantasy sports duels. Challenge a rival, snake-draft
real players from a real slate on a ticking clock, watch both rosters score
live off real box scores, winner takes the coin pot and the rivalry lead.
Trash talk built in. Two clients — an iOS app and the web app at
headsupfantasy.com — one backend. **Every design ships to both.**

## Design language (already live — match it)

- **Fonts:** Archivo (body), Archivo Black italic (wordmark "HEADSUP"),
  Barlow Condensed italic 700/800 (display type, ALL-CAPS headings, scores)
- **Palette:** bg `#07080C`/`#0A0B10`, card `#12141D`, elevated `#191C28`,
  border `#252A3A`, subtle border `#1A1E2B`, text `#F4F5F7`, dim `#B9BECF`,
  muted `#8B91A7`, faint `#565D73`, **accent lime `#C8FF2E`** (use
  `var(--acc,#C8FF2E)`), purple `#7C5CFF` / `#9F8BFF`, danger `#FF4557`,
  warning amber `#FFB021`, cyan `#22E5FF`
- **Shapes:** 999px pill buttons/chips, 12–18px card radii, 1px borders,
  radial/linear gradient washes on hero cards
- **Motion:** blink (live dots), pulse (primary CTA), rise (screen entry),
  marquee (top ticker, 26s)
- **The coin glyph is ◎** (e.g. `◎ 25`). Coins are a free in-app score — never
  imply purchases or cash value.

## Hard facts — never contradict these

| Thing | Truth |
|---|---|
| Leagues | 🏀 WNBA, ⚾️ MLB, 🏈 NFL, 🏀 NBA — off-season leagues show but are dimmed/disabled ("OFF-SEASON") |
| Roster sizes | **Per sport**: 🏀 5 or 7 · 🏈 5 or 7 · ⚾️ **6 or 9** (6 = one pitcher + five bats w/ UTIL; 9 = "the diamond": P·C·1B·2B·3B·SS·3 OF, no UTIL) — nothing else |
| Stakes | **No stake / ◎ 25 / ◎ 100** — there is no 50. Pot = stake × number of drafters |
| Pick clock | **15 / 30 / 60 seconds** — no minute/hour clocks |
| Drafters per duel | **1v1 up to 4 total** ("call out up to 3 rivals"). Never 8 |
| Slates | Basketball/baseball pick a **day** ("Tonight", "Tomorrow", "Sat Aug 16"); football picks a **week** ("Preseason Wk 2", "Week 3"). One slate per duel |
| Draft | Snake order, coin flip for first pick, auto-pick on clock expiry, per-position slots (e.g. G/G/F/F/FLEX) |
| Duel statuses + badge language | pending→you answer: **RESPOND** (cyan #22E5FF) · pending→you sent: **SENT** (gray) · **COUNTERED** (purple #A794FF, "terms changed") · accepted: **READY** (lime) · **DRAFTING** (red, blinking) · drafted/live: **IN PLAY** (cyan, blinking) · then settled W/L/T, declined, cancelled, expired |
| Countering | 1v1 duels only. A counter sends the terms back to the other person |
| Players | Real athletes with headshots, position, team, FPG projection, next-game time, and **injury tags: OUT (red) / GTD (amber)** — injuries must be visible anywhere a player can be picked |
| Scoring | Real box scores; live totals tick during games; settlement is automatic when the last game ends |
| Coins | 1,000 on signup, small daily comeback bonus when broke. Win = +stake, loss = −stake (shown amber ◎ on wins) |
| Records | W–L (+ties), win %, streaks (🔥 W3), per-rival head-to-head with last-duels history, splits by league/roster/field. **There is no "avg place" stat** |
| Friends | Search → request → accept/decline ("WANTS IN" inbox). Private friend groups as tabs (e.g. HOOPS CREW). Blocking exists |
| Email verification | Required before dueling — a 6-digit code screen exists; unverified users get bounced to it |
| Account | Change password, sign out, delete account (permanent, anonymizing) — these controls must exist on the profile screen |
| Trash talk | Per-duel text chat, 280-char max, phone + web both talk in the same thread. Six quick-reaction emoji exist in the draft room: 🔥 😂 😭 🥶 💀 👑 |

## The screens that exist (routes are live)

landing `/` · home `/app` · duels `/app/duels` · new challenge `/app/new` ·
draft room `/app/draft/:id` · live duel `/app/live/:id` · results
`/app/results/:id` · scoreboard `/app/games` · profile `/app/you` · verify
email `/app/verify`. App shell: 230px sidebar (HOME / DUELS+count / DRAFT /
LIVE+badge / SCOREBOARD / YOU), pulsing + NEW CHALLENGE, ◎ COIN WALLET chip,
profile row, and the marquee ticker across the top.

## Rules for every design you produce

1. **Design every state, not just the happy path.** Each screen needs: filled,
   **empty** (see below), loading-ish (scores pending), and error where
   relevant. A screen with no empty state is incomplete.
2. **Empty states must be alive — never one line of gray text.** This is a
   standing product rule. An empty state should do at least one of: show a
   playful illustration/typographic moment in the design language, preview
   what the screen will look like with ghost/skeleton content, or offer the
   next action as a real CTA (e.g. empty duels → a mini "call someone out"
   moment, not "No duels yet"). Make emptiness feel like the start of
   something, not the absence of everything.
3. **Annotate every interaction.** Next to anything clickable, note where it
   goes or what it does ("game card → box score with fantasy leaders",
   "REMATCH → sends same terms"). Unannotated elements get built as static.
4. **Use realistic demo data** consistent with the hard-facts table (WNBA/MLB/
   NFL names, 5/7 slots, ◎ 25/◎ 100 stakes, seconds clocks, max 4 drafters).
5. **Group duels exist** (3–4 players). Where a screen shows a duel, consider
   how the 4-player version reads (seat count "2/4 in", ranked standings
   🥇🥈🥉 in results).
6. **Don't design these (deliberately out of scope):** first-to-accept
   challenges (deferred until the clan-chat build), buying coins, player-pool
   browsing inside the scoreboard, any stat not in the facts table.

## How to hand a design back

Export **per screen** — the code/source for the changed screen only, not one
bundled file of everything. If only details changed on an existing screen, a
note ("duels card: badge moved above the meta line, avatar 44px") is enough.
New screens: full markup + a one-line list of its interactions and states.
