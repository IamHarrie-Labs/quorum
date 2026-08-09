// Fills the 5-seat demo pack live: issues QuorumAsset to P1-P5 (P1's first wallet), then attempts
// P6 and captures the on-chain refusal. Real transactions, real reverts.
import { readFileSync } from "node:fs";
import { createWalletClient, createPublicClient, http, getContract, parseEther } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import "dotenv/config";

const QUORUM_ASSET = process.argv[process.argv.indexOf("--asset") + 1];
if (!QUORUM_ASSET?.startsWith("0x")) {
  console.error("Usage: node fill-seats.js --asset 0x...");
  process.exit(1);
}

const ABI = [
  { type: "function", name: "issue", stateMutability: "nonpayable", inputs: [{ name: "to", type: "address" }, { name: "amount", type: "uint256" }], outputs: [] },
  { type: "function", name: "preflight", stateMutability: "view", inputs: [{ name: "from", type: "address" }, { name: "to", type: "address" }, { name: "value", type: "uint256" }], outputs: [{ name: "allowed", type: "bool" }, { name: "reason", type: "bytes32" }, { name: "seatsAfter", type: "uint32" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "", type: "address" }], outputs: [{ name: "", type: "uint256" }] },
];
const SEAT_LEDGER_ABI = [
  { type: "function", name: "activeSeats", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "uint32" }] },
];

const monad = {
  id: 10143,
  name: "Monad Testnet",
  nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
  rpcUrls: { default: { http: [process.env.MONAD_RPC_URL ?? "https://testnet-rpc.monad.xyz"] } },
};

async function main() {
  const doc = JSON.parse(readFileSync("../scripts/demo-cast.json", "utf8"));
  const account = privateKeyToAccount(process.env.MONAD_PRIVATE_KEY);
  const publicClient = createPublicClient({ chain: monad, transport: http() });
  const walletClient = createWalletClient({ account, chain: monad, transport: http() });
  const asset = getContract({ address: QUORUM_ASSET, abi: ABI, client: { public: publicClient, wallet: walletClient } });

  const AMOUNT = parseEther("100");
  const results = { issued: [], refusal: null };

  console.log("Filling seats 1-5...\n");
  for (const p of doc.cast.slice(0, 5)) {
    const to = p.wallets[0].address;
    const hash = await asset.write.issue([to, AMOUNT]);
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    const seats = await publicClient.readContract({ address: doc.seatLedger ?? undefined, abi: SEAT_LEDGER_ABI, functionName: "activeSeats" }).catch(() => null);
    console.log(`  ✓ ${p.key} ${p.name}  issued 100 QNOTE  tx=${hash}  status=${receipt.status}`);
    results.issued.push({ key: p.key, to, txHash: hash, blockNumber: receipt.blockNumber.toString() });
  }

  console.log("\nAttempting P6 (should be refused)...\n");
  const p6 = doc.cast.find((p) => p.key === "P6");
  const to6 = p6.wallets[0].address;

  const [allowed, reason, seatsAfter] = await asset.read.preflight(["0x0000000000000000000000000000000000000000", to6, AMOUNT]);
  console.log(`  preflight: allowed=${allowed} reason=${Buffer.from(reason.slice(2), "hex").toString("utf8").replace(/\0/g, "")} seatsAfter=${seatsAfter}`);

  try {
    const hash = await asset.write.issue([to6, AMOUNT]);
    await publicClient.waitForTransactionReceipt({ hash });
    console.log("  UNEXPECTED: P6 issuance succeeded:", hash);
  } catch (e) {
    console.log(`  ✓ P6 refused on-chain: ${e.shortMessage ?? e.message}`);
    results.refusal = { key: "P6", to: to6, error: e.shortMessage ?? e.message };
  }

  console.log("\n" + JSON.stringify(results, null, 2));
}

main().catch((e) => {
  console.error("✗", e.message);
  process.exit(1);
});
