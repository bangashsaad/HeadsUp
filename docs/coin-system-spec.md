# HeadsUp Coins — functional spec (v1)

An in-house virtual currency. Free-only for the beta: coins cannot be bought,
cashed out, or transferred — which keeps them legally inert (no consideration,
no prize of value) in all 50 states. The ledger is adapted from Jeb's
double-entry engine so a real-money layer can later slot in without
re-architecture.

## Hard rules (inherited from Jeb, adapted)

1. Coins are integers. No floats, no fractions.
2. Every coin movement goes through `Coins.post/1`. No direct balance writes.
3. `coin_entries` and `coin_txns` are append-only (DB triggers). Corrections
   are new reversing transactions.
4. Every transaction sums to zero (app validation + deferred DB constraint
   trigger).
5. No wallet ever goes negative (row-locked overdraft guard).
6. Every product-triggered movement carries an idempotency key; replays return
   the original transaction.
7. Coin movements ride **inside the same DB transaction** as the duel status
   change that causes them — a duel can never change state without its coins
   moving, or vice versa.

## Ledger internals

**Tables** (bigint ids, single currency — no `currency` column):

- `coin_accounts` — `kind` (`wallet | system`), `code` (system only, unique),
  `owner_user_id` (wallet only, unique). Seeded system accounts: `mint`
  (issuance counterparty), `escrow.duels` (stakes in play). Later: `sink.rake`.
- `coin_txns` — `kind`, `idempotency_key` (unique), `metadata` (map; always
  carries `duel_id` for duel movements).
- `coin_entries` — `txn_id`, `account_id`, `amount` (signed: debits positive,
  credits negative; wallets/escrow are credit-normal, natural balance is the
  negated sum).
- `coin_balances` — cached signed balance + entry_count per account; truth is
  always re-derivable from entries (`Coins.Integrity.check/0`).

**Transaction kinds:** `:grant`, `:stake`, `:refund`, `:payout`, `:burn`,
`:reversal`.

**Economy constants** (module attributes, one place):

| Constant | Value |
|---|---|
| Signup grant | 1,000 |
| Comeback bonus | +100 when balance < 25, max once per ET calendar day |
| Stake bounds | integer, 0 ≤ stake ≤ 10,000 |
| Mobile stake presets | Friendly (0) · 25 · 100 · 500 |

A duel's stake is **uniform** — every participant stakes the same
`duels.stake_coins` (renamed from the vestigial `wager_cents`). Pot = stake ×
number of players who staked.

## The complete action catalogue

### A. Coin-native actions (no duel involved)

| # | Action | Trigger | Movement | Idempotency key |
|---|--------|---------|----------|-----------------|
| A1 | Signup grant | successful `POST /api/register` | mint → new wallet, 1,000 | `grant:signup:{user_id}` |
| A2 | Backfill grant | `mix coins.backfill` (one-off release task) | mint → each existing wallet, 1,000 | `grant:signup:{user_id}` (same key ⇒ rerun-safe, can never double-grant) |
| A3 | Comeback bonus | lazily on authenticated `GET /api/me` when balance < 25 and none granted today (ET) | mint → wallet, 100 | `grant:comeback:{user_id}:{YYYY-MM-DD}` |
| A4 | Read balance | `GET /api/me` (also login/register responses) | none | — |
| A5 | Read history | `GET /api/coins` — balance + last 50 entries (± natural amount, kind, duel_id, timestamp) | none | — |
| A6 | Dev grant | `mix coins.grant <email> <amount>` (dev tooling only) | mint → wallet | none (deliberate) |

### B. Duel actions (S = `stake_coins`; S = 0 skips all coin steps)

| # | Action | Endpoint | Coin guard | Movement |
|---|--------|----------|-----------|----------|
| B1 | Create 1v1 challenge | `POST /api/duels` | challenger balance ≥ S, else 422 and the duel is **not created** | challenger wallet → escrow, S |
| B2 | Create group challenge (host + up to 3 invitees) | `POST /api/duels` | host balance ≥ S | host wallet → escrow, S |
| B3 | Accept (1v1 opponent) | `POST /api/duels/:id/accept` | opponent balance ≥ S, else 422 and the duel **stays pending** | opponent wallet → escrow, S |
| B4 | Accept (group seat) | same | seat balance ≥ S, else 422 and the seat **stays invited** | seat wallet → escrow, S |
| B5 | Decline (1v1 opponent) | `POST /api/duels/:id/decline` | — | escrow → challenger, S (refund) |
| B6 | Decline (group seat) | same | seat never staked — nothing to refund for them | none; but if this decline kills the duel (every seat declined), refund host + any already-staked seats |
| B7 | Cancel (challenger/host, from pending) | `POST /api/duels/:id/cancel` | — | refund **every** staked wallet |
| B8 | Counter (1v1 opponent, may change S → S′) | `POST /api/duels/:id/counter` | counter-er balance ≥ S′ | original duel → countered: refund original challenger S; new duel: counter-er wallet → escrow, S′ |
| B9 | Rematch (stake copied from parent duel) | `POST /api/duels/:id/rematch` | caller balance ≥ S | caller wallet → escrow, S |
| B10 | Force-start group | `POST /api/duels/:id/start` | ≥ 2 accepted seats (existing rule) | none — undecided seats are dropped to declined and never staked |
| B11 | Draft starts (internal, accepted → drafting) | — | — | none |
| B12 | Draft finishes (internal, drafting → drafted) | — | — | none |
| B13 | Draft cancelled (internal, accepted/drafting → cancelled) | — | — | refund every staked wallet |
| B14 | Settle, decisive winner (Settlement worker, drafted → settled) | — | posted inside the existing `Settlement.persist/3` Multi | escrow → winner wallet, **pot = S × staked players** |
| B15 | Settle, 1v1 tie | — | — | escrow → each wallet, S (stakes returned) |
| B16 | Settle, group tie at top | — | — | pot floor-split among tied-top players; indivisible remainder → mint (`:burn`, ≤ n−1 coins) |

