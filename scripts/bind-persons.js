// Binds every wallet in identities.json to a personId in the live PersonRegistry contract.
//
// personHash = keccak256(customerId) - customerId is the confirmed person key (see
// setup-identities.js), reused across a person's wallets, so wallets sharing a customerId land on
// the same personId. This is a real on-chain write per wallet.
//
// Usage: node bind-persons.js --registry 0x... [--write]
import { readFileSync } from "node:fs";
import { createWalletClient, http, keccak256, toBytes, getContract, createPublicClient } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import "dotenv/config";

const args = process.argv.slice(2);
const WRITE = args.includes("--write");
const REGISTRY = args[args.indexOf("--registry") + 1];
if (!REGISTRY?.startsWith("0x")) {
  console.error("Usage: node bind-persons.js --registry 0x... [--write]");
  process.exit(1);
}

const ABI = [
  {
    type: "function",
    name: "bind",
    stateMutability: "nonpayable",
    inputs: [
      { name: "wallet", type: "address" },
      { name: "kycHash", type: "bytes32" },
    ],
    outputs: [{ name: "personId", type: "uint256" }],
  },
  {
    type: "function",
    name: "personOf",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
];

const monad = {
  id: 10143,
  name: "Monad Testnet",
  nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
  rpcUrls: { default: { http: [process.env.MONAD_RPC_URL ?? "https://testnet-rpc.monad.xyz"] } },
};

async function main() {
  const doc = JSON.parse(readFileSync("./identities.json", "utf8"));
  const account = privateKeyToAccount(process.env.MONAD_PRIVATE_KEY);
  const publicClient = createPublicClient({ chain: monad, transport: http() });
  const walletClient = createWalletClient({ account, chain: monad, transport: http() });
  const registry = getContract({ address: REGISTRY, abi: ABI, client: { public: publicClient, wallet: walletClient } });

  console.log(`Binding ${doc.cast.reduce((n, p) => n + p.wallets.length, 0)} wallets to PersonRegistry ${REGISTRY}`);
  console.log(WRITE ? "mode: WRITE" : "mode: DRY RUN");

  for (const p of doc.cast) {
    const personHash = keccak256(toBytes(p.wallets[0].customerId));
    console.log(`\n${p.key} ${p.name}  customerId=${p.wallets[0].customerId}  hash=${personHash}`);
    for (const w of p.wallets) {
      if (!WRITE) {
        console.log(`  [dry] bind(${w.address}, ${personHash})`);
        continue;
      }
      try {
        const hash = await registry.write.bind([w.address, personHash]);
        await publicClient.waitForTransactionReceipt({ hash });
        const personId = await registry.read.personOf([w.address]);
        console.log(`  ✓ ${w.address}  personId=${personId}  tx=${hash}`);
      } catch (e) {
        console.log(`  ✗ ${w.address}  ${e.shortMessage ?? e.message}`);
      }
    }
  }
}

main().catch((e) => {
  console.error("\n✗", e.message);
  process.exit(1);
});
