# Quorum

**Every securities exemption is a headcount rule. Blockchains count wallets, not people.**
Quorum is the missing layer: it resolves many wallets to one legal person and blocks any transfer
that would push a holder base past its legal cap — evaluating the resulting state of the whole
cap table, not just the recipient.

Built for the **Cleanverse Build: Trusted Assets Hackathon** (RWA Issuance track), deployed to
**Monad testnet**.

**Live demo:** https://iamharrie-labs.github.io/quorum/dashboard.html
**Docs / architecture:** https://iamharrie-labs.github.io/quorum/docs.html

## The problem

Singapore SFA s.272A caps a private offer at 50 persons in any 12 months. US Reg D 506(b) caps
non-accredited purchasers at 35. EU prospectus exemptions cap at 150 per member state. Go one over
and the exemption is void retroactively — every prior sale becomes an unregistered securities
sale. Today this number lives in a transfer agent's spreadsheet, reconciled monthly, after the
transfers have already settled. No chain enforces it, because a chain counts addresses, and one
person opens fifty addresses in an afternoon.

## The architecture

```
QuorumAsset (ERC-20, deployed by us, registered as a CVA)
   ├── registered A-Token (CVA)      → POST /atoken/register_atoken
   ├── registered Validator pool     → POST /validator/register
   └── _update() hook runs a set-level check on every transfer
         ├── PersonRegistry   resolves wallet -> personId (customerId-keyed, see below)
         ├── SeatLedger       O(1) headcount counter against the pack's cap
         └── concentration ceiling, evaluated per-person across all their wallets
```

We deploy the token ourselves and register it via `register_atoken` rather than `atoken/launch` —
launch has Cleanverse deploy the contract, which leaves no transfer hook for the seat logic. The
same contract also registers as a Validator compliance pool, so a single transfer runs three
enforcement layers: the Cleanverse A-Token rule (per-wallet country/tier), the Cleanverse Validator
pool rule, and Quorum's own set-level invariant, which is the one no per-wallet rule engine can
express.

## CVI · CVA integration points

- **`generate_apass`** — registers each demo identity's A-Pass, tagged with SG country data.
- **`query_apass_list`** — resolves a wallet to its person (see correction below).
- **`register_atoken`** — QuorumAsset registered as a live A-Token (CVA), not launched by
  Cleanverse, keeping the transfer hook.
- **`validator/grant` + `validator/register`** — QuorumAsset also registered as a Validator
  compliance pool (CVI), with an SG country rule.
- **`atoken/add_rule`** — matching SG country rule on the A-Token side.
- **`update_status`** — live freeze/unfreeze scene: a holder's A-Pass is frozen through
  Cleanverse; `verify_apass` returns a genuine on-chain `APassNotActive` revert while frozen,
  while `SeatLedger` confirms the seat itself is untouched — freezing blocks *acquisition*, not
  existing holding.
- **`preflight()`** — a read-only view on `QuorumAsset` that runs the identical check the transfer
  hook runs, live, from the dashboard's pre-transaction check panel.

### A correction, kept in the repo on purpose

The original design assumed `currentKycHash` from `query_apass` was stable across a person's
wallets. Registering three wallets under identical identity data and comparing hashes live (see
`contracts/src/PersonRegistry.sol`'s doc comments and `scripts/setup-identities.js`) showed it
isn't — each A-Pass registration record hashes independently. The real person key is `customerId`,
Cleanverse's own persistent per-customer identifier: reusing it across wallet addresses groups them
under one `cvRecordId`, confirmed via `query_apass_list`. `PersonRegistry` binds
`keccak256(customerId)` and is otherwise source-agnostic.

## What's live, not simulated

- Contracts deployed and verified on Monad testnet (chainId 10143) — addresses and every
  transaction hash in [`contracts/deployments.json`](contracts/deployments.json).
- 6-person demo cast (8 wallets, person 1 holds 3) registered via `generate_apass` and bound into
  `PersonRegistry` on-chain — see [`scripts/demo-cast.json`](scripts/demo-cast.json).
- 5 seats filled with real `issue()` transactions; person 6 — fully verified, correctly
  domiciled — refused on-chain with `EXEMPTION_CAPACITY_EXHAUSTED`.
- Wallet-splitting proven live: person 1 moves value across their second and third wallets;
  `activeSeats` never moves.
- Live freeze/unfreeze revocation scene against Cleanverse, described above.
- The dashboard reads all of this directly via `ethers.js` against Monad's public RPC — no mocked
  numbers, every figure links to [MonadVision](https://testnet.monadvision.com).

## Repo layout

- `contracts/` — Foundry project: `PersonRegistry`, `SeatLedger`, `QuorumAsset`, invariant + scene
  tests, deploy script, `deployments.json`.
- `scripts/` — Node scripts against the Cleanverse Cooperate API and Monad (identity setup,
  A-Token/Validator registration, seat filling, wallet-split and freeze scenes). `demo-cast.json`
  is the public record of the live demo identities (no private keys).
- `index.html` / `dashboard.html` / `docs.html` — the three surfaces: landing, live dashboard,
  architecture docs. Static HTML/CSS/JS, no build step.

## Running the contracts

```bash
cd contracts
forge test
```

17 tests, including fuzz invariants asserting `activeSeats` never exceeds the cap or the number of
distinct persons across any sequence of mints, transfers, and exits.
