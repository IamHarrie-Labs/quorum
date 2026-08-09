// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PersonRegistry} from "../src/PersonRegistry.sol";
import {SeatLedger} from "../src/SeatLedger.sol";
import {QuorumAsset} from "../src/QuorumAsset.sol";

/// @notice Deploys the demo pack: standing cap of 5 persons, concentration ceiling disabled at
///         first (enable live during the concentration scene). Mirrors test/Scenes.t.sol exactly
///         so what airs in the video is what passed in CI.
contract Deploy is Script {
    address constant MONAD_APASS = 0xbA82D189540CaC9DC6FF46B6837CaC1BFdEC58B9;
    uint32 constant MAX_PERSONS = 5;
    uint32 constant WINDOW_DAYS = 0; // standing cap for the demo pack, not rolling
    uint16 constant CONCENTRATION_CEILING_BPS = 10_000; // disabled until the scene needs it

    function run() external {
        vm.startBroadcast();

        PersonRegistry registry = new PersonRegistry(MONAD_APASS);
        SeatLedger ledger = new SeatLedger(MAX_PERSONS, WINDOW_DAYS);
        QuorumAsset asset =
            new QuorumAsset("Quorum Note", "QNOTE", registry, ledger, CONCENTRATION_CEILING_BPS);

        ledger.setOperator(address(asset), true);

        vm.stopBroadcast();

        console.log("PersonRegistry:", address(registry));
        console.log("SeatLedger:", address(ledger));
        console.log("QuorumAsset:", address(asset));
    }
}
