# Quorum — 48-hour build plan

Window: **Aug 8 00:00 UTC → Aug 9 23:59 UTC**. Submission by email to `isaac@cleanverse.com`.
All times are UTC — map them to your local clock before Aug 8 and write that down.

**Target submission: Aug 9, 21:00 UTC.** Three hours of buffer. Nobody who submits at 23:58
submits their best work.

---

## Rule zero

Commit history during the window is a stated requirement.

- Repo created and initialized **at 00:00 on Aug 8**, not before.
- 20–30 real commits across two days. Commit at every "done means" below.
- Never one giant commit. Judges open the commit graph before the code.

Setup that isn't code — A-Passes, token registration, faucet, addresses, design — happens before
the window and should.

---

## Architecture

The critical decision: **you deploy the token, then register it as a CVA.** Do not use
`/atoken/launch` — that has Cleanverse deploy the contract, which leaves you no transfer hook to
put the seat logic in, and the enforcement would end up sitting beside the asset instead of inside
it. `/atoken/register_atoken` with an owner signature makes *your* contract a registered A-Token.

```
QuorumAsset (yours, deployed by you)
   ├── registered as an A-Token          → /atoken/register_atoken  (CVA)
   ├── registered as a Validator pool    → /validator/register       (CVI rules)
   └── _update() hook runs the set-level check on every transfer
         ├── PersonRegistry      currentKycHash → personId, many wallets → one person
         ├── SeatLedger          rolling 12-month headcount, O(1)
         └── ConcentrationGuard  max % per person, across all their wallets
```

**Four enforcement layers on one transfer**, three of them running in Cleanverse's engine:

| Layer | Owner | Catches |
|---|---|---|
| A-Token compliance rule | Cleanverse | Wrong tier, wrong country |
| Validator pool rule | Cleanverse, applied to your contract | Pool-level eligibility |
| Seat + concentration invariant | Quorum | Room is full; one person holds too much |
| **A-Pass subGroup tag** | **Quorum writes it, Cleanverse enforces it** | **Anyone Quorum never seated** |

### Layer 4 — the closed loop

Every rule Cleanverse has is a per-wallet attribute check; it cannot compute an aggregate. Quorum
can. So Quorum computes the set-level answer and **writes it back into the person's credential**
as a subGroup tag (`QS` = seated), then an A-Token rule with `allowed_sub_group: "QS"` makes
Cleanverse's own engine enforce a conclusion only Quorum could reach.

Identity flows in, seat state flows back out, enforcement happens in their engine. That is the
difference between consuming the platform and extending it.

Demo payoff: person 6 is refused by Quorum's contract *and independently* by `verify_apass`,
because Quorum never granted the tag. Two systems agreeing, one of them theirs.

**Belt and braces — non-negotiable.** The contract enforces the cap on its own regardless. The
write-back is an additional visible layer, never the load-bearing one. If an API write fails on
camera the refusal still happens; it just loses one of its two justifications. Do not let the demo
depend on a write succeeding live.

Optional second axis if layer 4 holds: encode each person's concentration bracket in `subTier`
(1–99) and gate with `min_sub_tier`.

### Cleanverse surface used

Reads: `query_apass` (personId via `currentKycHash`), `verify_apass` (composite verdict, code `4`
= valid and transferable), `query_apass_list`, `query_txs`, `atoken/rules`, `validator/verify`.

Writes: `register_atoken`, `add_rule`, `validator/grant`, `validator/register`, `validator/set_rule`,
**`update_status` (freeze/unfreeze — the revocation scene)**, `faucet`, `download_travel_rule`.

Use `verify_apass` for eligibility rather than reimplementing it. Quorum's job is the layer above.

### Monad testnet · chainId 10143 · https://testnet-rpc.monad.xyz

```
A-Pass       0xbA82D189540CaC9DC6FF46B6837CaC1BFdEC58B9  (proxy → 0x9406f5d4…15a3)
AccessCore   0x8F118338a1fa41E7Fa86Be19A4e8B99Ed58A6EcC
aUSDC        0xaC0893567D43C3E7e6e35a72803df05416C1f20D
USDC         0x534b2f3A21130d7a60830c2Df862319e593943A3
```

---

## Pre-window (Aug 5–7) — no commits, all blockers

