# Heads Up Fantasy — Product & Feature Memo

> **Purpose of this document:** a self-contained snapshot of everything the app
> currently does, so a product/market-research collaborator can understand the
> product without reading the code and help brainstorm new features, positioning,
> and monetization. It describes what is **built and working today**, what is
> **stubbed/deferred**, and the **constraints** shaping decisions.
>
> _Accurate as of June 2026. Concrete counts (players, tests, schedule window)
> drift as the product and season move; treat them as "order of magnitude."_
> _For dev setup / how to run it, see `CLAUDE.md`._

---

## 1. What it is (concept)

**Heads Up Fantasy** is a **1-on-1, head-to-head fantasy sports app**: you
challenge a friend to a quick head-to-head fantasy *duel*, draft a small lineup
against each other live (snake draft with a ticking clock), and the winner is
declared **automatically** once the real games finish — scored on **real stats**
from a live sports feed.

Think "fantasy football league" compressed into a **fast, personal, 1v1 duel you
can start with one friend in minutes**, instead of a season-long, 10-person
commitment. It's built around **rivalry and bragging rights** between friends.

- **Format:** always 2 players, head-to-head.
- **Speed:** a duel can be created, drafted, and settled in the span of a single
  game slate (or set to run async over hours/days).
- **Real data:** lineups are scored on actual box scores, not projections.

### Monetization intent (deferred)
The long-term model is **Kalshi-style**: a small **rake per contest** (a flat cut
for hosting the duel), **not** a cut of wagers. **All money is deferred for the
beta** — today the product is entirely free and the goal is "functional + fun."
No payments, wallets, or KYC exist yet.

### Platform / stage
- **Mobile app** (iOS, React Native / Expo) — the whole product is phone-first.
- **Currently a private beta** run through Expo Go (no App Store presence yet).
- Backend is a JSON API + realtime websockets; data lives in PostgreSQL.

---

## 2. The core loop (end-to-end user journey)

1. **Sign up / log in** (username, email, password; stays logged in).
2. **Add friends** (search by username → send request → they accept).
3. **Challenge a friend to a duel**, choosing the terms: sport, lineup size &
   shape, pick-clock speed, draft time, and the fantasy scoring chart.
4. Friend **accepts** (or **declines** / **counters** with different terms).
5. Both players enter a **live draft room**: a coin flip sets the order, then they
   **snake-draft** their lineups against a ticking per-pick clock.
6. When the draft finishes, **lineups lock** and a **scoring window** opens.
7. As the real games play, both players can **watch live scoring** tick up
   player-by-player.
8. Once the games in the window are final, the app **auto-settles**: real stats →
   fantasy points → **winner declared**, with a full scoreboard.
9. **Rematch** in one tap, **share** the result, and your **record / trophies /
   leaderboard** update.

---

## 3. Feature inventory (what's built today)

### 3.1 Accounts & authentication
- Username/email/password signup and login.
- Token-based auth; **stays logged in** across app restarts (secure token
  storage on device).
- Change password from settings.
- Passwords hashed (bcrypt). Email is never exposed to other users (only
  id + username are public).

### 3.2 Friends / social graph
- **Search users** by username.
- **Send / accept friend requests**; incoming-request list.
- Friends list; you can **only challenge people you're friends with**.
- **Invite a friend** — share your username via the native share sheet (a text
  invite; true tap-to-onboard deep links are pending a real app build — see §6).

### 3.3 Challenges / duels (the matchmaking layer)
- **Create a challenge** to a friend with fully configurable **terms**:
  - **Sport** (see §4).
  - **Lineup template** — a preset roster shape (e.g. a "quick" 3-slot lineup or a
    "standard" 5–7-slot lineup), which fixes how many players you draft and what
    positions are required.
  - **Pick clock** — how long each pick has: **live** (30 / 60 / 90 seconds) or
    **async** (4h / 12h / 24h) for a walk-away draft.
  - **Draft start time.**
  - **Scoring chart** — the per-category fantasy point values (ships with a
    sensible per-sport default; can be overridden and is then frozen onto the duel).
- **Lifecycle:** pending → accepted / declined / cancelled / **countered**.
  - **Counter-offer:** the recipient can counter with new terms, which creates a
    fresh challenge back in the other direction (linked to the original).
  - The challenger can **cancel** a pending challenge.
- **Duels tab** organizes everything into **Active** vs **Past**, each grouped
  (e.g. "Needs your response," "In progress," "Completed," "Declined & cancelled").
- **Rematch** — from a finished duel, one tap re-challenges the same opponent with
  the **same terms** (a fresh duel, linked back to the original).

### 3.4 Live draft engine (the centerpiece)
A real-time, two-phone draft experience:
- **Lobby / ready-check:** both players mark ready; then a **coin flip** decides
  who picks first.
- **Snake order:** standard snake (1-2-2-1-1-2…) across the roster.
- **Per-pick clock:** a visible ticking countdown (circular timer). Works for both
  fast live clocks and long async clocks.
