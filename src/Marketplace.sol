// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title NFTMarketplace
 * @author SALAMI SELIM  
 * @notice ERC1155 Marketplace for listing and buying NFTs
 * @dev Supports both single NFTs and editions (multiple copies)
 */
contract NFTMarketplace is Ownable, ReentrancyGuard, IERC1155Receiver {
    //////////////////////////////
    //////////  ERRORS  /////////
    /////////////////////////////
    error NFTMarketplace__PriceMustBeAboveZero();
    error NFTMarketplace__NotListed(address nftAddress, uint256 tokenId);
    error NFTMarketplace__PriceNotMet(address nftAddress, uint256 tokenId, uint256 price);
    error NFTMarketplace__NotOwner();
    error NFTMarketplace__AlreadyListed(address nftAddress, uint256 tokenId);
    error NFTMarketplace__NoProceeds();
    error NFTMarketplace__TransferFailed();
    error NFTMarketplace__InvalidNFTAddress();
    error NFTMarketplace__NotERC1155();
    error NFTMarketplace__InvalidFee();
    error NFTMarketplace__NotApprovedForMarketplace();
    error NFTMarketplace__InvalidAmount();
    error NFTMarketplace__InsufficientBalance();

    ////////////////////////////
    //////  EVENTS  ///////////
    ////////////////////////////
    event ItemListed(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 pricePerItem
    );

    event ItemBought(
        address indexed buyer,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 totalPrice,
        address seller
    );

    event ItemCanceled(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 amount
    );

    event ListingUpdated(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 oldPrice,
        uint256 newPrice
    );

    event ProceedsWithdrawn(address indexed seller, uint256 amount);
    event EthReceived(address indexed sender, uint256 amount);

    ///////////////////////////////
    /////  STATE VARIABLES //////
    ///////////////////////////////
    
    struct Listing {
        uint256 pricePerItem;  // Price for ONE item
        uint256 amount;        // Amount available
        address seller;
    }

    uint256 private constant MAX_FEE_BPS = 1000; // 10% max fee
    uint256 private s_marketplaceFeeBps;
    uint256 private s_totalSales;
    uint256 private s_totalVolume;
    uint256 private s_currentListings;

    // NFT Address -> Token ID -> Listing
    mapping(address => mapping(uint256 => Listing)) private s_listings;
    
    // Seller -> Proceeds
    mapping(address => uint256) private s_proceeds;

    ///////////////////////////////
    /////// CONSTRUCTOR //////////
    /////////////////////////////
    
    constructor(uint256 marketplaceFeeBps) Ownable(msg.sender) {
        if (marketplaceFeeBps > MAX_FEE_BPS) {
            revert NFTMarketplace__InvalidFee();
        }
        s_marketplaceFeeBps = marketplaceFeeBps;
    }

    //////////////////////////////////////
    ///////  LISTING FUNCTIONS  /////////
    ////////////////////////////////////

    /**
     * @notice List ERC1155 tokens for sale
     * @param nftAddress Address of the ERC1155 contract
     * @param tokenId Token ID to list
     * @param amount Amount of tokens to list
     * @param pricePerItem Price per single token
     */
    function listItem(
        address nftAddress,
        uint256 tokenId,
        uint256 amount,
        uint256 pricePerItem
    ) external nonReentrant {
        if (pricePerItem == 0) {
            revert NFTMarketplace__PriceMustBeAboveZero();
        }
        if (amount == 0) {
            revert NFTMarketplace__InvalidAmount();
        }
        if (nftAddress == address(0)) {
            revert NFTMarketplace__InvalidNFTAddress();
        }

        // Check if it's ERC1155
        if (!IERC165(nftAddress).supportsInterface(type(IERC1155).interfaceId)) {
            revert NFTMarketplace__NotERC1155();
        }

        IERC1155 nft = IERC1155(nftAddress);

        // Check seller has enough balance
        if (nft.balanceOf(msg.sender, tokenId) < amount) {
            revert NFTMarketplace__InsufficientBalance();
        }

        // Check if marketplace is approved
        if (!nft.isApprovedForAll(msg.sender, address(this))) {
            revert NFTMarketplace__NotApprovedForMarketplace();
        }

        // Check if already listed
        if (s_listings[nftAddress][tokenId].amount > 0) {
            revert NFTMarketplace__AlreadyListed(nftAddress, tokenId);
        }

        // Transfer tokens to marketplace
        nft.safeTransferFrom(msg.sender, address(this), tokenId, amount, "");

        s_listings[nftAddress][tokenId] = Listing({
            pricePerItem: pricePerItem,
            amount: amount,
            seller: msg.sender
        });

        s_currentListings++;

        emit ItemListed(msg.sender, nftAddress, tokenId, amount, pricePerItem);
    }

    /**
     * @notice Cancel a listing
     */
    function cancelListing(
        address nftAddress,
        uint256 tokenId
    ) external nonReentrant {
        Listing memory listing = s_listings[nftAddress][tokenId];
        
        if (listing.amount == 0) {
            revert NFTMarketplace__NotListed(nftAddress, tokenId);
        }
        if (listing.seller != msg.sender) {
            revert NFTMarketplace__NotOwner();
        }

        uint256 amount = listing.amount;
        
        delete s_listings[nftAddress][tokenId];
        s_currentListings--;

        // Return tokens to seller
        IERC1155(nftAddress).safeTransferFrom(
            address(this),
            msg.sender,
            tokenId,
            amount,
            ""
        );

        emit ItemCanceled(msg.sender, nftAddress, tokenId, amount);
    }

    /**
     * @notice Update listing price
     */
    function updateListing(
        address nftAddress,
        uint256 tokenId,
        uint256 newPricePerItem
    ) external nonReentrant {
        if (newPricePerItem == 0) {
            revert NFTMarketplace__PriceMustBeAboveZero();
        }

        Listing memory listing = s_listings[nftAddress][tokenId];
        
        if (listing.amount == 0) {
            revert NFTMarketplace__NotListed(nftAddress, tokenId);
        }
        if (listing.seller != msg.sender) {
            revert NFTMarketplace__NotOwner();
        }

        uint256 oldPrice = listing.pricePerItem;
        s_listings[nftAddress][tokenId].pricePerItem = newPricePerItem;

        emit ListingUpdated(msg.sender, nftAddress, tokenId, oldPrice, newPricePerItem);
    }

    //////////////////////////////////////
    ///////  BUYING FUNCTIONS  //////////
    ////////////////////////////////////

    /**
     * @notice Buy tokens from a listing
     * @param nftAddress Address of the ERC1155 contract
     * @param tokenId Token ID to buy
     * @param amount Amount of tokens to buy (must be <= listed amount)
     */
    function buyItem(
        address nftAddress,
        uint256 tokenId,
        uint256 amount
    ) external payable nonReentrant {
        if (amount == 0) {
            revert NFTMarketplace__InvalidAmount();
        }

        Listing memory listing = s_listings[nftAddress][tokenId];
        
        if (listing.amount == 0) {
            revert NFTMarketplace__NotListed(nftAddress, tokenId);
        }
        if (amount > listing.amount) {
            revert NFTMarketplace__InvalidAmount();
        }

        uint256 totalPrice = listing.pricePerItem * amount;
        
        if (msg.value < totalPrice) {
            revert NFTMarketplace__PriceNotMet(nftAddress, tokenId, totalPrice);
        }

        // Calculate fees
        uint256 fee = (totalPrice * s_marketplaceFeeBps) / 10000;
        uint256 proceeds = totalPrice - fee;

        // Update listing
        s_listings[nftAddress][tokenId].amount -= amount;
        
        // If all bought, remove listing
        if (s_listings[nftAddress][tokenId].amount == 0) {
            delete s_listings[nftAddress][tokenId];
            s_currentListings--;
        }

        // Update stats
        s_totalSales++;
        s_totalVolume += totalPrice;

        // Update proceeds
        s_proceeds[listing.seller] += proceeds;
        s_proceeds[owner()] += fee;

        // Transfer tokens to buyer
        IERC1155(nftAddress).safeTransferFrom(
            address(this),
            msg.sender,
            tokenId,
            amount,
            ""
        );

        // Refund excess payment
        if (msg.value > totalPrice) {
            (bool success, ) = msg.sender.call{value: msg.value - totalPrice}("");
            if (!success) {
                revert NFTMarketplace__TransferFailed();
            }
        }

        emit ItemBought(msg.sender, nftAddress, tokenId, amount, totalPrice, listing.seller);
    }

    /**
     * @notice Withdraw accumulated proceeds
     */
    function withdrawProceeds() external nonReentrant {
        uint256 amount = s_proceeds[msg.sender];
        
        if (amount == 0) {
            revert NFTMarketplace__NoProceeds();
        }

        s_proceeds[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) {
            revert NFTMarketplace__TransferFailed();
        }

        emit ProceedsWithdrawn(msg.sender, amount);
    }

    //////////////////////////////////////
    ///////    OWNER FUNCTIONS /////////
    ////////////////////////////////////

    /**
     * @notice Update marketplace fee (only owner)
     */
    function updateMarketplaceFee(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) {
            revert NFTMarketplace__InvalidFee();
        }
        s_marketplaceFeeBps = newFeeBps;
    }

    ////////////////////////////////////////
    ///////    GETTER FUNCTIONS   ///////
    //////////////////////////////////////

    function getListing(
        address nftAddress,
        uint256 tokenId
    ) external view returns (Listing memory) {
        return s_listings[nftAddress][tokenId];
    }

    function isNFTListed(
        address nftAddress,
        uint256 tokenId
    ) external view returns (bool) {
        return s_listings[nftAddress][tokenId].amount > 0;
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

    /**
     * @notice Calculate total price for buying amount of tokens
     */
    function calculateTotalPrice(
        address nftAddress,
        uint256 tokenId,
        uint256 amount
    ) external view returns (uint256 totalPrice, uint256 fee, uint256 proceeds) {
        Listing memory listing = s_listings[nftAddress][tokenId];
        require(listing.amount >= amount, "Not enough available");
        
        totalPrice = listing.pricePerItem * amount;
        fee = (totalPrice * s_marketplaceFeeBps) / 10000;
        proceeds = totalPrice - fee;
    }

    ////////////////////////////////////////
    ///////   ERC1155 RECEIVER   //////////
    ////////////////////////////////////////

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId ||
               interfaceId == type(IERC165).interfaceId;
    }

    ////////////////////////////////////////
    ///////   RECEIVE FUNCTIONS   /////////
    ////////////////////////////////////////

    receive() external payable {
        emit EthReceived(msg.sender, msg.value);
    }

    fallback() external payable {
        emit EthReceived(msg.sender, msg.value);
    }
}