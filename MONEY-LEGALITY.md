# Can HeadsUp Do Real-Money Duels? — Legality Research Brief

_Compiled 2026-07-09 from four parallel deep-research passes (federal law, state law,
market precedent, operations) with sources cited throughout. **This is research, not
legal advice** — before any real dollar moves, a gaming attorney reviews the design.
That engagement (an "opinion letter") is also required in practice by banks and
payment processors, so it is unavoidable anyway._

---

## The question

> Friends deposit money, agree a stake shown in the duel terms, winner takes the pot,
> and HeadsUp keeps a small rake. Is this legal?

## The verdict

**No — not in that shape.** Three independent features of the plan are each fatal on
their own:

1. **The rake kills the "just friends betting" theory everywhere.** Nearly every
   state exempts genuinely private social bets — but the exemption protects the
   *players*, never a third-party organizer, and it evaporates the moment anyone
   profits from running the bet. Texas Penal Code 47.02(b) requires that "no person
   received any economic benefit other than personal winnings"; NY Penal Law 225.00
   defines the protected "player" as one who profits *only* as a bettor; Colorado
   defines disqualifying "profit" as ANY direct or indirect benefit. An app that
   matches the bet, holds the pot, and takes a cut is a gambling promoter/bookmaker
   in every state examined — in California, that's Penal Code 337a (a wobbler:
   misdemeanor or felony up to 3 years).

2. **"Winner takes the pot" fails the fantasy safe harbor.** The federal UIGEA
   fantasy carve-out (31 U.S.C. §5362(1)(E)(ix)) — whose language most state fantasy
   statutes copy — requires prizes to be established in advance AND "not determined
   by the number of participants or the amount of any fees paid." A pot that equals
   2× the stake minus rake is *definitionally* determined by the fees. This is why
   DraftKings/FanDuel head-to-heads use **fixed entry tiers with posted,
   predetermined prizes** (two $10 entries → a posted $18 prize) — economically
   identical, legally night-and-day.