- **Position-aware picking:** you can only draft a player into a slot their
  position is eligible for (guards into guard slots, FLEX/UTIL accept multiple);
  illegal picks are rejected.
- **Auto-pick on timeout:** if your clock runs out, the app drafts for you —
  **your queue first**, otherwise the best available player that fits an open slot.
- **Draft queue (pre-ranking):** during the draft you can **★-star players** to
  queue them; queued players pin to the top of your board and are the ones
  auto-pick takes first (in your order). The queue is **private** to you and is
  ideal for **async drafts** — set your board and walk away.
- **Live sync:** picks appear on both phones instantly (realtime websockets); the
  board, both lineups, and the clock stay in sync.
- **Resilience:** disconnect/reconnect handling with a grace window; the draft
  survives a server restart by replaying picks.
- **Player search + position filters** inside the draft room, and an info button
  to open any player's full profile mid-draft.

### 3.5 Scoring & settlement (auto-decided winners on real stats)
- When a draft completes, lineups **lock** and a **scoring window** freezes onto
  the duel (default ~24 hours; the window is the set of real games that count).
- A background worker **sweeps** for duels whose window has closed and **settles**
  them: it pulls each drafted player's **real stats** from the live feed, computes
  fantasy points against the duel's frozen scoring chart, and **declares a winner**
  (or a tie).
- **Draft-risk rule:** a drafted player who doesn't play (injured/benched/DNP)
  scores 0 — you're on the hook for your picks.
- The result is a full **scoreboard**: both team totals, per-player points, and
  each player's stat line, stored permanently.
- **Results screen:** win/tie/loss banner with animation, both lineups, per-player
  scoring, plus **Rematch** and **Share result** actions.

### 3.6 Sports & player data (real, from a live feed)
- **Two sports live, two modeled:** WNBA + MLB are fully live; NBA + NFL are
  modeled (schemas, scoring, lineups) but running on placeholder data (offseason).
- **WNBA and MLB are LIVE with real data** — real rosters (~200 WNBA / ~780 MLB
  players across all real teams), real season stats, real box scores, and real
  settlement. These are the two **in-season** sports.
- **NBA and NFL** currently use placeholder pools (they're offseason; wiring their
  real feeds + scoring is a known future step — see §6).
- Every real player carries a **projection = FPPG (fantasy points per game)**,
  computed from their actual season game log under the sport's default scoring.
  This is the headline number used to rank the draft board (replaced an earlier
  arbitrary 1–100 rating).

### 3.7 Games tab (schedule + live box scores)
- **Upcoming Games** feed with a **WNBA / MLB switcher**: real scheduled games for
  the next ~8 days, grouped by day, with times / live / final status and scores.
- Tap a game:
  - **Upcoming game →** both teams' **draftable rosters** with each player's FPPG
    (a scouting view for who to draft).
  - **Live or final game →** a full **ESPN-style box score** — every player, all
    the normal stat columns, **plus a "FAN" (fantasy points) column**. Refreshes
    live while the game is in progress. (Baseball shows batting + pitching tables.)

### 3.8 Player profiles, search & comparison
- **Player profile:** season summary tiles (e.g. PPG/RPG/APG for basketball;
  AVG/HR/RBI for hitters; ERA/K/IP for pitchers), season FPPG, and a **fantasy game
  log** — every game with the box line and the fantasy points it earned.
- **Player search:** search any real player by name (cross-sport) → open profile.
- **Player comparison:** pick two players and see their season stats **side by
  side**, with the leader in each row highlighted (a scouting/draft aid).
- Profiles are reachable from game rosters, box scores, the draft board, results
  lineups, and search.

### 3.9 Live scoring & live matchup (watch a duel unfold)
- While a duel is drafted-but-not-settled, both players can **watch it live**:
  - **Live score card** on the duel screen (running totals, who's leading, how many
    games are final/live/upcoming).
  - **Live Matchup screen:** both lineups laid out with **each player's live fantasy
    points and stat line**, updating every ~15s, auto-advancing to the final result
    once the duel settles.
- (WNBA updates continuously mid-game; MLB updates per completed game — a feed
  limitation, not a bug.)

### 3.10 Home dashboard
The app opens to a **Home tab** that surfaces what needs attention:
- **"Your move"** action cards — challenges to respond to, drafts to start/resume.
- **Record strip** — your W-L, current streak, recent form.
- **Latest results** — your most recent settled duels.
- **Today's games** — a quick strip of the day's slate.

### 3.11 Records, leaderboard & achievements (competitive stakes)
- **Record:** overall W-L-T, win %, points for/against, current streak, recent form.
- **Head-to-head:** your record vs each friend you've faced.
- **Leaderboard:** standings among you and your friends, ranked by wins (🥇🥈🥉).
- **Achievements / trophies:** 8 derived trophies with progress toward locked ones —
  First Win, Hat Trick (3 straight), On Fire (5 straight), Veteran (10 played),
  Century (100+ in a duel), Sharpshooter (draft a 50-pt player), Blowout (win by
  30+), Rivalry (face one opponent 5×).

