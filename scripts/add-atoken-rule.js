// Adds the SG country compliance rule to the registered A-Token.
// add_rule is create-only: submitting the same rule twice is rejected, there is no update.
import { addATokenRule } from "./cleanverse.js";

const CHAIN = "monad";
const ATOKEN = process.argv[process.argv.indexOf("--atoken") + 1];
if (!ATOKEN?.startsWith("0x")) {
  console.error("Usage: node add-atoken-rule.js --atoken 0x...");
  process.exit(1);
}

const rule = {
  allowed_group: "",
  allowed_sub_group: "",
  min_tier: 0,
  min_sub_tier: 0,
  is_black_list: false,
  countries: ["SG"],
};

addATokenRule({ chain: CHAIN, atoken_address: ATOKEN, rule })
  .then((res) => console.log("✓", JSON.stringify(res)))
  .catch((e) => {
    console.error("✗", e.message);
    if (e.response) console.error(JSON.stringify(e.response, null, 2));
    process.exit(1);
  });
