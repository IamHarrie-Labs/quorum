// LAYER 4 — Quorum writes its conclusion back into Cleanverse's own credential.
//
// Cleanverse's rule engine is structurally incapable of computing an aggregate: every rule it has
// is a per-wallet attribute check (tier, subTier, group, subGroup, country). It can never answer
// "how many distinct people hold this asset."
//
// Quorum can. So Quorum computes the set-level answer on-chain — does this person hold a seat —
// and writes it back into each of that person's A-Pass records as a subGroup tag. An A-Token rule
// with allowed_sub_group "QS" then makes CLEANVERSE'S OWN ENGINE refuse anyone Quorum never
// seated, using the one rule shape it does have. The aggregate is precomputed and handed over as
// a per-wallet attribute.
//
// Belt and braces: the contract still enforces the cap by itself. This layer is an additional,
// independently-reached refusal, never the load-bearing one.
//
// Usage: node writeback-seats.js [--write]
import { readFileSync } from "node:fs";
import { createPublicClient, http } from "viem";
import { generateApass, queryApassList } from "./cleanverse.js";
import "dotenv/config";

const CHAIN = "monad";
const SEATED = "QS";
const UNSEATED = "QU";
const WRITE = process.argv.includes("--write");

const SEAT_LEDGER = "0x5f80999D2e449479E3765f81666A245135de0aca";
const LEDGER_ABI = [{
  type: "function", name: "holdsSeat", stateMutability: "view",
  inputs: [{ name: "", type: "uint256" }], outputs: [{ name: "", type: "bool" }],
}];

const monad = {
  id: 10143, name: "Monad Testnet",
  nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
  rpcUrls: { default: { http: [process.env.MONAD_RPC_URL ?? "https://testnet-rpc.monad.xyz"] } },
};

async function main(){
  const cast = JSON.parse(readFileSync("../scripts/demo-cast.json", "utf8"));
  // identities.json is local-only (gitignored) and carries the identity payload we must echo back
  // on override so the A-Pass keeps its country tags — dropping identityDataList would strip the
  // SG tag the A-Token country rule depends on.
  const ids = JSON.parse(readFileSync("./identities.json", "utf8"));
  const client = createPublicClient({ chain: monad, transport: http() });

  console.log(WRITE ? "mode: WRITE" : "mode: DRY RUN");
  console.log("Reading seat state from SeatLedger, writing it into Cleanverse A-Passes.\n");

  for(const p of cast.cast){
    const seated = await client.readContract({
      address: SEAT_LEDGER, abi: LEDGER_ABI, functionName: "holdsSeat", args: [BigInt(p.personId)],
    });
    const tag = seated ? SEATED : UNSEATED;
    const src = ids.cast.find(x => x.key === p.key);
    const identityDataList = [{
      idType: "ID_CARD", fullName: src.name, idNumber: src.idNumber,
      validUntil: "2032-12-31", issuingCountryISO2: src.country,
    }];

    console.log(`${p.key} personId=${p.personId} holdsSeat=${seated} -> subGroup ${tag}`);
    for(const w of p.wallets){
      if(!WRITE){ console.log(`   [dry] ${w.address}`); continue; }
      try{
        await generateApass({
          customerId: p.customerId,
          expirationTime: ids.expiry,
          override: true,
          subGroup: tag,
          wallet: { address: w.address, chain: CHAIN },
          identityDataList,
        });
        console.log(`   ✓ ${w.address}`);
      }catch(e){
        console.log(`   ✗ ${w.address}  ${e.message}`);
      }
      await new Promise(r => setTimeout(r, 1200));
    }
  }

  if(!WRITE) return;

  console.log("\nReading tags back from query_apass_list…");
  await new Promise(r => setTimeout(r, 3000));
  for(const p of cast.cast){
    for(const w of p.wallets){
      const list = await queryApassList({ chain: CHAIN, walletAddress: w.address });
      const row = list.items && list.items[0];
      console.log(`  ${p.key} ${w.address.slice(0,10)}…  subGroup=${JSON.stringify(row && row.subGroup)}  countries=${JSON.stringify(row && row.countries)}`);
      await new Promise(r => setTimeout(r, 300));
    }
  }
}

main().catch((e) => {
  console.error("✗", e.message);
  if (e.response) console.error(JSON.stringify(e.response, null, 2));
  process.exit(1);
});