- [ ] **Person-ID verdict.** Two wallets, identical identity data, different `customerId` →
      does `currentKycHash` match? Everything downstream assumes yes.
- [ ] **`register_atoken` spike.** Deploy a throwaway ERC-20 on Monad, sign EIP-191 over lowercase
      `monad` + lowercase address, register it, poll to `ISSUED`. **This is the highest-risk
      unknown left** — registration may require an interface we can't see in the docs. Find out on
      the 5th, not at hour 8.
- [ ] **`add_rule` on the registered token** — confirm rules attach to a contract you deployed.
- [ ] **Write-back spike** — `node spike-writeback.js --write --atoken 0x…`. Does `override: true`
      mutate `subGroup` on an existing A-Pass, how long does it take to land on-chain, and does
      `verify_apass` flip when an `allowed_sub_group` rule stops matching? Both halves must pass
      for layer 4 to exist. If either fails, drop layer 4 — nothing else changes.
- [ ] **Validator spike** — `grant` then `register` your throwaway contract as a pool, then
      `is_register` and `verify`. Same signature format. Confirm it works end to end.
- [ ] **Freeze spike** — `update_status` with `status: 2` on a test A-Pass, then `verify_apass`,
      confirm the verdict changes, then unfreeze. This is a demo scene; don't discover it live.
- [ ] **Faucet drawn.** Cooldown is likely shared across all ~40 teams. Draw early, don't rely on it.
- [ ] **Demo identities.** 6 people: 5 who take seats, 1 refused. Person #1 gets **three** wallets
      (same identity data) for the split scene. 8 A-Passes total. Record every wallet, customerId
      and hash.
- [ ] **AES helper working** (already spiked in `spike/`). Rewrite inside the window — 10 minutes
      once you know it works.
- [ ] Foundry installed. `.env.local` prepared, never committed.

Never use `LAUNCH_WRAPPED`. Every observed `ISSUE_FAILED` is a wrapped launch.

---

## Day 1 — Aug 8. Goal: the demo works with no UI at all.

By 23:59, a script must fill 5 seats, refuse the 6th, pass the wallet-split case, and survive a
live freeze. If that's true, Day 2 is only making it visible.

### 00:00–02:00 · Scaffold
Foundry + static HTML/CSS/JS, one repo. `.gitignore` with `.env*` **in the first commit**. Brand
tokens from `brand.md`, fonts wired, wallet connect via ethers.js.

> Adjustment (Aug 8): dropped Next.js — plain HTML/CSS/JS with ethers.js for chain reads, built
> on the pre-window `index.html` / `dashboard.html` / `docs.html` drafts. Faster to iterate solo,
> deploys to Vercel/any static host with zero build step.
> Done: `forge test` runs, `pnpm dev` serves a themed page. **3–4 commits.**

### 02:00–06:00 · Core contracts
`PersonRegistry`, `SeatLedger` (O(1) counter — never loop the holder set), `RulePack`
(`sg_sfa_272a` and a `demo` pack at `maxPersons: 5`).

Invariant test now, not later: **`activeSeats ≤ maxPersons` after any sequence of mints,
transfers, revocations.** It's the claim the project makes.
> Done: invariant suite green. **4–6 commits.**

### 06:00–09:00 · QuorumAsset, deployed and registered
ERC-20 with the check in `_update()`. Structured reason codes — `EXEMPTION_CAPACITY_EXHAUSTED`,
`CONCENTRATION_EXCEEDED`, `SEAT_ALREADY_HELD`. Event on every decision, approved and refused both.

Deploy to Monad. Then `register_atoken` → poll to `ISSUED` → `add_rule` with `countries: ["SG"]`.
Commit `deployments.json`.
> Done: your contract is a live registered A-Token; a refusal is visible on the explorer.
> **3–4 commits.**

### 09:00–12:00 · Cleanverse integration
AES client, `query_apass` → `currentKycHash`, `verify_apass` in the transfer path, the writer that
pushes wallet → personId into `PersonRegistry`.
> Done: a live A-Pass produces a real on-chain registry write. **3–4 commits.**

### 12:00–18:00 · Sleep. Six hours, actually.

