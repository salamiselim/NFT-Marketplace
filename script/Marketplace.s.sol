// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {NFTMarketplace} from "../src/Marketplace.sol";

contract DeployNFTMarketplace is Script {
    uint256 constant INITIAL_FEE = 250; // 2.5%

    function run() external returns (NFTMarketplace) {
        vm.startBroadcast();
        NFTMarketplace marketplace = new NFTMarketplace(INITIAL_FEE);
        vm.stopBroadcast();
        console.log(" Contract address: %s", address(marketplace));
        return marketplace;
    }
}