// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {NFTMarketplace} from "../src/Marketplace.sol";
import {console} from "forge-std/console.sol";

/**
 * @title DeployNFTMarketplace
 * @author SALAMI SELIM
 * @notice Deploys the NFTMarketplace
 */
contract DeployNFTMarketplace is Script {
    uint256 public constant MARKETPLACE_FEE_BPS = 250;

    function run() external returns (NFTMarketplace) {
        vm.startBroadcast();

        NFTMarketplace marketplace = new NFTMarketplace(MARKETPLACE_FEE_BPS);
        console.log("NFTMarketplace deployed at:", address(marketplace));
        console.log("Owner (deployer):         ", msg.sender);
        vm.stopBroadcast();
        return marketplace;

    }
}