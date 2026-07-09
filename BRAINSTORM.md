# Heads Up Fantasy — Brainstorm & Working Doc

> **For the Claude agent working in this repo:** this is a living scratchpad for
> brainstorming and problem-solving — not a spec. Read it for context, help me think
> through the open questions below, and update it as decisions get made. When we
> settle something, move it from "Open questions" to "Decisions log" with the date.
> Keep `README.md` (the product memo) and `CLAUDE.md` (the build/status doc) as the
> sources of truth; this file is where thinking happens before it lands there.

_Last updated: 2026-06-30_

---

## Where things stand (one-paragraph snapshot)
Private beta on Expo Go. WNBA + MLB are live on real ESPN data with auto-settlement;
NBA + NFL are modeled but on placeholder pools (offseason). Core loop works end to
end: accounts → friends → challenge/duel → live snake draft → live scoring →
auto-settle → records/leaderboard/trophies. No money layer, no push notifications,
no deep-link onboarding yet. Goal right now: functional + fun.

---

## The guiding principle
**Engagement → Growth → Money.** Make the existing game sticky (notifications), then
grow it (deep-link invites), keep it from going dark (more in-season sports), and
only then monetize (rake). Don't run the money track in parallel — it's the reward
for winning the earlier steps, and it's legal work, not just code.

---

## Roadmap (working order, revisit freely)
1. **Real dev build (EAS).** The pivotal unlock — both push notifications and
   deep-link invites are blocked by Expo Go. Doing this once unblocks the two
   biggest growth levers. Do before anything below.
2. **Push notifications.** Highest engagement ROI for a turn-based 1v1 game:
   "it's your pick," "you were challenged," "you won." The game dies in silence
   without these.
3. **Deep-link invites + basic onboarding.** Today the only growth loop is friends
   who already have the beta. Deep links turn a shared result into a new user.
4. **Broaden live sports coverage** (NBA/NFL real feeds, injury/news status).
   Seasonality = the emptiness problem; wire the next sport *before* its season opens.
5. **Money layer (rake, wallets, KYC, compliance).** Last, and deliberately. Only
   after retention proves the free product is fun and sticky.

---

## Agent evaluation of this doc (2026-06-30)
**Verdict: the thinking here is sound.** Engagement→Growth→Money is the right
sequencing, the roadmap order is correct, and "money is legal work, not code" is
exactly right. Four things the roadmap under-weights, plus quick takes on the open
questions:

**Gaps / dependencies the roadmap should name explicitly:**
1. **The literal first blocker is an Apple Developer account ($99/yr).** "Dev build
   first" is right, but iOS device builds require Apple code-signing. That account
   (a you-action, ~a day to approve) gates step 1. Everything else is config I can do.
2. **Push + deep-link invites share the same gate** (the dev build), so once we're
   on it they can ship as **one push**, not strictly 2-then-3.
3. **Missing step: an on-device hardening/QA pass** belongs right after the dev
   build and *before* real users. The app grew fast and is largely device-unverified
   (bundle-verified only). Ship bugs to a real cohort and you poison the retention
   signal you're trying to measure.
4. **You can't measure engagement with seeded test accounts.** The whole chain
   assumes retention is *measurable*, but the beta is ~a few fake friends. So the
   true first milestone isn't "build push" — it's **dev build → small REAL cohort
   (5–15 friends on a preview build)**. Retention metrics only mean something after
   that. This reframes step 1 as "get real humans on a real build," with push as
   the thing that makes that cohort sticky.

**Quick takes on the open questions:**
- **Retention metric:** with a real cohort, watch two north stars — **duels started
  per active user per week** and **D7 return**. The money layer is justified when
  those hold *without you nagging people*. (Until there's a cohort, this is
  unanswerable — don't over-index on it yet.)
- **Push signal vs noise:** notify ONLY on actionable/rewarding events — *your pick
  is up* (with the clock), *you were challenged*, *your duel settled* (W/L). Do NOT
  notify on opponent-made-a-pick (too frequent) or generic game scores. Add quiet
  hours. Fewer, higher-signal pings.
- **Viral loop:** the shared artifact must deep-link to a **specific action**, not a
  generic home screen — tapping a shared result → install → app opens **pre-filled
  with a rematch/challenge from the sharer** → first duel in <2 min. Landing on
  "Home" kills the conversion.
- **ESPN plan B:** it's reliability *and* legal. Short term: resilience (retries,
  caching — partly there). Before money: **licensed provider is mandatory** (ToS),
  and it's a real recurring cost — put it in the money-layer P&L, not the "if it
  breaks" pile.
