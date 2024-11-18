// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {BaseLogoNFT} from "../src/BaseLogoNFT.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        
        address payable initialOwner = payable(0x7Bc1C072742D8391817EB4Eb2317F98dc72C61dB);
        new BaseLogoNFT(initialOwner);
       
        vm.stopBroadcast();
    }
}

