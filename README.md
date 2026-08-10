# Quorum

**Every securities exemption is a headcount rule. Blockchains count wallets, not people.**
Quorum is the missing layer. It resolves many wallets back to one legal person and blocks any
transfer that would push a holder base past its legal cap, based on the resulting state of the
whole cap table, not just the recipient in front of it.

Built for the **Cleanverse Build: Trusted Assets Hackathon** (RWA Issuance track), deployed to
**Monad testnet**.

**Live demo:** https://tryquorum.vercel.app/dashboard
**Docs / architecture:** https://tryquorum.vercel.app/docs
**Mirror:** https://iamharrie-labs.github.io/quorum/dashboard.html
**Demo video:** https://youtu.be/xT9-FX6VcdI

## The problem

Singapore SFA s.272A caps a private offer at 50 persons in any 12 months. US Reg D 506(b) caps
non-accredited purchasers at 35. EU prospectus exemptions cap at 150 per member state. Cross one of
those numbers and the exemption goes void retroactively, so every prior sale in the offering
becomes an unregistered securities sale. Today that count lives in a transfer agent's spreadsheet,
reconciled monthly, well after the transfers have already settled. No chain enforces it, because a
chain counts addresses, and one person can open fifty addresses in an afternoon.

## Adoption, without needing us to deploy anything

An already-deployed plain ERC-20 has immutable bytecode, so it can't be retrofitted after the fact.
Everything below is built around that constraint instead of ignoring it.

- **Self-serve issuance.** `QuorumFactory` deploys a fully-wired register in one transaction, and
  the caller owns it outright. The factory itself holds no authority over what it deploys. As live
  proof, a wallet with no connection to anything else on this site called `deploy()` with
  Singapore's real parameters (50 persons, 365-day rolling window, 30% ceiling), and our own
  deployer key was refused with `NotRegisterOwner` when it tried to touch that register through the
  factory afterward. See `factory` in `contracts/deployments.json`.
- **Zero-integration adoption for an existing A-Token.** The layer-4 write-back (below) doubles as
  an adoption path. Point Quorum's resolver at an already-registered A-Token, add one rule
  (`allowed_sub_group: "QS"`), and it gains person-level headcount enforcement with no changes to
  its own contract.
- **`preflight()`** is a free, permissionless `eth_call` for anyone who wants an answer without
  integrating anything at all.

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

We deploy the token ourselves and register it with Cleanverse using `register_atoken`. We didn't
use `atoken/launch`, since that has Cleanverse deploy the contract, which would leave no transfer
hook for the seat logic to live in. The same contract also registers as a Validator compliance
pool, so a single transfer runs three enforcement layers: the Cleanverse A-Token rule (per-wallet
country and tier), the Cleanverse Validator pool rule, and Quorum's own set-level invariant, the one
layer no per-wallet rule engine can express on its own.

## CVI · CVA integration points

- **`generate_apass`**: registers each demo identity's A-Pass, tagged with SG country data.
- **`query_apass_list`**: resolves a wallet to its person (see the correction below).
- **`register_atoken`**: QuorumAsset registered as a live A-Token (CVA), keeping its own transfer
  hook by deploying it ourselves rather than through Cleanverse.
- **`validator/grant` + `validator/register`**: QuorumAsset also registered as a Validator
  compliance pool (CVI), with an SG country rule.
- **`atoken/add_rule`**: matching SG country rule on the A-Token side.
- **`update_status`**: live freeze and unfreeze scene. A holder's A-Pass is frozen through
  Cleanverse, `verify_apass` returns a genuine on-chain `APassNotActive` revert while frozen, and
  `SeatLedger` confirms the seat itself stays untouched throughout. Freezing blocks new
  acquisitions while leaving any tokens already held exactly where they are.
- **`preflight()`**: a read-only view on `QuorumAsset` that runs the same check the transfer hook
  runs, live, from the dashboard's pre-transaction check panel.

### A correction, kept in the repo on purpose

