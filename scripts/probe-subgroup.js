// Probe 1 of 2 for layer 4: does generate_apass with override:true mutate subGroup on an
// EXISTING A-Pass record? Runs against a throwaway wallet so the live demo cast is untouched.
import { Wallet } from "ethers";
import { generateApass, queryApass, queryApassList } from "./cleanverse.js";

const CHAIN = "monad";
const EXPIRY = Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 365;
const CUSTOMER = "QRMSUBGROUPTEST1";

const identity = [{
  idType: "ID_CARD", fullName: "Subgroup Probe", idNumber: "SG9999001Z",
  validUntil: "2032-12-31", issuingCountryISO2: "SG",
}];

async function readBack(label, address){
  const a = await queryApass(CHAIN, address);
  const list = await queryApassList({ chain: CHAIN, walletAddress: address });
  const row = list.items && list.items[0];
  console.log(`  ${label}: subGroup=${JSON.stringify(a.subGroup)} (query_apass) | ` +
    `subGroup=${JSON.stringify(row && row.subGroup)} tier=${row && row.tier} (query_apass_list)`);
}

async function main(){
  const w = Wallet.createRandom();
  console.log("throwaway wallet:", w.address);

  console.log("\n1. register WITHOUT subGroup");
  await generateApass({
    customerId: CUSTOMER, expirationTime: EXPIRY, override: false,
    wallet: { address: w.address, chain: CHAIN }, identityDataList: identity,
  });
  await new Promise(r => setTimeout(r, 2500));
  await readBack("after initial register", w.address);

  console.log("\n2. re-register WITH subGroup=QS and override:true");
  const res = await generateApass({
    customerId: CUSTOMER, expirationTime: EXPIRY, override: true, subGroup: "QS",
    wallet: { address: w.address, chain: CHAIN }, identityDataList: identity,
  });
  console.log("   response:", JSON.stringify(res));
  await new Promise(r => setTimeout(r, 3000));
  await readBack("after override write", w.address);

  console.log("\n3. flip it back to QU (proving it is mutable, not just set-once)");
  await generateApass({
    customerId: CUSTOMER, expirationTime: EXPIRY, override: true, subGroup: "QU",
    wallet: { address: w.address, chain: CHAIN }, identityDataList: identity,
  });
  await new Promise(r => setTimeout(r, 3000));
  await readBack("after second write", w.address);

  console.log("\nVERDICT: if subGroup went null -> QS -> QU, layer 4's write half works.");
}

main().catch((e) => {
  console.error("✗", e.message);
  if (e.response) console.error(JSON.stringify(e.response, null, 2));
  process.exit(1);
});
