// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {QuorumFactory} from "../src/QuorumFactory.sol";

contract DeployFactory is Script {
    function run() external {
        vm.startBroadcast();
        QuorumFactory factory = new QuorumFactory();
        vm.stopBroadcast();
        console.log("QuorumFactory:", address(factory));
    }
}
