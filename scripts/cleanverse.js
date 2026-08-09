// Minimal Cleanverse Cooperate API client.
//
// Encrypted endpoints take AES/CBC/PKCS5Padding with a fixed all-zero IV, keyed on the
// Base64-DECODED api-key, wrapped as {"data": "<base64 ciphertext>"}. Everything else is plain
// JSON. The api-key never goes in a header — only the api-id does.
import crypto from "node:crypto";
import "dotenv/config";

const BASE = process.env.CV_BASE_URL ?? "https://uatapi.cleanverse.com/api/cooperate";
const API_ID = process.env.CV_API_ID;
const API_KEY = process.env.CV_API_KEY;

if (!API_ID || !API_KEY) {
  console.error("Missing CV_API_ID or CV_API_KEY. Copy .env.example to .env and fill it in.");
  process.exit(1);
}

const KEY = Buffer.from(API_KEY, "base64");
const IV = Buffer.alloc(16, 0);
const CIPHER = { 16: "aes-128-cbc", 24: "aes-192-cbc", 32: "aes-256-cbc" }[KEY.length];
if (!CIPHER) throw new Error(`Unexpected api-key length after base64 decode: ${KEY.length} bytes`);

export function encrypt(plainObject) {
  const c = crypto.createCipheriv(CIPHER, KEY, IV); // PKCS5 == PKCS7 at this block size
  return Buffer.concat([c.update(JSON.stringify(plainObject), "utf8"), c.final()]).toString("base64");
}

export function decrypt(b64) {
  const d = crypto.createDecipheriv(CIPHER, KEY, IV);
  return JSON.parse(
    Buffer.concat([d.update(Buffer.from(b64, "base64")), d.final()]).toString("utf8")
  );
}

async function request(method, path, { body, encrypted = false } = {}) {
  const headers = { "api-id": API_ID, "X-Request-ID": crypto.randomUUID() };
  let payload;
  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
    payload = JSON.stringify(encrypted ? { data: encrypt(body) } : body);
  }
  const res = await fetch(`${BASE}${path}`, { method, headers, body: payload });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw new Error(`HTTP ${res.status} — non-JSON response: ${text.slice(0, 300)}`);
  }
  // Cleanverse returns HTTP 200 with a business code; "0000" is the only success.
  if (json.code !== "0000") {
    const err = new Error(`${path} failed [${json.code}] ${json.message}`);
    err.response = json;
    throw err;
  }
  return json.data;
}

export const post = (path, body, encrypted = false) => request("POST", path, { body, encrypted });
export const get = (path) => request("GET", path);

// --- endpoint wrappers we actually use -------------------------------------

export const generateApass = (payload) => post("/generate_apass", payload, true);
export const queryApass = (chain, address) => post("/query_apass", { chain, address });
export const queryApassList = (filters = {}) => post("/query_apass_list", filters);
export const verifyApass = (chain, atoken, address) =>
  post("/verify_apass", { chain, atoken, address });
// status: "1" activate/unfreeze, "2" freeze. Drives the live revocation scene.
export const updateStatus = (payload) => post("/update_status", payload, true);

// We register our OWN deployed contract rather than using /atoken/launch — launch has Cleanverse
// deploy the token, which leaves no transfer hook to put the seat logic in.
export const registerAToken = (payload) => post("/atoken/register_atoken", payload, true);
export const launchAToken = (payload) => post("/atoken/launch", payload, true);
export const queryApplyStatus = (requestId) => get(`/atoken/query_apply_status/${requestId}`);
export const listMyATokens = (qs = "") => get(`/atoken/list_my_atokens${qs}`);

// A-Token rules are create-only and reject duplicates; there is no update, only add/remove.
export const addATokenRule = (payload) => post("/atoken/add_rule", payload, true);
export const removeATokenRule = (payload) => post("/atoken/remove_rule", payload, true);
export const queryATokenRules = (chain, atoken_address) =>
  post("/atoken/rules", { chain, atoken_address });
export const setATokenPaused = (payload) => post("/atoken/set_paused", payload, true);
export const queryDepositATokenList = (chain) => post("/query_deposit_atoken_list", { chain });
export const faucet = (payload) => post("/faucet", payload);
export const downloadTravelRule = (payload) => post("/download_travel_rule", payload);

// Validator module — the deep-integration path. Reads are plain, writes are encrypted.
export const validatorGrant = (payload) => post("/validator/grant", payload, true);
export const validatorRegister = (payload) => post("/validator/register", payload, true);
export const validatorIsRegistered = (chain, contract_address) =>
  post("/validator/is_register", { chain, contract_address });
export const validatorSetRule = (payload) => post("/validator/set_rule", payload, true);
export const validatorRules = (chain, contract_address) =>
  post("/validator/rules", { chain, contract_address });
export const validatorVerify = (chain, contract_address, user_address) =>
  post("/validator/verify", { chain, contract_address, user_address });