- **Money model:** premature to nail, but a **flat rake per duel** (a contest-entry
  fee) is cleaner and a *different regulatory posture* than a % of wagers — worth
  leaning into "skill contest fee," not "bet," for compliance framing. (Legal
  counsel territory, not ours to decide.)

**Refined near-term sequence (my recommendation):**
`Apple Dev acct (you)` → `EAS dev build + URL scheme (me)` → `on-device hardening
pass (us)` → `preview build to 5–15 real friends` → `push notifications` →
`deep-link invites + onboarding`. Sports-coverage + money stay where the doc has
them (later, gated).

---

## README cleanup checklist (small, do soon)
- [x] ~~Fix Kalshi vs "Kaoshi" spelling~~ — **non-issue**: already spelled "Kalshi"
      correctly in README + CLAUDE.md. We do mean **Kalshi** (the event-contracts
      exchange) and its **rake-not-wager** model. No change needed.
- [x] §3.6 → now reads "Two sports live, two modeled."
- [x] Added a "for dev setup see CLAUDE.md" pointer (CLAUDE.md already has the
      3-terminal startup + seed + test commands, so no need to duplicate in the
      product memo).
- [x] Added an "Accurate as of June 2026 / counts drift" note near the top.
- [x] Elevated the ESPN feed to a **ToS/legal + licensing** dependency (not just
      reliability) — flagged as a hard blocker for the money layer.

---

## Open questions (to brainstorm)
- **Retention:** what's the single metric that tells us the free product is sticky
  enough to justify the money layer? (e.g. duels/user/week, D7 return rate?)
- **Seasonality:** WNBA + MLB only — how do we keep users engaged in the gaps?
  More sports, or non-sport content (season-long ladders, historical replays)?
- **Push strategy:** which events actually earn a notification vs become noise?
- **Viral loop:** what's the ideal shared-result → install → first-duel path?
- **ESPN dependency:** what's plan B if the free feed breaks or rate-limits? Cost of
  a paid provider before there's revenue?
- **Money model specifics:** ~~flat rake per duel vs %~~ — **ANSWERED 2026-07-09:
  see MONEY-LEGALITY.md.** Verdict: "friends wager + rake" is illegal as sketched
  (rake kills social exemptions; floating pot fails the fantasy safe harbor; wager
  framing forfeits the entry-fee doctrine; CA AG hostile since July 2025). The
  legal shape = fixed entry fees + posted predetermined prizes as registered skill
  contests (the Splash Sports model), or rent a licensed partner's money layer.
  Staged plan in the doc; free beta stays correct for now.

---

## Working plan: quick wins → multiplayer duels (agreed 2026-07-02)
> **STATUS 2026-07-03: ALL FOUR BATCHES BUILT ✅** (commits b3796c8, 24de632,
> 6486768+135b766, 163decc, 60a6a12; backend deployed to Fly; 176 server tests
> green). Remaining: **on-device testing** — nothing past Batch 1 is
> device-verified, and the group flow needs 3-4 accounts. Notes vs the plan:
> group rematch skips the friends check between co-players (they just played
> together); a group that shrinks to 2 rematches as a classic 1v1; "below a
> shared top" counts as a LOSS in records, not a tie; new Party Crasher trophy.

**Batch 1 — quick wins (one session):**
- Draft-complete screen: "Watch Live Matchup" + "Back to Duels" buttons under the lineups.
- "Share matchup" (native text share) on Live Matchup + Duel Detail. (Share result already exists.)

**Batch 2 — draft-room upgrades (still 1v1, shippable alone):**
- LIVE PICK TICKER (recent picks strip, e.g. "P7 · Buddy → A. Wilson") + snake-order avatar dots.
- 1v1 keeps side-by-side rosters but FIT ON SCREEN (responsive half-width columns, no horizontal scroll).
- Shared components built here: ticker, order dots, roster sheet (avatar tabs → full roster per player).

**Batch 3 — multiplayer contests (1v1v1 up to 4), phased:**
- A. Data model: duel_participants table (seat, accept-status), migrate existing 1v1s, behavior unchanged.
- B. Engine: N-player snake, N-way ready check, auto-pick/pool sizing, channel auth.
- C. Mobile: multi-select opponents (max 3), N-seat lobby, 3+ players use the FLOW layout (ticker + my-slots strip + roster sheet); results become a ranked leaderboard (1st/2nd/3rd).
- D. Peripherals: records (win = 1st place; H2H stays 1v1-only), multi trophies, notification copy ("2nd of 4"), rematch-same-group. Counters stay 1v1-only in v1.

