// Registers QuorumAsset as a Cleanverse Validator compliance pool.
//
// grant() gives the contract REGISTER_ROLE via an EIP-191 owner signature (same lowercase
// chain+address format as register_atoken). register() then enrolls it as a pool. Both need the
// signer to equal the contract's on-chain owner() — the reason QuorumAsset got an owner() alias.
//
// Usage: node register-validator.js --contract 0x... --write
import { privateKeyToAccount } from "viem/accounts";
import { validatorGrant, validatorRegister, validatorIsRegistered, validatorSetRule } from "./cleanverse.js";
import "dotenv/config";

const CHAIN = "monad";
const args = process.argv.slice(2);
const WRITE = args.includes("--write");
const CONTRACT = args[args.indexOf("--contract") + 1];

if (!CONTRACT?.startsWith("0x")) {
  console.error("Usage: node register-validator.js --contract 0x... [--write]");
  process.exit(1);
}

const PK = process.env.MONAD_PRIVATE_KEY;
const line = () => console.log("─".repeat(72));

async function main() {
  const account = privateKeyToAccount(PK.startsWith("0x") ? PK : `0x${PK}`);
  const message = `${CHAIN.toLowerCase()}${CONTRACT.toLowerCase()}`;
  const signature = await account.signMessage({ message });

  line();
  console.log("QUORUM · validator registration");
  console.log("contract:", CONTRACT);
  console.log("signer  :", account.address);
  line();

  if (!WRITE) {
    console.log("Dry run. signed msg:", message);
    console.log("signature:", signature);
    return;
  }

  console.log("granting REGISTER_ROLE…");
  const grantRes = await validatorGrant({ chain: CHAIN, address: CONTRACT, owner_signature: signature });
  console.log("  ✓", JSON.stringify(grantRes));

  // sg_sfa_272a is the rule this whole project argues for — country-gated to Singapore, no
  // per-wallet tier/group restriction on top since Quorum's contribution is the set-level check.
  const rule = {
    allowed_group: "",
    allowed_sub_group: "",
    min_tier: 0,
    min_sub_tier: 0,
    is_black_list: false,
    countries: ["SG"],
  };

  console.log("registering as a Validator pool…");
  const regRes = await validatorRegister({ chain: CHAIN, contract_address: CONTRACT, rule, owner_signature: signature });
  console.log("  ✓", JSON.stringify(regRes));

  console.log("confirming is_register…");
  const isReg = await validatorIsRegistered(CHAIN, CONTRACT);
  console.log("  ✓", JSON.stringify(isReg));

  line();
  console.log("QuorumAsset is now a registered Validator pool.");
  line();
}

main().catch((e) => {
  console.error("\n✗", e.message);
  if (e.response) console.error(JSON.stringify(e.response, null, 2));
  process.exit(1);
});