### 18:00–22:00 · Validator pool + freeze + end-to-end
`validator/grant` → `validator/register` for QuorumAsset → `set_rule`. Verify with `is_register`
and `verify`.

Wire the freeze path: `update_status` freezes a holder's A-Pass; Quorum keeps their seat (in law
they still hold) but blocks acquisition. Unfreeze recovers.

Seed script: fill 4 seats with real people, real transactions.
> Done: **all four demo scenes run headlessly on live infrastructure.**

### 22:00–23:00 · Checkpoint, honestly
Scenes work → Day 2 as written. They don't → cut concentration and the Validator layer, ship
headcount plus freeze, spend Day 2 making that beautiful. A flawless two-scene demo beats a broken
four-scene one.

---

## Day 2 — Aug 9. Make it visible, then stop.

### 00:00–06:00 · Dashboard
Seat counter (filled gold circles vs hollow outlines). Holder register showing **persons with
wallet counts underneath** — the thesis, made legible. Preflight panel. Decision banners.
`<Receipt txHash />` on every number. Live feed from `query_txs`.
> Done: real chain state, zero mocked values. **5–7 commits.**

### 06:00–10:00 · Landing + docs
Landing: one scroll — headline, problem in two lines, seat visual, button to dashboard.
Docs: how CVI and CVA are used, the three-layer table, contract addresses, architecture diagram,
the offeree-vs-holder caveat stated plainly. **This page is where the 30-point integration score
gets argued.** Not filler.

Deploy to Vercel now, not at hour 46.
> Done: public URL, three surfaces live. **4–5 commits.**

### 10:00–14:00 · Sleep.

### 14:00–15:00 · FEATURE FREEZE. Set an alarm. Bug fixes only.

### 15:00–16:00 · Reset demo state
Seed to exactly 4 of 5 seats. Gas in every wallet, approvals pre-signed, second RPC ready.

### 16:00–18:00 · Rehearse twice, then record

1. **The problem.** 50-person limit, spreadsheet, retroactive void. 45 seconds.
2. **Seat 5 fills.** Capacity reached.
3. **Person 6 refused** — verified, domiciled, accredited, refused anyway. Sit on this one. Read
   the reason code aloud. *"Every other system in this hackathon would have allowed this."*
4. **Wallet split.** Existing holder, new wallet, resolves to the same person, no new seat, approved.
5. **Live revocation.** Freeze P3's A-Pass through Cleanverse on camera. Seat retained, acquisition
   blocked. Unfreeze, recovers. *"That wasn't a flag in our database. That was their credential."*
6. **Receipts.** Click a number → Monad explorer. *Nothing here is simulated.*
7. **The config.** `maxPersons: 5` for the demo, `50` for Singapore.

No length limit. 6–9 minutes.

### 18:00–20:00 · One-page summary + README
Problem / solution / CVI·CVA integration points / deployed chains — their headings, their order.

### 20:00–21:00 · Final checks
Repo public. `git log -p | grep -i "api-key"` returns nothing — check, don't assume. Live URL in an
incognito window. Video plays from the link you're sending. **Submit by 21:00.**

---

## Cut list — in this order, no debate at 4am

1. Light mode
2. Docs styling (keep the content)
3. `subTier` concentration banding (layer 4's second axis)
4. Concentration ceiling
5. Live feed via `query_txs`
6. Preflight panel
7. Layer 4 write-back (the contract still enforces; you lose the second justification)
8. Validator pool layer (fall back to A-Token registration alone)

**Never cut:** the wallet-split scene, the freeze scene, block-explorer receipts, the invariant test.

---

## Solo adjustment

Alone? Drop concentration and the Validator layer from the plan now, not at hour 40, and start the
dashboard earlier. One person ships headcount + wallet-split + freeze + a clean dashboard. One
person does not ship all of it.

---

## Known failure modes

- **AES mismatch** — zero IV, key must be base64-*decoded* first. Most common blocker.
- **EIP-191 rejected** — lowercase chain + lowercase hex address, no separator.
- **`register_atoken` rejects your contract** — the reason the Aug 5 spike exists.
- **`add_rule` is create-only** and rejects duplicates. There is no update.
- **Faucet cooldown** triggered by another team. Draw early.
- **Monad RPC flakiness while recording.** Second endpoint ready.
