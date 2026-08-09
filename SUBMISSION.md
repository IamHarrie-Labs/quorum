# Quorum — one-page summary

**Team:** Harrie · **Track:** RWA Issuance · **Chain:** Monad testnet (chainId 10143)
**Repo:** https://github.com/IamHarrie-Labs/quorum
**Live demo:** https://iamharrie-labs.github.io/quorum/dashboard.html
**Docs:** https://iamharrie-labs.github.io/quorum/docs.html

---

## Problem

Every private placement exemption is a **headcount rule**, not an eligibility rule. Singapore's SFA
s.272A caps an offer at 50 persons in any 12 months. US Reg D 506(b) caps non-accredited purchasers
at 35. The EU Prospectus Regulation caps at 150 per member state. These are cliffs: go one over and
the exemption is void *retroactively*, and every prior sale becomes an unregistered securities sale.

No blockchain enforces these limits, for one structural reason: **a chain counts wallets, and one
person opens fifty wallets in an afternoon.** So the number lives in a transfer agent's spreadsheet,
reconciled monthly — after the transfers have already settled.

This is not the problem most compliance tooling solves. Checking whether *this recipient* is
eligible is a per-wallet attribute check. Checking whether *the holder base is still legal* is a
question about the set, and no per-wallet rule engine can express it. We verified this directly
against Cleanverse: every rule object in the A-Token and Validator modules is
`allowed_group` / `allowed_sub_group` / `min_tier` / `min_sub_tier` / `is_black_list` / `countries`.
There is no aggregate. That gap is the entire product.

## Solution

Quorum resolves many wallets to one legal person, then evaluates the **resulting state of the whole
cap table** before a transfer settles — refusing anything that would push the holder base past its
legal cap. Two set-level rules ship, both live: a person-headcount cap, and a per-person
concentration ceiling measured across all of that person's wallets.

The check runs inside the ERC-20 `_update()` hook, which every mint, transfer and burn routes
through, so there is no code path that moves the token without passing it.

## CVI · CVA integration points

Quorum deploys its own token and registers it via `register_atoken` rather than `atoken/launch` —
launch has Cleanverse deploy the contract, which would leave no transfer hook for the seat logic.
The same contract is *also* registered as a Validator compliance pool. Four enforcement layers run
on one transfer, three of them inside Cleanverse:

| Layer | Runs in | Catches |
|---|---|---|
| A-Token country rule (`add_rule`) | Cleanverse | Wrong jurisdiction |
| Validator pool rule (`grant` → `register`) | Cleanverse | Pool-level ineligibility |
| Seat + concentration invariant | Quorum | Room is full; one person holds too much |
| **A-Pass subGroup write-back** | **Cleanverse** | **Anyone Quorum never seated** |

**The fourth layer is the one worth reading twice.** Cleanverse's engine cannot compute an
aggregate. Quorum can. So Quorum computes the set-level answer on-chain, writes it back into each
person's A-Pass as a subGroup tag (`QS` seated, `QU` not), and an A-Token rule requiring `QS` makes
**Cleanverse's own engine enforce a conclusion only Quorum could reach** — using the one rule shape
it does have. The aggregate is precomputed and handed over as a per-wallet attribute.

Person 6 is therefore refused **twice, independently**: once by Quorum's transfer hook, once by
`verify_apass` with an on-chain `SubGroupMismatch` revert. Neither refusal depends on the other.

Also used: `generate_apass` (8 A-Passes, SG-tagged), `query_apass_list` (person resolution),
`update_status` (live freeze/unfreeze), `verify_apass`, `atoken/rules`, `validator/is_register`.

## What is live, not simulated

Every figure on the dashboard is a contract read; every claim below is a transaction on Monad
testnet, linked from the site and listed in `contracts/deployments.json`.

- 5 seats filled with real `issue()` transactions.
- **Person 6 — verified, Singapore-domiciled, same tier as everyone seated — refused on capacity**
  with `EXEMPTION_CAPACITY_EXHAUSTED`.
- **Wallet-splitting defeated:** person 1 moves value across their 2nd and 3rd wallets;
  `activeSeats` never moves. Ten addresses, five people.
- **Concentration enforced per person:** a transfer into person 1's second wallet was refused
  on-chain (`CONCENTRATION_EXCEEDED`) even though *that wallet* would have held only 12% of supply —
  the person behind it would have crossed 30%. A smaller transfer through the same path settled.
- **Live revocation:** freezing person 3's A-Pass through Cleanverse makes `verify_apass` return an
  on-chain `APassNotActive` revert, while `SeatLedger` confirms the seat is retained — freezing
  blocks acquisition, not existing holding. Unfreezing recovers.
- 17 Foundry tests including fuzz invariants asserting `activeSeats` never exceeds the cap or the
  number of distinct persons, over 8,192 randomised calls each.
- **Self-serve adoption:** `QuorumFactory` lets any wallet deploy its own fully-wired register in
  one transaction and own it outright. A wallet with no connection to anything else in this
  submission deployed a register through the factory with Singapore's real parameters (50 persons,
  365-day rolling window, 30% ceiling) — not the demo's narrowed pack. Our own deployer key then
  tried to act on that register through the factory and was refused on-chain with
  `NotRegisterOwner`. 6 additional Foundry tests cover this, including the factory acting on its
  own deployments.

The docs include a **Verify it yourself** section: copy-pasteable `cast` commands that reproduce
every number above directly against Monad, plus the `verify_apass` call that refuses person 6 using
none of our code.

## Two findings we did not expect, recorded because they are not documented

1. **`currentKycHash` is not a person identifier.** It differs per wallet even for identical
   identity data — it hashes the A-Pass record, not the human. The real cross-wallet key is
   `customerId`, which groups wallets under one `cvRecordId`. Our original design assumed otherwise;
   the correction is in the repo's history rather than quietly patched out.
2. **A-Token rules are OR-combined.** With both a country-only rule and the `QS` rule registered,
   person 6 still passed on the country rule alone. The permissive rule had to be removed for the
   subgroup gate to bind.

## Deployed contracts — Monad testnet (10143)

```
QuorumAsset     0x26B57c58C20C171233e15c73fA1bD814b269dD88   (A-Token + Validator pool)
PersonRegistry  0xf0D3a94fEb9decdF738Db37e11645C40f69Dad50
SeatLedger      0x5f80999D2e449479E3765f81666A245135de0aca
QuorumFactory   0x385c692d7AAC898FEdDb7282B1860318CD47bD30   (self-serve deployment)
```

## What this is not

A working proof that the architecture holds on live infrastructure — not production software. No
security audit, single deployer key, person resolution is an operator script rather than a monitored
service, `windowDays = 0` so the demo runs a standing cap rather than the rolling 12-month window
s.272A specifies, and no securities counsel has reviewed the legal mappings. Quorum counts *holders*
where s.272A counts *offerees*; an offer made and declined is invisible to any chain. The demo runs
a 5-person cap because fifty genuinely bank-verified identities are not obtainable in a hackathon
sandbox, and faking forty-nine of them would make the demo the very thing this project argues
against. All of this is stated on the docs page, not buried here.
