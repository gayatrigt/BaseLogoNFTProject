// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {BaseLogoNFT} from "../src/BaseLogoNFT.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        new BaseLogoNFT(0x84a5413b6d840C75Dc8e5F6Eb56E0D1C3eD3337C);
        vm.stopBroadcast();
    }
}