3. **Calling it a "wager" forfeits the industry's core defense.** Twenty years of
   fantasy law rests on the *entry fee ≠ wager* doctrine (Humphrey v. Viacom):
   unconditional fee, guaranteed prize not proportional to fees, neutral operator.
   A product that self-describes as wagering, with user-set stakes, hands
   prosecutors the Wire Act elements ("engaged in the business of betting or
   wagering," transmitting bets and resulting money interstate) that compliant DFS
   is structured to avoid.

**And the sharpest local fact: California.** The CA Attorney General's formal
opinion (July 3, 2025) declares ALL paid daily fantasy — draft-style and pick'em,
peer-to-peer included — illegal sports wagering under PC 337a, explicitly bypassing
the skill-vs-chance debate (betting on someone else's skill contest is still
betting). It's advisory, not a statute; no enforcement yet; DraftKings/FanDuel are
riding it out behind litigation war chests, and four class actions are pending
against operators. But we live in LA with none of their leverage. **Operating the
described product from — or into — California is the single biggest legal risk in
the plan.**

---

## What the market history says (the graveyard is instructive)

- **"Friends bet friends" apps are a graveyard.** Wagr did it *licensed* in a legal
  state with a discounted 5% fee — commercially dead within a year, acquihired by
  Yahoo, gone. Betcha/Vivid Picks: dead July 2025. Mojo: ~$100M raised, one state,
  pivoted to B2B. ZenSports: license neutered its P2P feature.
- **"No rake" is NOT a safe harbor.** Betcha.com (Wash. Sup. Ct. 2010) charged only
  flat listing fees, escrowed stakes, even made paying losses *optional* — held
  unanimously to be illegal bookmaking. Arizona C&D'd no-vig BettorEdge (June 2025)
  for "gambling promotion" anyway.
- **"Subscription instead of rake" is arguably WORSE** — the only on-point 2026
  attorney analysis (Dentons) says recurring payment makes the consideration element
  *easier* to prove, and NY-style "advancing gambling" statutes criminalize
  facilitation with zero revenue.
- **Sweepstakes is dead for new sports products**: banned in CA/NY/NJ/CT/MT/NV/IN/TN
  (2025–26 wave), 65 C&Ds in Illinois alone, processors and app stores exiting.
- **The survivors** prove the two workable lanes:
  - **Splash Sports** — friends' pools with entry fees, pots, and a 10% rake,
    structured as *fantasy/skill contests* under state fantasy statutes, geofenced
    to ~40 eligible jurisdictions, registered/licensed where required (NY approval
    2024). Funded ($14.5M Series B, Oct 2025), 2.3M users. **This is the existence
    proof for HeadsUp's model — done the legal way.**
  - **LeagueSafe** — 18 years, zero enforcement, $31M+/season held: a pure
    *custodian* of private-league dues. No rake; flat processing fees only;
    payouts released by **majority vote of the league**, never by LeagueSafe
    judging outcomes. The lesson: fees tied to processing (never outcomes) +
    no adjudication role = tolerated.
  - **P2P conversions**: PrizePicks/Underdog turned state C&Ds into approvals by
    converting house-banked games into peer-to-peer *contest* formats (16
    jurisdictions formally recognize PrizePicks' P2P as skill games). P2P vs
    friends is the right instinct — inside a contest framework, not a wager one.

## The practical gates (even where legal)

- **Apple App Store 5.3.4**: real-money gaming apps must show licensing for every
  location served, geo-restrict, be free, fund wallets outside IAP, and ship from a
  corporate entity. TestFlight/ad-hoc is not a loophole (same guidelines).
- **Payments**: Stripe/Square prohibit paid fantasy outright. The lane is gaming
  processors (Aeropay/PayNearMe pay-by-bank) + KYC (Persona et al.) + geolocation +
  segregated player-fund (FBO) accounts + 0.25% federal wagering excise on entries +
  1099s ($2,000 net-profit threshold from TY2026).
- **Cost to do it ourselves**: state fees are the cheap part (~$1.5k–12k across the
  friendly small-operator tiers: CO $350, MD $100, IL $500, TN $300+, MO ~$0, ME
  free under $100k revenue). The real cost is counsel + opinion letter + payments +
  compliance build: **roughly $50k–150k and 6–12 months** before the first legal
  dollar of rake. Hard-blocked states regardless: WA, ID, MT, NV, HI (+ CA
  decision, CT practically closed). ~30 states reachable cheaply once structured
  correctly.

---

## The plan adjustment (same product feel, different legal shape)

**Phase 1 — now (free beta, unchanged):** No real money. Optionally add a coins /
bragging-rights economy and season records. One rule if we ever sell coins: sold
coins must never be the thing wagered head-to-head (Kater v. Churchill Downs
exposure in WA). Friends who want side stakes settle privately offline — the app
stores no dollar amounts and links no payments (that's the untouchable
WagerLab/ESPN-league posture, and it's also processor- and App-Store-clean).

**Phase 2 — at real traction: rent the money layer.** Integrate or partner rather
than become an operator: Splash Sports has a Partner Solutions division (your UX,
their licenses/wallet/payouts, rake shared), and LeagueSafe covers season-long
private leagues. Real stakes, ~zero compliance capex, and it validates whether
friends actually pay before spending $100k on the stack.

**Phase 3 — at scale: become the operator, correctly.**
- **Fixed entry tiers + posted predetermined prizes** — never a floating pot.
  ($10 + $10 → posted $18 prize; the $2 is a contest fee, not a rake on a wager.)
- **Vocabulary matters legally**: entry fee / contest / prize — never bet, wager,
  stake, pot. (In-app trash talk can say whatever; terms, marketing, and flows
  cannot.)
- Multi-game rosters only (already true), 18/19/21+ age gates per state, geofence
  the blocked states, launch in the small-operator-tier states first, skip
  NY/PA/CT/VA until revenue justifies $50k fees, treat CA as closed until the
  Bonta-opinion fight resolves.
- Gaming counsel signs off before launch. Non-negotiable.

**Never:** sweepstakes. **Not us (for now):** CFTC event-contract exchanges — a
PrizePicks-scale project with unresolved state-vs-federal litigation.

---

## Bottom line

The *product* — head-to-head draft fantasy decided by real stats — is the most
defensible paid format in US law, more defensible than the pick'em games that drew
all the crackdowns. What's illegal is the *packaging* we sketched: user-set wagers,
winner-takes-pot, platform rake. Splash Sports charges friends 10% on pooled
real-money contests legally in ~40 jurisdictions — by being a registered fantasy
contest operator with fixed-prize structures. The path exists; it's a compliance
project, not a feature flag, and the current free beta is exactly the right place
to be standing while we decide when it's worth it.

_Key sources: 31 U.S.C. §5362(1)(E)(ix); Humphrey v. Viacom (D.N.J. 2007);
Dew-Becker v. Wu (Ill. 2020); Internet Community & Entertainment Corp. v. Wash.
State Gambling Comm'n (Wash. 2010); CA AG Opinion 23-1001 (July 3, 2025) + Underdog
v. Bonta coverage (WilmerHale Feb 2026); NY Penal Law 225.00/225.05; Tex. Penal
Code 47.02; Fla. Stat. 849.14; Velawood 50-state fantasy tracker (Feb 2026); SCCG
DFS licensing breakdown (2025); PrizePicks NY settlement ($15M, 2024) and Underdog
($17.5M, 2025); Splash Sports state list + Series B (Oct 2025); LeagueSafe terms;
Apple App Review Guidelines §5.3; CRS R44398; IRS CCA 202042015; OBBBA 1099
threshold change (2025). Full citation set lives in the research transcripts._
