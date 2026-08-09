// Creates the demo cast for Quorum and answers the question the whole project rests on:
// do two wallets belonging to the SAME human share a currentKycHash?
//
// Cast: 6 people. Person 1 holds three wallets (the wallet-splitting scene). Person 6 is the
// one who gets refused after the room is full. That's 8 A-Passes.
//
//   node setup-identities.js          # dry run, prints the plan, touches nothing
//   node setup-identities.js --write  # actually registers A-Passes
import { writeFileSync, existsSync, readFileSync } from "node:fs";
import { Wallet } from "ethers";
import { generateApass, queryApass } from "./cleanverse.js";

const CHAIN = "monad";
const OUT = "./identities.json";
const WRITE = process.argv.includes("--write");
const EXPIRY = Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 365 * 3; // 3 years

// customerId: 12+ chars, strictly A-Za-z0-9. No hyphens, no underscores.
//
// Confirmed empirically 2026-08-09: currentKycHash does NOT match across a person's wallets even
// with identical identityDataList content - each generate_apass call derives its own hash.
// customerId is the actual person key: reusing the same customerId across wallet addresses groups
// them under one cvRecordId (verified via query_apass_list). One customerId PER PERSON, reused
// across all of that person's wallets - not one per wallet.
const customerId = (tag) =>
  `QRM${tag}MAIN`.padEnd(16, "0");

const PEOPLE = [
  { key: "P1", name: "Adaeze Okonkwo", idNumber: "SG8412771A", country: "SG", wallets: 3 },
  { key: "P2", name: "Marcus Tan", idNumber: "SG7719284B", country: "SG", wallets: 1 },
  { key: "P3", name: "Rina Kaur", idNumber: "SG9023117C", country: "SG", wallets: 1 },
  { key: "P4", name: "Jonas Frey", idNumber: "SG8855402D", country: "SG", wallets: 1 },
  { key: "P5", name: "Wei Lin Cheong", idNumber: "SG9134668E", country: "SG", wallets: 1 },
  { key: "P6", name: "Priya Raman", idNumber: "SG8766193F", country: "SG", wallets: 1 }, // refused
];

const identityFor = (p) => [
  {
    idType: "ID_CARD",
    fullName: p.name,
    idNumber: p.idNumber, // identical across a person's wallets — this is what we're testing
    validUntil: "2032-12-31",
    issuingCountryISO2: p.country,
  },
];

async function main() {
  if (existsSync(OUT) && WRITE) {
    console.error(`${OUT} already exists. Move it aside before re-running with --write.`);
    process.exit(1);
  }

  const cast = [];
  for (const p of PEOPLE) {
    const wallets = Array.from({ length: p.wallets }, () => {
      const w = Wallet.createRandom();
      // Each wallet gets its OWN customerId. Same human, different institutional label —
      // so a matching currentKycHash can only come from the identity data itself.
      return { address: w.address, privateKey: w.privateKey, customerId: customerId(p.key) };
    });
    cast.push({ ...p, wallets });
  }

  console.log(`Cast: ${PEOPLE.length} people, ${cast.reduce((n, p) => n + p.wallets.length, 0)} wallets\n`);
  for (const p of cast) {
    console.log(`  ${p.key} ${p.name.padEnd(16)} ${p.wallets.length} wallet(s)`);
    p.wallets.forEach((w) => console.log(`        ${w.address}  ${w.customerId}`));
  }

  if (!WRITE) {
    console.log("\nDry run. Re-run with --write to register these against the sandbox.");
    return;
  }

  console.log("\nRegistering A-Passes...\n");
  for (const p of cast) {
    for (const w of p.wallets) {
      try {
        const res = await generateApass({
          customerId: w.customerId,
          expirationTime: EXPIRY,
          override: false,
          wallet: { address: w.address, chain: CHAIN },
          identityDataList: identityFor(p),
        });
        w.cvRecordId = res.cvRecordId;
        w.tier = res.tier;
        w.txHash = res.wallet?.txHash;
        console.log(`  OK   ${p.key} ${w.address}  tier=${res.tier}  tx=${w.txHash ?? "-"}`);
      } catch (e) {
        w.error = e.message;
        console.log(`  FAIL ${p.key} ${w.address}  ${e.message}`);
      }
      await new Promise((r) => setTimeout(r, 1200)); // be polite; the sandbox is shared
    }
  }

  console.log("\nReading back currentKycHash for each wallet...\n");
  for (const p of cast) {
    for (const w of p.wallets) {
      try {
        const a = await queryApass(CHAIN, w.address);
        w.currentKycHash = a.currentKycHash;
        w.status = a.status;
        w.countries = a.countries;
        console.log(`  ${p.key} ${w.address.slice(0, 12)}…  ${a.currentKycHash}`);
      } catch (e) {
        console.log(`  ${p.key} ${w.address.slice(0, 12)}…  read failed: ${e.message}`);
      }
      await new Promise((r) => setTimeout(r, 400));
    }
  }

  writeFileSync(OUT, JSON.stringify({ chain: CHAIN, expiry: EXPIRY, cast }, null, 2));
  console.log(`\nWrote ${OUT} (contains private keys — never commit this)\n`);

  verdict(cast);
}

function verdict(cast) {
  const p1 = cast.find((p) => p.key === "P1");
  const hashes = p1.wallets.map((w) => w.currentKycHash).filter(Boolean);
  const others = cast.filter((p) => p.key !== "P1").flatMap((p) => p.wallets.map((w) => w.currentKycHash)).filter(Boolean);

  console.log("=".repeat(64));
  if (hashes.length < 2) {
    console.log("INCONCLUSIVE — fewer than two hashes came back for P1. Check the errors above.");
  } else if (new Set(hashes).size === 1 && !others.includes(hashes[0])) {
    console.log("CONFIRMED. P1's three wallets share one currentKycHash, and no other person");
    console.log("shares it. currentKycHash is the personId. Quorum works as designed.");
  } else if (new Set(hashes).size === 1) {
    console.log("PARTIAL. P1's wallets match each other, but the hash collides with another");
    console.log("person — so it is not identity-derived. Fall back to customerId grouping.");
  } else {
    console.log("NOT CONFIRMED. P1's wallets produced different hashes:");
    hashes.forEach((h, i) => console.log(`   wallet ${i + 1}: ${h}`));
    console.log("\nFall back: group by customerId via query_apass_list, and assign one");
    console.log("customerId per person rather than per wallet. Re-plan before Aug 8.");
  }
  console.log("=".repeat(64));
}

main().catch((e) => {
  console.error("\nFatal:", e.message);
  if (e.response) console.error(JSON.stringify(e.response, null, 2));
  process.exit(1);
});