**Layout decision (2026-07-02):** hybrid — ≤2 players: side-by-side rosters (fitted, no scroll) + ticker; 3+: flow layout with rosters behind avatar sheet. Head-to-head tension is worth keeping visible in 1v1; four columns can't fit a phone.

**Group invite/accept design (agreed 2026-07-02, revertable):** host-centric seats.
- Host multi-selects up to 3 friends (friendship required with HOST only) + sets terms once. No counters in group matches (v1).
- Each invitee accepts/declines their own seat independently; invite screen shows the other seats' statuses.
- Declines SHRINK the match (4→3→2); below 2 total → auto-cancel. Non-responders can't wedge it: host gets "Start with current group" (drops pending invitees, needs ≥2 in) + cancel anytime.
- Draftable when every non-declined seat accepted (∧ ≥2). Pushes: seat invite → each invitee; "everyone's in" → all; shrink notice → host. Rematch re-invites the same group (tapper becomes host).

## Roadmap of record (agreed 2026-07-09)
Money verdict shaping this: see MONEY-LEGALITY.md — money arrives via fixed-entry
tiers + posted prizes (skill-contest framing), gated on traction, never as raked
wagers. Coin system (PR #1) is stage one of that path.

- **Now → mid-July — coins + polish:** verify & deploy the coin merge (tests,
  refund paths, OTA-vs-rebuild check) **[ON HOLD until Saad says go]**; fix the
  chip-clipping bug (OTA-marker diagnostic first); brothers play real coin duels —
  first live test of "do stakes make it more fun."
- **Late July — fun pass + growth plumbing (Sessions 2–3, all OTA):** draft-room
  emoji reactions; live-matchup juice (game-state chips, score flashes); invite
  links live end-to-end (/d/… foundation already deployed); run-it-back rematch
  from rivalry records; uptime pinger for on-time settlement. End of July = app
  feature-complete for the friends era.
- **August — NFL month (the one hard deadline):** NFL scoring model, ~1,700-player
  rosters, stat parsing, settlement provider — tested live against preseason
  (early Aug). TestFlight so the cohort grows past the 4 registered phones. Coin
  seasons/weekly leaderboards so stakes have rhythm.
- **September — NFL kickoff = the real test:** season gating auto-flips NFL on
  (~Sept 10). Retention numbers start meaning something: duels/user/week + do
  people return unprompted (the north stars from the 2026-06-30 review).
- **Q4 2026 — the money gate (decision, not date):** if retention holds through
  October → gaming-attorney consult + licensed-partner conversations (Splash
  Partner Solutions) → real-money tiers via partner, realistically early 2027,
  geofenced (CA excluded until the Bonta fight resolves). If not → keep iterating
  free; the compliance clock never starts.
- **2027 — own the money layer (only at scale):** registered operator in
  cheap-tier states (~$1.5–3k gov fees; ~$50–150k all-in) when partner rev-share
  math justifies it.
- Constant threads: Sentry rides the next rebuild; NBA in October (reuses the
  WNBA model cheaply); password rotations (still on Saad).

## Ideas parking lot (unfiltered, no commitment)
- Positionless / UTIL-heavy lineup presets (Saad, 2026-07-01): keep classic slots
  as the default, but offer a mode where most/all slots are UTIL — draft anyone,
  pure best-ball vibes. (Context: we added a required C slot to wnba_standard and
  kept UTIL; this is the "lean further into UTIL" variant as its own preset.)
- Async "walk-away" drafts as the default for casual play (queue + long clock already exist).
- Rivalry framing: surface head-to-head streaks harder ("you're down 3-1 to buddy").
- A weekly friend leaderboard reset for recurring stakes.
- Spectator mode for a friend's live duel.

---

## Decisions log
_(Move settled items here with a date and a one-line "why.")_
- _2026-06-30 — Established Engagement→Growth→Money sequencing; EAS build is the first unlock._
- _2026-06-30 — Agent reviewed the doc: roadmap validated. Surfaced the real gating
  chain — **Apple Dev acct ($99) → dev build → on-device hardening → small REAL
  cohort → push** — because engagement is unmeasurable on seeded accounts. Money
  layer confirmed to REQUIRE a licensed data provider (ESPN free feed is a ToS
  blocker, not just a reliability risk). README accuracy fixes applied._
- _2026-06-30 — "Kalshi" spelling confirmed correct (checklist item was a misread);
  model = event-contracts-style flat rake per contest, not wager-based._