Idempotency keys for B-rows: `duel:{id}:stake:{user_id}`,
`duel:{id}:refund:{user_id}`, `duel:{id}:payout`.

The governing invariant: **escrow lifetime == duel active lifetime.** Every
path into `declined` / `cancelled` / `countered` refunds; the one path into
`settled` pays out; nothing else moves coins.

### C. Explicitly impossible (not built, by design)

- Buying coins (no purchase endpoint, no IAP).
- Cashing out / redeeming coins for anything of value.
- Transferring coins between users.
- Editing a stake in place (counter is the only re-terms path).
- Asymmetric stakes.
- Rake (deferred; the seam is one extra entry in the B14 payout txn).
- Negative balances, fractional coins.

### D. Error catalogue

| Condition | Response |
|---|---|
| Balance < S at create/accept/counter/rematch | `422 {"error": "insufficient_coins", "balance": n, "required": S}` |
| Stake non-integer, < 0, or > 10,000 | `422` validation error on `stake_coins` |
| Invalid lifecycle transition | unchanged existing behavior (404/422) |
| Ledger internal failure (unbalanced, frozen, missing account) | `500`; should be unreachable — nightly `Integrity.check` alarms |

### E. Races (all resolved by construction)

- **Double-tap accept** → status transition is from-status-guarded; the stake
  idempotency key makes any replay a no-op.
- **Two staked creates draining one wallet concurrently** → balance rows are
  locked `FOR UPDATE` in sorted account order; the second posting fails the
  overdraft guard.
- **Settle vs. draft-cancel race** → both are status-guarded transitions with
  their coin movement in the same DB transaction; only one commits.
- **Double settle** → `duel:{id}:payout` idempotency key + the existing unique
  `settlement_results.duel_id` constraint.
- **User row deleted with coins in escrow** (no API path today, DB-only
  hazard) → caught by integrity invariant 4 below.

## Integrity invariants (nightly check, adapted from Jeb)

1. Every `coin_txn`'s entries sum to zero (also DB-enforced at commit).
2. Every cached balance equals the sum derived from entries.
3. No wallet's natural balance is negative.
4. **Escrow reconciliation (new, HeadsUp-specific):** `escrow.duels` balance
   == Σ (stake × staked-player-count) over duels in
   `pending | accepted | drafting | drafted`, where staked players are
   derivable from status (1v1 pending: challenger; 1v1 accepted+: both;
   groups: host + accepted seats).

## API surface changes

| Endpoint | Change |
|---|---|
| `POST /api/register` | grants A1; response `user` gains `"coins"` |
| `POST /api/login`, `GET /api/me` | response `user` gains `"coins"`; `/me` applies A3 lazily |
| `POST /api/duels` | accepts `stake_coins` (default 0); B1/B2 + 422s |
| `POST /api/duels/:id/accept·decline·cancel·counter·rematch·start` | coin effects per catalogue; counter accepts `stake_coins` |
| `GET /api/duels`, `GET /api/duels/:id` | duel JSON gains `stake_coins`, `pot_coins` (currently escrowed total for that duel) |
| `GET /api/duels/:id/result` | gains `stake_coins`, `pot_coins`, `my_coin_delta` (net: winner +S×(n−1), loser −S, tie 0) |
| `GET /api/coins` | **new** — `{balance, entries: [...]}` per A5 |

## Mobile changes (screen by screen)

- **AuthContext** — expose `refreshUser()` (re-fetch `/api/me`, merge into
  `user`); call it after any staked duel mutation, on Results mount, on
  Profile focus.
- **ChallengeForm** — new "Stake" chip row (`Friendly · 25 · 100 · 500`) with
  a "you have ◎N" hint; chips above balance disabled; included in the submit
  payload; the counter flow inherits it automatically.
- **CreateChallengeScreen** — surface the 422 insufficient-coins error inline.
- **DuelDetailScreen** — "Stake" term row + gold pot callout near the VS
  header; accept button reads "Accept & stake ◎250" when S > 0.
- **DuelsListScreen** — gold `◎ pot` pill on every staked row (respond /
  ready / waiting / drafting / live / receipt).
- **ResultsScreen** — banner shows net delta ("+◎500") on win, "Stakes
  returned" on tie; detail line "Pot ◎1,000 · your stake ◎500".
- **ProfileScreen** — coin balance in the header stat zone (gold) + "Coin
  history" menu row → new **CoinHistoryScreen** (list from `GET /api/coins`:
  kind icon, duel context, ±amount, date).
- **HomeScreen** — small tappable coin pill in the header → Profile.
- Coin mark: text glyph `◎` in `colors.gold`.

## Migrations & tasks

1. `create_coin_ledger` — the four tables + seeded `mint` / `escrow.duels`
   system accounts.
2. `coin_ledger_guards` — append-only + zero-sum triggers (Jeb's, near
   verbatim).
3. `rename_wager_cents_to_stake_coins` on `duels`.
4. `mix coins.backfill` — idempotent signup grants for existing users.

## Build order

1. **Ledger core** — schemas, `post/1`, integrity, migrations, unit tests.
2. **Grants + reads** — A1–A6, `/api/me` coins, `GET /api/coins`.
3. **Duel wiring** — every B-row inside the corresponding Contests/Settlement
   transaction, JSON additions, a test per catalogue row.
4. **Mobile pass** — the screen list above.
5. **End-to-end** — two dev accounts, staked duel through draft → settle on
   the live stack; run `Integrity.check` after.
