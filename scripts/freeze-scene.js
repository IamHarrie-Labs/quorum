// Live revocation scene: freeze P3's A-Pass through Cleanverse, show the seat is retained
// (in law they still hold) but verify_apass flips, then unfreeze and confirm recovery.
import { updateStatus, verifyApass } from "./cleanverse.js";

const CHAIN = "monad";
const ATOKEN = "0x26B57c58C20C171233e15c73fA1bD814b269dD88";
const P3_WALLET = "0x3570D7aAFb5C6240Fd55D0e5Ea8319Ef4a5959C2";

async function verdict(label){
  const v = await verifyApass(CHAIN, ATOKEN, P3_WALLET);
  console.log(`  ${label}: code=${v.code} message="${v.message}"`);
  return v;
}

async function main(){
  console.log("Before freeze:");
  await verdict("verify_apass");

  console.log("\nFreezing P3's A-Pass (status=2)...");
  const freezeRes = await updateStatus({
    status: "2",
    blacklistReason: "Quorum demo - live revocation scene",
    wallet: { chain: CHAIN, address: P3_WALLET },
  });
  console.log("  ✓", JSON.stringify(freezeRes));

  await new Promise((r) => setTimeout(r, 2000));
  console.log("\nAfter freeze:");
  await verdict("verify_apass");

  console.log("\nUnfreezing (status=1)...");
  const unfreezeRes = await updateStatus({
    status: "1",
    wallet: { chain: CHAIN, address: P3_WALLET },
  });
  console.log("  ✓", JSON.stringify(unfreezeRes));

  await new Promise((r) => setTimeout(r, 2000));
  console.log("\nAfter unfreeze:");
  await verdict("verify_apass");
}

main().catch((e) => {
  console.error("✗", e.message);
  if (e.response) console.error(JSON.stringify(e.response, null, 2));
  process.exit(1);
});
