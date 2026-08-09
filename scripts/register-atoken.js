// Spike: can we register a contract WE deployed as an A-Token?
//
// This is the highest-risk unknown left in the design. The whole architecture rests on it:
// /atoken/launch has Cleanverse deploy the token, which leaves us no transfer hook for the seat
// logic. /atoken/register_atoken takes a contract address plus an owner signature, so the token
// stays ours and the enforcement lives inside it.
//
// Another team already got REGISTER_ATOKEN to ISSUED on monad, so the path works in principle.
// What we do not know is whether Cleanverse requires an interface we cannot see in the docs.
// Find out on Aug 5, not at hour 8 of the build.
//
// Prereq: deploy any ERC-20 to Monad testnet from the wallet whose key you pass here. The
// signing key must be the contract's owner() — Cleanverse verifies the signature against it.
//
//   forge create --rpc-url https://testnet-rpc.monad.xyz --private-key $PK \
//     lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol:ERC20 --constructor-args "T" "T"
//
// Usage:
//   node spike-register-atoken.js --contract 0x...            # dry run, prints the signature
//   node spike-register-atoken.js --contract 0x... --write    # submits and polls to ISSUED
//
// Requires: npm i viem
import { privateKeyToAccount } from "viem/accounts";
import { registerAToken, queryApplyStatus, queryATokenRules } from "./cleanverse.js";
import "dotenv/config";

const CHAIN = "monad";
const ICON = "https://images.cleanverse.com/app/token_icon/USDC.svg";

const args = process.argv.slice(2);
const WRITE = args.includes("--write");
const CONTRACT = args[args.indexOf("--contract") + 1];

if (!CONTRACT?.startsWith("0x")) {
  console.error("Usage: node spike-register-atoken.js --contract 0x... [--write]");
  process.exit(1);
}

const PK = process.env.MONAD_PRIVATE_KEY;
if (!PK) {
  console.error("Missing MONAD_PRIVATE_KEY in .env — must be the contract's owner() key.");
  process.exit(1);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const line = () => console.log("─".repeat(72));

async function main() {
  const account = privateKeyToAccount(PK.startsWith("0x") ? PK : `0x${PK}`);

  line();
  console.log("QUORUM · register_atoken spike");
  console.log(WRITE ? "mode: WRITE (submits the application)" : "mode: DRY RUN");
  line();
  console.log("contract  :", CONTRACT);
  console.log("signer    :", account.address);
  console.log("           ^ this must equal the contract's owner(), or Cleanverse rejects it");

  // The signed payload is lowercase chain concatenated with the lowercase hex address, no
  // separator, via EIP-191 personal_sign. Getting this format wrong is the most common way this
  // call fails, so print it and eyeball it before submitting.
  const message = `${CHAIN.toLowerCase()}${CONTRACT.toLowerCase()}`;
  const signature = await account.signMessage({ message });

  console.log("\nsigned msg:", message);
  console.log("signature :", signature.slice(0, 26) + "…" + signature.slice(-6));

  if (!WRITE) {
    line();
    console.log("Dry run. Re-run with --write to submit.");
    line();
    return;
  }

  line();
  console.log("submitting…");
  const res = await registerAToken({
    chain: CHAIN,
    atoken_address: CONTRACT,
    owner_signature: signature,
    atoken_icon: ICON,
  });
  console.log("requestId :", res.requestId);

  // LAUNCH is auto-approved near-instantly in sandbox; REGISTER_ATOKEN has been observed the same
  // way, but poll properly rather than assuming.
  let status;
  for (let i = 0; i < 40; i++) {
    await sleep(3000);
    status = await queryApplyStatus(res.requestId);
    process.stdout.write(`\r  ${status.applyStatus}${" ".repeat(20)}`);
    if (["ISSUED", "REJECTED", "ISSUE_FAILED"].includes(status.applyStatus)) break;
  }
  console.log("");

  line();
  if (status.applyStatus === "ISSUED") {
    console.log("✓ ISSUED — a contract we deployed is now a registered A-Token.");
    console.log("  atokenAddress :", status.atokenAddress);
    console.log("  txHash        :", status.txHash);
    console.log("\n  The architecture holds. QuorumAsset can be both the CVA and the enforcer.");
    try {
      const rules = await queryATokenRules(CHAIN, CONTRACT);
      console.log("  rules         :", JSON.stringify(rules.rules));
    } catch (e) {
      console.log("  rules         : could not read —", e.message);
    }
  } else {
    console.log(`✗ ${status.applyStatus}`);
    console.log("  rejectReason  :", status.rejectReason ?? "(none)");
    console.log("  issueErrorMsg :", status.issueErrorMsg ?? "(none)");
    console.log("\n  If this is an interface problem, the fallback is: let Cleanverse launch the");
    console.log("  A-Token, and have QuorumRegister gate the mint/distribution path instead of");
    console.log("  the transfer path. Weaker, but the seat logic survives.");
  }
  line();
}

main().catch((e) => {
  console.error("\n✗", e.message);
  if (e.response) console.error(JSON.stringify(e.response, null, 2));
  process.exit(1);
});
