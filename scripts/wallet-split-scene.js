// Demo scene: P1 moves value to their own second and third wallets. Ten addresses would look like
// two new holders to any per-wallet system; here it's one person, no seat consumed.
import { readFileSync } from "node:fs";
import { createWalletClient, createPublicClient, http, getContract, parseEther } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import "dotenv/config";

const QUORUM_ASSET = process.argv[process.argv.indexOf("--asset") + 1];
const SEAT_LEDGER = process.argv[process.argv.indexOf("--seatledger") + 1];

const ASSET_ABI = [
  { type: "function", name: "transfer", stateMutability: "nonpayable", inputs: [{ name: "to", type: "address" }, { name: "value", type: "uint256" }], outputs: [{ name: "", type: "bool" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "", type: "address" }], outputs: [{ name: "", type: "uint256" }] },
];
const LEDGER_ABI = [
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
  const p1 = doc.cast.find((p) => p.key === "P1");
  const [w1, w2, w3] = p1.wallets;

  const identitiesRaw = JSON.parse(readFileSync("./identities.json", "utf8"));
  const p1Full = identitiesRaw.cast.find((p) => p.key === "P1");
  const pk1 = p1Full.wallets[0].privateKey;

  const account = privateKeyToAccount(pk1);
  const publicClient = createPublicClient({ chain: monad, transport: http() });
  const walletClient = createWalletClient({ account, chain: monad, transport: http() });
  const asset = getContract({ address: QUORUM_ASSET, abi: ASSET_ABI, client: { public: publicClient, wallet: walletClient } });

  const before = await publicClient.readContract({ address: SEAT_LEDGER, abi: LEDGER_ABI, functionName: "activeSeats" });
  console.log(`activeSeats before: ${before}`);

  console.log(`\nP1 wallet1 (${w1.address}) -> wallet2 (${w2.address}): 30 QNOTE`);
  let hash = await asset.write.transfer([w2.address, parseEther("30")]);
  await publicClient.waitForTransactionReceipt({ hash });
  console.log(`  ✓ tx=${hash}`);

  console.log(`\nP1 wallet1 (${w1.address}) -> wallet3 (${w3.address}): 20 QNOTE`);
  hash = await asset.write.transfer([w3.address, parseEther("20")]);
  await publicClient.waitForTransactionReceipt({ hash });
  console.log(`  ✓ tx=${hash}`);

  const after = await publicClient.readContract({ address: SEAT_LEDGER, abi: LEDGER_ABI, functionName: "activeSeats" });
  console.log(`\nactiveSeats after: ${after} (unchanged = wallet-splitting did not manufacture a seat)`);

  const bal1 = await publicClient.readContract({ address: QUORUM_ASSET, abi: ASSET_ABI, functionName: "balanceOf", args: [w1.address] });
  const bal2 = await publicClient.readContract({ address: QUORUM_ASSET, abi: ASSET_ABI, functionName: "balanceOf", args: [w2.address] });
  const bal3 = await publicClient.readContract({ address: QUORUM_ASSET, abi: ASSET_ABI, functionName: "balanceOf", args: [w3.address] });
  console.log(`\nbalances: wallet1=${bal1} wallet2=${bal2} wallet3=${bal3}`);
}

main().catch((e) => {
  console.error("✗", e.message);
  process.exit(1);
});
