// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {NFTMarketplace} from "../src/Marketplace.sol";
import {console} from "forge-std/console.sol";

/**
 * @title DeployNFTMarketplace
 * @author SALAMI SELIM
 * @notice Script to deploy the NFTMarketplace contract
 * @dev Deploys with a specified marketplace fee, name, and symbol
 */
contract DeployNFTMarketplace is Script {
    uint256 public constant MARKETPLACE_FEE = 250; // 2.5% fee (in basis points)
    string public constant NAME = "NFT Marketplace";
    string public constant SYMBOL = "NFTM";

    function run() external returns (NFTMarketplace) {
        vm.startBroadcast();
        
        // Deploy the NFTMarketplace contract
        NFTMarketplace marketplace = new NFTMarketplace(
            MARKETPLACE_FEE,
            NAME,
            SYMBOL
        );
        
        console.log("NFTMarketplace deployed at:", address(marketplace));
        console.log("Deployer (owner):", msg.sender);
        console.log("Marketplace fee:", marketplace.getMarketplaceFee());
        
        vm.stopBroadcast();
        return marketplace;
    }
}