// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract NFTMarketplace is Ownable, ReentrancyGuard, IERC721Receiver {
    // CUSTOM ERRORS
    error NFTMarketplace__PriceMustBeAboveZero();
    error NFTMarketplace__NotListed(address nftAddress, uint256 tokenId);
    error NFTMarketplace__PriceNotMet(address nftAddress, uint256 tokenId, uint256 price);
    error NFTMarketplace__NotOwner();
    error NFTMarketplace__AlreadyListed(address nftAddress, uint256 tokenId);
    error NFTMarketplace__NoProceeds();
    error NFTMarketplace__TransferFailed();
    error NFTMarketplace__InvalidNFTAddress();
    error NFTMarketplace__NotERC721();
    error NFTMarketplace__InvalidFee();
    error NFTMarketplace__NotApprovedForMarketplace();

    struct Listing {
        uint256 price;
        address seller;
    }

    uint256 private constant MAX_FEE_BPS = 1000;
    uint256 private s_marketplaceFeeBps;
    uint256 private s_totalSales;
    uint256 private s_totalVolume;
    uint256 private s_currentListings;

    mapping(address => mapping(uint256 => Listing)) private s_listings;
    mapping(address => uint256) private s_proceeds;

    event ItemListed(address indexed seller, address indexed nftAddress, uint256 indexed tokenId, uint256 price);
    event ItemBought(
        address indexed buyer, address indexed nftAddress, uint256 indexed tokenId, uint256 price, address seller
    );
    event ItemCanceled(address indexed seller, address indexed nftAddress, uint256 indexed tokenId);
    event ListingUpdated(
        address indexed seller, address indexed nftAddress, uint256 indexed tokenId, uint256 oldPrice, uint256 newPrice
    );
    event ProceedsWithdrawn(address indexed seller, uint256 amount);
    event EthReceived(address indexed sender, uint256 amount);

    constructor(uint256 marketplaceFeeBps) Ownable(msg.sender) {
        if (marketplaceFeeBps > MAX_FEE_BPS) revert NFTMarketplace__InvalidFee();
        s_marketplaceFeeBps = marketplaceFeeBps;
    }

    function listItem(address nftAddress, uint256 tokenId, uint256 price) external nonReentrant {
        if (price == 0) revert NFTMarketplace__PriceMustBeAboveZero();
        if (nftAddress == address(0)) revert NFTMarketplace__InvalidNFTAddress();
        if (!IERC721(nftAddress).supportsInterface(type(IERC721).interfaceId)) {
            revert NFTMarketplace__NotERC721();
        }
        if (s_listings[nftAddress][tokenId].price != 0) {
            revert NFTMarketplace__AlreadyListed(nftAddress, tokenId);
        }

        if (
            IERC721(nftAddress).getApproved(tokenId) != address(this)
                && IERC721(nftAddress).isApprovedForAll(msg.sender, address(this)) == false
        ) {
            revert NFTMarketplace__NotApprovedForMarketplace();
        }

        IERC721(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId);

        s_listings[nftAddress][tokenId] = Listing({price: price, seller: msg.sender});
        s_currentListings++;

        emit ItemListed(msg.sender, nftAddress, tokenId, price);
    }

    function cancelListing(address nftAddress, uint256 tokenId) external nonReentrant {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price == 0) revert NFTMarketplace__NotListed(nftAddress, tokenId);
        if (listing.seller != msg.sender) revert NFTMarketplace__NotOwner();

        delete s_listings[nftAddress][tokenId];
        s_currentListings--;

        IERC721(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId);

        emit ItemCanceled(msg.sender, nftAddress, tokenId);
    }

    function updateListing(address nftAddress, uint256 tokenId, uint256 newPrice) external nonReentrant {
        if (newPrice == 0) revert NFTMarketplace__PriceMustBeAboveZero();
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price == 0) revert NFTMarketplace__NotListed(nftAddress, tokenId);
        if (listing.seller != msg.sender) revert NFTMarketplace__NotOwner();

        uint256 oldPrice = listing.price;
        s_listings[nftAddress][tokenId].price = newPrice;

        emit ListingUpdated(msg.sender, nftAddress, tokenId, oldPrice, newPrice);
    }

    function buyItem(address nftAddress, uint256 tokenId) external payable nonReentrant {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price == 0) revert NFTMarketplace__NotListed(nftAddress, tokenId);
        if (msg.value < listing.price) revert NFTMarketplace__PriceNotMet(nftAddress, tokenId, listing.price);

        uint256 fee = (listing.price * s_marketplaceFeeBps) / 10000;
        uint256 proceeds = listing.price - fee;

        delete s_listings[nftAddress][tokenId];
        s_currentListings--;
        s_totalSales++;
        s_totalVolume += listing.price;

        s_proceeds[listing.seller] += proceeds;
        s_proceeds[owner()] += fee;

        IERC721(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId);

        if (msg.value > listing.price) {
            (bool success,) = msg.sender.call{value: msg.value - listing.price}("");
            if (!success) revert NFTMarketplace__TransferFailed();
        }

        emit ItemBought(msg.sender, nftAddress, tokenId, listing.price, listing.seller);
    }

    function withdrawProceeds() external nonReentrant {
        uint256 amount = s_proceeds[msg.sender];
        if (amount == 0) revert NFTMarketplace__NoProceeds();
        s_proceeds[msg.sender] = 0;
        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert NFTMarketplace__TransferFailed();
        emit ProceedsWithdrawn(msg.sender, amount);
    }

    function updateMarketplaceFee(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert NFTMarketplace__InvalidFee();
        s_marketplaceFeeBps = newFeeBps;
    }

    // GETTERS
    function getListing(address nftAddress, uint256 tokenId) external view returns (Listing memory) {
        return s_listings[nftAddress][tokenId];
    }

    function isNFTListed(address nftAddress, uint256 tokenId) external view returns (bool) {
        return s_listings[nftAddress][tokenId].price != 0;
    }

    function getProceeds(address seller) external view returns (uint256) {
        return s_proceeds[seller];
    }

    function getMarketplaceFee() external view returns (uint256) {
        return s_marketplaceFeeBps;
    }

    function getTotalSales() external view returns (uint256) {
        return s_totalSales;
    }

    function getTotalVolume() external view returns (uint256) {
        return s_totalVolume;
    }

    function getCurrentListings() external view returns (uint256) {
        return s_currentListings;
    }

    // ERC721 RECEIVER
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {
        emit EthReceived(msg.sender, msg.value);
    }

    fallback() external payable {
        emit EthReceived(msg.sender, msg.value);
    }
}
