NFT Marketplace
A simple NFT Marketplace smart contract built with Solidity and tested using Foundry. Users can list, buy, cancel, and update NFT listings, withdraw proceeds, and the owner can manage fees.
Overview

Contract: src/Marketplace.sol (NFTMarketplace)
List NFTs for sale.
Buy listed NFTs.
Cancel or update listings.
Withdraw sale proceeds.
Owner can update marketplace fee (≤10%) or emergency withdraw NFTs.
Supports direct ETH transfers with an event.


Tests: test/Marketplace.t.sol
Tests all functions, reverts, and events using a mock ERC721 contract.


Dependencies: OpenZeppelin, Foundry.

Setup

Install Foundry:
curl -L https://foundry.paradigm.xyz | bash
foundryup


Clone Repository:
git clone <repository-url>
cd nft-marketplace


Install Dependencies:
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install foundry-rs/forge-std --no-commit


Configure foundry.toml:
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
remappings = ["@openzeppelin/contracts=node_modules/@openzeppelin/contracts", "forge-std=lib/forge-std/src"]
via_ir = true
optimizer = true
optimizer_runs = 200


Compile:
forge build



Testing
Run the test suite to verify functionality:
forge test --match-path test/Marketplace.t.sol -vvvv

Test Cases

Listing: Tests successful listing, event emission, and reverts for zero price, unapproved NFTs, and already listed NFTs.
Buying: Tests successful purchases, overpayment refunds, event emission, and reverts for non-listed NFTs or insufficient payment.
Canceling: Tests successful cancellation and reverts for non-listed or non-seller attempts.
Updating: Tests price updates and reverts for non-seller attempts.
Proceeds: Tests withdrawing proceeds and reverts for no proceeds.
Fees: Tests owner fee updates and reverts for invalid or non-owner attempts.
ETH Receive: Tests direct ETH transfers with event emission.

Event Emission Test:

Issue: test_BuyItem_EmitsEvent lacked listing setup and had redundant calls.
Fix: Added listing step and removed extra buyItem call.



Dependencies

Foundry: For building, testing, and deployment.
OpenZeppelin: For ERC721 and Ownable contracts.
Forge-std: For testing utilities.

Future Improvements

Add auction functionality (noted by unused AuctionNotEnded and AuctionEnded errors).
Optimize gas usage in buyItem and other functions.
Add more fuzz tests for edge cases.

License
MIT License