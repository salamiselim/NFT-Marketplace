// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

/**
 * @title NFTMarketplace
 * @author SALAMI SELIM
 * @notice This contract allows users to list, buy, and manage NFT sales with marketplace fees
 * @dev Uses pull-over-push payment pattern for security and ERC721Holder for safe transfers
 */
contract NFTMarketplace is ReentrancyGuard, Ownable, ERC721Holder {
    //////////////////////////////
    //////////  ERRORS  /////////
    /////////////////////////////
    error NFTMarketplace__PriceMustBeAboveZero();
    error NFTMarketplace__NotApprovedForMarketplace();
    error NFTMarketplace__AlreadyListed(address nftAddress, uint256 tokenId);
    error NFTMarketplace__NotOwner();
    error NFTMarketplace__NotListed(address nftAddress, uint256 tokenId);
    error NFTMarketplace__PriceNotMet(address nftAddress, uint256 tokenId, uint256 price);
    error NFTMarketplace__NoProceeds();
    error NFTMarketplace__TransferFailed();
    error NFTMarketplace__InvalidFee();
    error NFTMarketplace__AuctionNotEnded();
    error NFTMarketplace__AuctionEnded();

    ////////////////////////////
    //////  EVENTS  ///////////
    ////////////////////////////
    event ItemListed(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );

    event ItemCanceled(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId
    );

    event ItemBought(
        address indexed buyer,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price,
        address seller
    );

    event ListingUpdated(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 newPrice
    );

    event ProceedsWithdrawn(
        address indexed seller,
        uint256 amount
    );

    event EthReceived(
        address indexed sender,
        uint256 amount
    );

    ///////////////////////////////
    /////  STATE VARIABLES //////
    /////////////////////////////
    struct Listing {
        uint256 price;
        address seller;
        uint256 timestamp;
    }

    // NFT Contract address -> NFT TokenID -> Listing
    mapping(address => mapping(uint256 => Listing)) private s_listings;
    
    // Seller address -> Amount earned
    mapping(address => uint256) private s_proceeds;

    // Marketplace fee percentage 
    uint256 private s_marketplaceFee;
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant MAX_FEE = 1000; // 10% maximum fee

    // Statistics (tracks active listings)
    uint256 private s_currentListings;
    uint256 private s_totalSales;
    uint256 private s_totalVolume;

    ///////////////////////////////////
    ///////   MODIFIERS  ///////////
    ////////////////////////////////
    modifier notListed(address nftAddress, uint256 tokenId) {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price > 0 && listing.seller != address(0)) {
            revert NFTMarketplace__AlreadyListed(nftAddress, tokenId);
        }
        _;
    }

    modifier isListed(address nftAddress, uint256 tokenId) {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price <= 0 || listing.seller == address(0)) {
            revert NFTMarketplace__NotListed(nftAddress, tokenId);
        }
        _;
    }

    modifier isOwner(address nftAddress, uint256 tokenId, address spender) {
        IERC721 nft = IERC721(nftAddress);
        address owner = nft.ownerOf(tokenId);
        if (spender != owner) {
            revert NFTMarketplace__NotOwner();
        }
        _;
    }

    modifier validFee(uint256 fee) {
        if (fee > MAX_FEE) {
            revert NFTMarketplace__InvalidFee();
        }
        _;
    }

    ///////////////////////////////
    /////// CONSTRUCTOR //////////
    /////////////////////////////
    
    constructor(uint256 marketplaceFee) validFee(marketplaceFee) Ownable(msg.sender) {
        s_marketplaceFee = marketplaceFee;
    }

    //////////////////////////////////////
    ///////////  MAIN FUNCTIONS  ////////
    /////////////////////////////////////

    /**
     * @notice Method for listing NFT on the marketplace
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     * @param price Sale price for the listed NFT (in wei)
     * @dev Uses pull-over-push pattern for security
     */
    function listItem(
        address nftAddress,
        uint256 tokenId,
        uint256 price
    )
        external
        notListed(nftAddress, tokenId)
        isOwner(nftAddress, tokenId, msg.sender)
        nonReentrant
    {
        if (price <= 0) {
            revert NFTMarketplace__PriceMustBeAboveZero();
        }

        IERC721 nft = IERC721(nftAddress);
        
        // Check if marketplace is approved for this token or for all tokens
        address approvedAddress = nft.getApproved(tokenId);
        bool isApprovedForAll = nft.isApprovedForAll(msg.sender, address(this));
        
        if (approvedAddress != address(this) && !isApprovedForAll) {
            revert NFTMarketplace__NotApprovedForMarketplace();
        }

        // Transfer NFT to marketplace for security
        nft.safeTransferFrom(msg.sender, address(this), tokenId);

        s_listings[nftAddress][tokenId] = Listing(price, msg.sender, block.timestamp);
        s_currentListings++;
        
        emit ItemListed(msg.sender, nftAddress, tokenId, price);
    }

    /**
     * @notice Method for buying an NFT
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     */
    function buyItem(
        address nftAddress,
        uint256 tokenId
    ) external payable isListed(nftAddress, tokenId) nonReentrant {
        Listing memory listedItem = s_listings[nftAddress][tokenId];
        
        if (msg.value < listedItem.price) {
            revert NFTMarketplace__PriceNotMet(nftAddress, tokenId, listedItem.price);
        }

        // Calculate fees and proceeds
        uint256 fee = (listedItem.price * s_marketplaceFee) / BASIS_POINTS;
        uint256 sellerProceeds = listedItem.price - fee;

        // Update proceeds
        s_proceeds[listedItem.seller] += sellerProceeds;
        s_proceeds[owner()] += fee;

        // Update statistics
        s_totalSales++;
        s_totalVolume += listedItem.price;
        s_currentListings--;

        // Clear listing
        delete s_listings[nftAddress][tokenId];

        // Transfer NFT to buyer (from marketplace)
        IERC721(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId);

        // Refund excess ETH if overpaid
        if (msg.value > listedItem.price) {
            uint256 refundAmount = msg.value - listedItem.price;
            (bool refundSuccess, ) = payable(msg.sender).call{value: refundAmount}("");
            require(refundSuccess, "Refund failed");
        }
        
        emit ItemBought(msg.sender, nftAddress, tokenId, listedItem.price, listedItem.seller);
    }

    /**
     * @notice Method for cancelling a listing
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     */
    function cancelListing(
        address nftAddress,
        uint256 tokenId
    )
        external
        isListed(nftAddress, tokenId)
        nonReentrant
    {
        Listing memory listing = s_listings[nftAddress][tokenId];
        
        // Only seller or owner can cancel
        if (msg.sender != listing.seller && msg.sender != owner()) {
            revert NFTMarketplace__NotOwner();
        }

        // Return NFT from Marketplace to seller
        IERC721(nftAddress).safeTransferFrom(address(this), listing.seller, tokenId);
        
        delete s_listings[nftAddress][tokenId];
        s_currentListings--;
        emit ItemCanceled(listing.seller, nftAddress, tokenId);
    }

    /**
     * @notice Method for updating listing price
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     * @param newPrice New price in Wei
     */
    function updateListing(
        address nftAddress,
        uint256 tokenId,
        uint256 newPrice
    )
        external
        isListed(nftAddress, tokenId)
        nonReentrant
    {
        Listing storage listing = s_listings[nftAddress][tokenId];
        
        if (msg.sender != listing.seller) {
            revert NFTMarketplace__NotOwner();
        }
        
        if (newPrice <= 0) {
            revert NFTMarketplace__PriceMustBeAboveZero();
        }

        listing.price = newPrice;
        listing.timestamp = block.timestamp;
        
        emit ListingUpdated(msg.sender, nftAddress, tokenId, newPrice);
    }

    /**
     * @notice Method for withdrawing proceeds from sales
     */
    function withdrawProceeds() external nonReentrant {
        uint256 proceeds = s_proceeds[msg.sender];
        if (proceeds <= 0) {
            revert NFTMarketplace__NoProceeds();
        }

        s_proceeds[msg.sender] = 0;
        
        (bool success, ) = payable(msg.sender).call{value: proceeds}("");
        if (!success) {
            revert NFTMarketplace__TransferFailed();
        }

        emit ProceedsWithdrawn(msg.sender, proceeds);
    }

    //////////////////////////////////////
    ///////    OWNER FUNCTIONS /////////
    ////////////////////////////////////

    /**
     * @notice Update marketplace fee (only owner)
     * @param newFee New fee in basis points (e.g., 250 = 2.5%)
     */
    function updateMarketplaceFee(uint256 newFee) external onlyOwner validFee(newFee) {
        s_marketplaceFee = newFee;
    }

    /**
     * @notice Emergency withdrawal for stuck NFTs (only owner)
     * @dev Should only be used in emergency situations
     */
    function emergencyWithdrawNFT(
        address nftAddress,
        uint256 tokenId,
        address to
    ) external onlyOwner {
        IERC721 nft = IERC721(nftAddress);
        nft.safeTransferFrom(address(this), to, tokenId);
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

    function getProceeds(address seller) external view returns (uint256) {
        return s_proceeds[seller];
    }

    function getMarketplaceFee() external view returns (uint256) {
        return s_marketplaceFee;
    }

    function getCurrentListings() external view returns (uint256) {
        return s_currentListings;
    }

    function getTotalSales() external view returns (uint256) {
        return s_totalSales;
    }

    function getTotalVolume() external view returns (uint256) {
        return s_totalVolume;
    }

    function isNFTListed(address nftAddress, uint256 tokenId) external view returns (bool) {
        return s_listings[nftAddress][tokenId].seller != address(0);
    }

    /////////////////////////////////////
    ///////   RECEIVE FUNCTION  ////////
    ////////////////////////////////////
    
    /**
     * @notice Allows contract to receive ETH and logs the event
     * @dev Emits EthReceived event for transparency; useful for accidental transfers or future extensions
     */
    receive() external payable {
        emit EthReceived(msg.sender, msg.value);
    }
}