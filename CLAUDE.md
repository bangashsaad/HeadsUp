# Heads Up Fantasy

A 1-on-1 fantasy sports app: challenge a friend to a head-to-head fantasy draft.
(Kalshi-style monetization — a small rake per contest, not on wagers — but **money
is deferred for the beta**; the goal right now is functional + fun.)

## Stack
- **Mobile** (`mobile/`): React Native via **Expo SDK 54**, JavaScript.
- **Backend** (`server/`): **Elixir + Phoenix 1.8**, a JSON API (realtime Phoenix
  Channels coming for the live draft).
- **Database**: **PostgreSQL 16**.

Phone ⇄ Phoenix API ⇄ Postgres.

## Running it in development (you need TWO servers + Expo)
Open three terminal tabs:
1. **Backend (data):** `cd server && mix phx.server`  → port 4000 (binds 0.0.0.0 so the phone can reach it).
2. **App bundler (Metro):** `cd mobile && npx expo start`  → port 8081.
3. Open **Expo Go** on your iPhone (same Wi-Fi), scan the QR.

If the app says "problem connecting to the server," Metro (#2) isn't running.
If the app loads but login/data fails, Phoenix (#1) isn't running.

Prereqs already installed on this Mac: Elixir, PostgreSQL 16 (brew service), Node.

## Gotchas (learned the hard way)
- **Stay on Expo SDK 54** while previewing with App Store Expo Go — newer SDKs fail
  with "incompatible with this version of Expo Go." Install mobile libraries with
  `npx expo install` (NOT plain `npm install`) so versions stay SDK-54-compatible.
- The app **auto-detects the Mac's IP** from Expo (`mobile/src/api/client.js`) — no
  hardcoded address to update when the network changes.
- Postgres: `postgresql@16` is on PATH via `~/.zshrc`; a `postgres` superuser role
  exists so Phoenix connects with default config. Dev DB is `heads_up_dev`.
- Seed the player pool: `cd server && mix run priv/repo/seeds.exs` (idempotent).

## Test accounts (dev DB)
- `nyel@example.com` / `supersecret123`
- `buddy@example.com` / `buddypass123`
(nyel ↔ buddy are friends; `saadbangash` is a phone-created account, also friends.)

## Status — built so far
- **Phase 0 — Full-stack hello:** Phoenix + Postgres + Expo wired end to end. ✅
- **Phase 1 — Accounts + Friends:** token-based signup/login (bcrypt, stay-logged-in),
  friend search / request / accept. ✅
- **Phase 2 — Sports & player pool:** 3 sports, ~81 seeded players, browse + filter. ✅
- **Phase 3 — Challenges (duels):** create a challenge with terms (sport, roster size,
  draft time) + per-sport scoring chart; accept / decline / cancel / **counter**. ✅

## Next steps
- **Phase 4 — LIVE DRAFT ENGINE (the centerpiece):** when a duel is accepted, both
  players enter a live draft room — snake order, a ticking pick clock, auto-pick on
  timeout, picks syncing to both phones instantly (Phoenix Channels + a GenServer per
  draft). Async draft falls out of the same engine (long clock).
- **Phase 5 — Scoring + settlement:** plug in a stats provider, compute fantasy points
  from the agreed scoring chart, declare a winner once stats are final.
- **Phase 6 — UI polish** (e.g. the Players screen is plain right now).
- **Later:** auction drafts, the money/rake layer, email verification, rate limiting,
  token expiry, KYC/regulation.

## Architecture quick map
- **Backend contexts:** `Accounts` (users + API tokens), `Social` (friendships),
  `Sports` (players/games), `Contests` (duels + scoring defaults). Controllers render
  JSON; `PublicUserJSON` exposes only id+username (never email).
- **Mobile:** `src/api` (server calls), `src/auth` (AuthContext + SecureStore token),
  `src/navigation` (AuthStack when logged out; MainTabs = Friends | Duels | Sports,
  each its own stack), `src/screens`, `src/components`, `src/theme.js` (colors/styles).
