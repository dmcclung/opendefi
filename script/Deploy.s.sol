// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {LoanMarketFactory} from "../src/LoanMarketFactory.sol";

contract Deploy is Script {
    function run() external returns (LoanMarketFactory factory) {
        vm.startBroadcast();
        factory = new LoanMarketFactory();
        vm.stopBroadcast();
        console.log("LoanMarketFactory deployed at", address(factory));
    }
}
