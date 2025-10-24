# QuivaComic and NFT Marketplace (ERC-1155)

A **multi-edition ERC-1155 NFT platform** built on **Hedera** using **Foundry**.  
Includes:
- `QuivaComic.sol` — Mint with creator roles
- `NFTMarketplace.sol` — List, buy, cancel, update, and withdraw for ERC-1155 NFTs

Fully tested. Ready to deploy on **Hedera Testnet**.

---

## Overview

### `QuivaComic.sol` — ERC-1155 Comic NFT
- **Multi-edition minting** (1-of-1 or 100+ copies)
- **Creator roles** (admin + multiple creators)
- **Metadata fallback**: `baseURI + tokenId`
- **Batch minting** & `mintMore()`
- **Access control** via OpenZeppelin

### `NFTMarketplace.sol` — ERC-1155 Marketplace
- List **any amount** of ERC-1155 tokens
- Buy with **exact or overpay + refund**
- Cancel, update price, withdraw proceeds
- **2.5% fee** (configurable by owner)


---

## Project Structure
