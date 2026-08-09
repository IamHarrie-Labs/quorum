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
         └── concentration ceiling, per-person across all their wallets
                                     (live at 30% on the deployed instance)
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
- Concentration ceiling live at 30% and enforced against the *person*: a transfer into person 1's
  second wallet was refused on-chain with `CONCENTRATION_EXCEEDED` even though that receiving
  wallet would have held just 12% of supply — the person behind it would have crossed 30%. A
  smaller transfer through the same path settled. Both are real transactions.
- Live freeze/unfreeze revocation scene against Cleanverse, described above.
- The dashboard reads all of this directly via `ethers.js` against Monad's public RPC — no mocked
  numbers, every figure links to [MonadVision](https://testnet.monadvision.com).

## Limitations

This is a working proof that the architecture holds on live infrastructure. It is not production
software, and the gap is worth naming precisely — an overstated compliance tool is worse than none.

**What the deployed instance actually has switched on.** Call the getters and you will find:

| Getter | Value | Meaning |
|---|---|---|
| `concentrationCeilingBps()` | `3000` | Concentration ceiling **live at 30%**, and binding — person 1 currently sits at 26%. |
| `windowDays()` | `0` | Standing cap, not the rolling 12-month window s.272A specifies. The rolling path is implemented and fuzz-tested but is not what is on display, and changing it means redeploying since it is fixed at construction. |
| `requireAPass()` | `false` | `PersonRegistry` does not verify on-chain A-Pass possession before binding. |

**The registrar is trusted, and it is the weakest joint.** Person resolution happens off-chain: a
script reads `customerId` from Cleanverse and writes `keccak256(customerId)` into the registry under
a registrar key. The contract cannot verify that mapping. A compromised registrar could bind two
wallets to one person who are not the same human, and the invariant would not catch it — the
invariant guarantees the count is *consistent*, not that it is *true*. Closing this needs either a
real per-wallet on-chain identity signal or a Cleanverse-signed attestation the contract can verify.
Neither exists here.

**The subgroup write-back was designed but not shipped.** The intended fourth enforcement layer —
Quorum writing its seat decision back into the A-Pass `subGroup` so Cleanverse's own engine refuses
unseated wallets independently — was spiked but not completed in the window. `docs.html` describes
it as future work, not as a running feature.

**Everything else a production deployment would need:** no security audit; single burner deployer
key with no multisig, timelock, or upgrade path; identity resolution is manual scripts rather than a
monitored service; Cleanverse's API is an unhandled single point of failure; the demo identities are
fictional people against a shared sandbox; and no securities counsel has reviewed the per-jurisdiction
legal mappings. The offeree-vs-holder gap for s.272A is discussed in `docs.html`.

**What is genuinely proven:** that a self-deployed contract can be both a registered A-Token and a
registered Validator pool while keeping its own transfer hook; that person-level headcount can be
enforced inside that hook at O(1); that wallet-splitting fails against it; and that a credential
frozen through Cleanverse changes the verdict on a live wallet. Each of those is a real Monad
testnet transaction, linked from the dashboard.

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