### 3.12 Profile, settings & polish
- **Profile tab:** your record card, head-to-head, trophy grid, and menu.
- **Settings:** appearance (**system / light / dark** theme, fully themed app),
  haptics toggle, change password, about, log out.
- **Sharing:** invite a friend, share a result (native share sheet).
- Consistent design system (cards, badges, chips, empty states, skeleton loaders,
  entrance animations, haptic feedback).

---

## 4. Sports & scoring model (the fantasy math)

Each sport ships with a **default scoring chart** (the challenger can tweak it; the
agreed chart is frozen onto the duel). A player's fantasy points = the sum over the
chart's categories of `stat × value`.

- **WNBA / NBA** (identical): point **1**, rebound **1.25**, assist **1.5**, steal
  **2**, block **2**, three-pointer **0.5**, turnover **−0.5**.
- **MLB:** single **3**, double **5**, triple **8**, home run **10**, RBI **2**,
  run **2**, walk **2**, stolen base **5**, inning pitched **2.25**, strikeout
  (pitching) **2**, win **4**, earned run **−2**.
- **NFL:** passing yard **0.04**, passing TD **4**, interception **−2**, rushing
  yard **0.1**, rushing TD **6**, reception **1** (PPR), receiving yard **0.1**,
  receiving TD **6**, fumble lost **−2**.

**Lineup shapes** are position-constrained presets, e.g.:
- WNBA "standard" = Guard, Guard, Forward, Forward, UTIL.
- MLB "standard" = SP, RP, C, corner infield, middle infield, OF, UTIL.
- Each sport also has a smaller "quick" template for faster duels.

**FPPG** (fantasy points per game) is each player's real season fantasy average
under the default chart — the single number used to rank and auto-pick.

---

## 5. Technical foundation (brief, for context)

- **Mobile:** React Native via Expo (iOS-first), one themed design system.
- **Backend:** Elixir / Phoenix JSON API + **realtime channels** (websockets) for
  the live draft; a supervised process per active draft is the source of truth.
- **Database:** PostgreSQL.
- **Live sports data:** pulled from a public ESPN feed (schedules, rosters, box
  scores, game logs). No paid data provider yet.
- **Settlement** is automatic and idempotent (a background worker), scored by a
  pure, deterministic fantasy-math engine.
- The codebase is heavily tested (130+ backend tests) and organized into clear
  domains: Accounts, Social (friends), Contests (duels), Drafts (the live engine),
  Sports (players/games/box scores), Settlement (scoring), Stats/Home/Achievements.

---

## 6. Not built yet / deferred / known gaps

These are **intentional gaps**, useful for spotting opportunities:

- **Money layer (the whole business model):** rake, wallets, deposits/withdrawals,
  payouts, KYC/eligibility, and any regulatory/compliance work — **all deferred**.
  The product is free today.
- **Push notifications:** not built. This is arguably the biggest engagement gap
  for a turn-based game ("it's your pick," "you were challenged," "you won"). Blocked
  in the current beta harness; **requires a real (dev) app build**.
- **Deep-link invites / viral onboarding:** you can share a text invite, but a link
  that onboards a brand-new user (installs the app → lands on your challenge)
  **requires a real app build + public presence** (App Store / web landing). Today
  you can only play with people who already have the beta and are your friends.
- **Real NBA & NFL data:** modeled but running on placeholder pools until their
  seasons + real feeds are wired (they're offseason). Only WNBA + MLB are live.
- **Injury / news status** on players: the data source exists but isn't wired in yet.
- **Onboarding / how-to-play walkthrough:** only a basic in-app blurb today.
- **Auction drafts:** the spec anticipates them; only snake drafts exist.
- **Group / multiplayer formats:** everything is strictly 1-on-1. No leagues,
  tournaments, brackets, or multi-week series.
- **Live game event alerts** ("your player just scored"): not built.
- **Email verification, rate limiting, token expiry:** deferred hardening.

---

## 7. Constraints & context to keep in mind when brainstorming

- **It's a private beta** (Expo Go), so anything needing a real build, App Store, or
  public URL is a step-change, not a quick add.
- **Only 2 in-season sports are live** (WNBA, MLB), so seasonality matters — the
  product is "empty" for a sport in its offseason unless we broaden coverage.
- **Strictly 1v1** is a core design choice (fast, personal). Multiplayer would be a
  big expansion, not a tweak.
- **Real-data dependency (reliability AND legal):** the "auto-settle on real box
  scores" magic depends on a **free, undocumented public feed**. Beyond
  scale/reliability/coverage, this is a **Terms-of-Service / licensing risk**:
  it's fine for a free beta, but **monetizing on it is not viable** — the money
  layer effectively requires switching to a **licensed data provider** (a real,
  ongoing cost to budget into the business case).
- **No money yet**, but the intended model (per-contest rake, not wager-based) shapes
  what "fair" and "regulated" look like later.

---

## 8. One-line pitch

> *Challenge a friend to a 60-second-to-set-up, head-to-head fantasy duel — draft a
> tiny lineup live, watch it score on real box scores, and settle bragging rights
> by tonight.*