The original design assumed `currentKycHash` from `query_apass` stayed stable across a person's
wallets. Registering three wallets under identical identity data and comparing hashes live (see
`contracts/src/PersonRegistry.sol`'s doc comments and `scripts/setup-identities.js`) showed
otherwise: each A-Pass registration record hashes independently. The real person key is
`customerId`, Cleanverse's own persistent per-customer identifier. Reusing it across wallet
addresses groups them under one `cvRecordId`, confirmed via `query_apass_list`. `PersonRegistry`
binds `keccak256(customerId)` and stays source-agnostic beyond that.

## What's live, not simulated

- Contracts deployed and verified on Monad testnet (chainId 10143). Addresses and every
  transaction hash live in [`contracts/deployments.json`](contracts/deployments.json).
- 6-person demo cast (8 wallets, person 1 holds 3) registered via `generate_apass` and bound into
  `PersonRegistry` on-chain. See [`scripts/demo-cast.json`](scripts/demo-cast.json).
- 5 seats filled with real `issue()` transactions. Person 6, fully verified and correctly
  domiciled, is refused on-chain with `EXEMPTION_CAPACITY_EXHAUSTED` simply because the room is
  full.
- Wallet-splitting proven live: person 1 moves value across their second and third wallets while
  `activeSeats` never moves.
- Concentration ceiling live at 30%, enforced against the person rather than the wallet. A transfer
  into person 1's second wallet was refused on-chain with `CONCENTRATION_EXCEEDED`, even though
  that receiving wallet alone would have held just 12% of supply. Summed across their wallets, the
  same person would have crossed 30%. A smaller transfer through the same path settled instead.
  Both are real transactions.
- Live freeze and unfreeze revocation scene against Cleanverse, described above.
- The dashboard reads all of this directly via `ethers.js` against Monad's public RPC. No mocked
  numbers, every figure links out to [MonadVision](https://testnet.monadvision.com).

## Limitations

This is a working proof that the architecture holds on live infrastructure. It is not production
software, and that gap is worth naming precisely, since an overstated compliance tool is worse than
no compliance tool at all.

**What the deployed instance actually has switched on.** Call the getters and you'll find:

| Getter | Value | Meaning |
|---|---|---|
| `concentrationCeilingBps()` | `3000` | Concentration ceiling live at 30%, and binding. Person 1 currently sits at 26%. |
| `windowDays()` | `0` | A standing cap, not the rolling 12-month window s.272A specifies. The rolling path is implemented and fuzz-tested, but it isn't what's on display here, and switching it means redeploying since it's fixed at construction. |
| `requireAPass()` | `false` | `PersonRegistry` doesn't verify on-chain A-Pass possession before binding. |

**The registrar is trusted, and it's the weakest joint in the system.** Person resolution happens
off-chain: a script reads `customerId` from Cleanverse and writes `keccak256(customerId)` into the
registry under a registrar key. The contract has no way to verify that mapping itself. A
compromised registrar could bind two wallets belonging to different people as if they were one, and
the invariant would never catch it, because the invariant only guarantees the seat count stays
internally consistent. It can't guarantee the underlying person mapping is actually true. Closing
this gap needs a real per-wallet on-chain identity signal, or a Cleanverse-signed attestation the
contract itself can verify. Neither exists here yet.

**The subgroup write-back was designed, then shipped for real.** The fourth enforcement layer,
Quorum writing its seat decision back into the A-Pass `subGroup` so Cleanverse's own engine refuses
unseated wallets independently, is live and demonstrated on the dashboard, not just described in
`docs.html`.

**Everything else a production deployment would still need:** a security audit, a multisig or
timelock in place of a single burner deployer key, a monitored identity resolution service instead
of manual scripts, a fallback for Cleanverse's API as a single point of failure, real identities in
place of the demo's fictional cast on a shared sandbox, and a review of the per-jurisdiction legal
mappings by securities counsel. The offeree-versus-holder gap for s.272A is discussed in
`docs.html`.

**What is genuinely proven:** that a self-deployed contract can be both a registered A-Token and a
registered Validator pool while keeping its own transfer hook, that person-level headcount can be
enforced inside that hook at O(1), that wallet-splitting fails against it, and that a credential
frozen through Cleanverse changes the verdict on a live wallet. Each of those is a real Monad
testnet transaction, linked from the dashboard.

## Repo layout

- `contracts/`: Foundry project. `PersonRegistry`, `SeatLedger`, `QuorumAsset`, invariant and scene
  tests, deploy script, `deployments.json`.
- `scripts/`: Node scripts against the Cleanverse Cooperate API and Monad (identity setup,
  A-Token and Validator registration, seat filling, wallet-split and freeze scenes).
  `demo-cast.json` is the public record of the live demo identities, with no private keys.
- `index.html` / `dashboard.html` / `docs.html`: the three surfaces, landing page, live dashboard,
  and architecture docs. Static HTML, CSS, and JS, with no build step.

## Running the contracts

```bash
cd contracts
forge test
```

20 tests, including fuzz invariants asserting `activeSeats` never exceeds the cap or the number of
distinct persons across any sequence of mints, transfers, and exits.
