// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title NFTMarketplace
 * @author SALAMI SELIM
 * @notice Allows users to mint, list, buy, and manage NFT sales with marketplace fees and creator royalties
 * @dev Uses ERC721URIStorage for minting, AccessControl for creator roles, and pull-over-push for payments
 */
contract NFTMarketplace is ERC721URIStorage, ReentrancyGuard, Ownable, ERC721Holder, AccessControl {
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
    error NFTMarketplace__OnlyCreatorCanMint();
    error NFTMarketplace__InvalidTokenURI();
    error NFTMarketplace__CreatorAlreadyExists();
    error NFTMarketplace__CreatorNotFound();
    error NFTMarketplace__InvalidRecipient();
    error NFTMarketplace__NFTNotHeldByContract();

    ////////////////////////////
    //////  EVENTS  ///////////
    ////////////////////////////
    event ItemListed(address indexed seller, address indexed nftAddress, uint256 indexed tokenId, uint256 price);
    event ItemCanceled(address indexed seller, address indexed nftAddress, uint256 indexed tokenId);
    event ItemBought(
        address indexed buyer, address indexed nftAddress, uint256 indexed tokenId, uint256 price, address seller
    );
    event ListingUpdated(
        address indexed seller, address indexed nftAddress, uint256 indexed tokenId, uint256 oldPrice, uint256 newPrice
    );
    event ProceedsWithdrawn(address indexed seller, uint256 amount);
    event EthReceived(address indexed sender, uint256 amount);
    event NFTMinted(address indexed creator, uint256 indexed tokenId, string tokenURI, address indexed to);
    event CreatorAdded(address indexed creator, address indexed addedBy);
    event CreatorRemoved(address indexed creator, address indexed removedBy);

    ///////////////////////////////
    /////  ROLES & CONSTANTS /////
    ///////////////////////////////
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant MAX_FEE = 1000; // 10% maximum fee

    ///////////////////////////////
    /////  STATE VARIABLES //////
    /////////////////////////////
    struct Listing {
        uint256 price;
        address seller;
        uint256 timestamp;
    }

    struct NFTInfo {
        address creator;
        uint256 mintTimestamp;
        bool isMarketplaceNFT;
    }

    // NFT Contract address -> NFT TokenID -> Listing
    mapping(address => mapping(uint256 => Listing)) private s_listings;

    // Seller address -> Amount earned
    mapping(address => uint256) private s_proceeds;

    // Token ID -> NFT Info (for marketplace-minted NFTs)
    mapping(uint256 => NFTInfo) private s_nftInfo;

    // Creator address -> Token IDs (for efficient NFT lookup)
    mapping(address => uint256[]) private s_creatorToTokenIds;

    // Creator address -> Index in s_creatorList (for efficient removal)
    mapping(address => uint256) private s_creatorIndex;

    // List of creators
    address[] private s_creatorList;

    // Marketplace fee percentage
    uint256 private s_marketplaceFee;

    // Statistics
    uint256 private s_currentListings;
    uint256 private s_totalSales;
    uint256 private s_totalVolume;
    uint256 private s_totalMinted;

    // Token counter for minted NFTs
    uint256 private s_tokenCounter;

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

    modifier onlyCreator() {
        if (!hasRole(CREATOR_ROLE, msg.sender)) {
            revert NFTMarketplace__OnlyCreatorCanMint();
        }
        _;
    }

    modifier validRecipient(address to) {
        if (to == address(0)) {
            revert NFTMarketplace__InvalidRecipient();
        }
        _;
    }

    ///////////////////////////////
    /////// CONSTRUCTOR //////////
    /////////////////////////////

    constructor(uint256 marketplaceFee, string memory name, string memory symbol)
        ERC721(name, symbol)
        validFee(marketplaceFee)
        Ownable(msg.sender)
    {
        s_marketplaceFee = marketplaceFee;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CREATOR_ROLE, msg.sender);
        s_creatorList.push(msg.sender);
        s_creatorIndex[msg.sender] = s_creatorList.length - 1;
        s_tokenCounter = 1;
    }

    //////////////////////////////////////
    ///////  CREATOR FUNCTIONS  /////////
    ////////////////////////////////////

    /**
     * @notice Add a new creator (only owner)
     * @param creator Address to grant creator role
     */
    function addCreator(address creator) external onlyOwner validRecipient(creator) {
        if (hasRole(CREATOR_ROLE, creator)) {
            revert NFTMarketplace__CreatorAlreadyExists();
        }
        _grantRole(CREATOR_ROLE, creator);
        s_creatorList.push(creator);
        s_creatorIndex[creator] = s_creatorList.length - 1;
        emit CreatorAdded(creator, msg.sender);
    }

    /**
     * @notice Remove a creator (only owner)
     * @param creator Address to revoke creator role
     */
    function removeCreator(address creator) external onlyOwner {
        if (!hasRole(CREATOR_ROLE, creator)) {
            revert NFTMarketplace__CreatorNotFound();
        }
        _revokeRole(CREATOR_ROLE, creator);
        uint256 index = s_creatorIndex[creator];
        if (index < s_creatorList.length) {
            s_creatorList[index] = s_creatorList[s_creatorList.length - 1];
            s_creatorIndex[s_creatorList[index]] = index;
            s_creatorList.pop();
        }
        delete s_creatorIndex[creator];
        emit CreatorRemoved(creator, msg.sender);
    }

    /**
     * @notice Mint NFT to a specific address (only creators)
     * @param to Address to mint NFT to
     * @param tokenURI Metadata URI for the NFT
     * @return tokenId The ID of the minted token
     */
    function mintNFT(address to, string memory tokenURI) public onlyCreator validRecipient(to) returns (uint256) {
        if (bytes(tokenURI).length == 0) {
            revert NFTMarketplace__InvalidTokenURI();
        }
        uint256 tokenId = s_tokenCounter++;
        s_totalMinted++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
        s_nftInfo[tokenId] = NFTInfo({creator: msg.sender, mintTimestamp: block.timestamp, isMarketplaceNFT: true});
        s_creatorToTokenIds[msg.sender].push(tokenId);
        emit NFTMinted(msg.sender, tokenId, tokenURI, to);
        return tokenId;
    }

    /**
     * @notice Mint NFT to creator's own address
     * @param tokenURI Metadata URI for the NFT
     * @return tokenId The ID of the minted token
     */
    function mintNFTToSelf(string memory tokenURI) external onlyCreator returns (uint256) {
        return mintNFT(msg.sender, tokenURI);
    }

    /**
     * @notice Batch mint NFTs to multiple addresses (only creators)
     * @param recipients Array of addresses to mint NFTs to
     * @param tokenURIs Array of metadata URIs for the NFTs
     */
    function batchMintNFTs(address[] memory recipients, string[] memory tokenURIs) external onlyCreator nonReentrant {
        require(recipients.length == tokenURIs.length, "Arrays length mismatch");
        require(recipients.length > 0, "Empty arrays");
        for (uint256 i = 0; i < recipients.length; i++) {
            mintNFT(recipients[i], tokenURIs[i]);
        }
    }

    //////////////////////////////////////
    ///////////  MAIN FUNCTIONS  ////////
    /////////////////////////////////////

    /**
     * @notice List NFT on the marketplace (creators and users)
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     * @param price Sale price in wei
     */
    function listItem(address nftAddress, uint256 tokenId, uint256 price)
        external
        notListed(nftAddress, tokenId)
        isOwner(nftAddress, tokenId, msg.sender)
        nonReentrant
    {
        if (price <= 0) {
            revert NFTMarketplace__PriceMustBeAboveZero();
        }
        IERC721 nft = IERC721(nftAddress);
        address approvedAddress = nft.getApproved(tokenId);
        bool isApprovedForAll = nft.isApprovedForAll(msg.sender, address(this));
        if (approvedAddress != address(this) && !isApprovedForAll) {
            revert NFTMarketplace__NotApprovedForMarketplace();
        }
        nft.safeTransferFrom(msg.sender, address(this), tokenId);
        s_listings[nftAddress][tokenId] = Listing(price, msg.sender, block.timestamp);
        s_currentListings++;
        emit ItemListed(msg.sender, nftAddress, tokenId, price);
    }

    /**
     * @notice Buy an NFT
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     */
    function buyItem(address nftAddress, uint256 tokenId) external payable isListed(nftAddress, tokenId) nonReentrant {
        Listing storage listing = s_listings[nftAddress][tokenId];
        if (msg.value < listing.price) {
            revert NFTMarketplace__PriceNotMet(nftAddress, tokenId, listing.price);
        }
        // Refund overpayment first
        if (msg.value > listing.price) {
            (bool success,) = payable(msg.sender).call{value: msg.value - listing.price}("");
            require(success, "Refund failed");
        }
        uint256 fee = (listing.price * s_marketplaceFee) / BASIS_POINTS;
        uint256 sellerProceeds = listing.price - fee;
        uint256 creatorRoyalty = 0;
        if (nftAddress == address(this) && s_nftInfo[tokenId].isMarketplaceNFT) {
            address creator = s_nftInfo[tokenId].creator;
            if (creator != address(0) && creator != listing.seller) {
                creatorRoyalty = (listing.price * 250) / BASIS_POINTS; // 2.5% royalty
                s_proceeds[creator] += creatorRoyalty;
                sellerProceeds -= creatorRoyalty;
            }
        }
        s_proceeds[listing.seller] += sellerProceeds;
        s_proceeds[owner()] += fee;
        s_totalSales++;
        s_totalVolume += listing.price;
        s_currentListings--;
        IERC721(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId);
        emit ItemBought(msg.sender, nftAddress, tokenId, listing.price, listing.seller);
        delete s_listings[nftAddress][tokenId];
    }
    /**
     * @notice Cancel a listing
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     */

    function cancelListing(address nftAddress, uint256 tokenId) external isListed(nftAddress, tokenId) nonReentrant {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (msg.sender != listing.seller && msg.sender != owner()) {
            revert NFTMarketplace__NotOwner();
        }
        IERC721(nftAddress).safeTransferFrom(address(this), listing.seller, tokenId);
        delete s_listings[nftAddress][tokenId];
        s_currentListings--;
        emit ItemCanceled(listing.seller, nftAddress, tokenId);
    }

    /**
     * @notice Update listing price
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     * @param newPrice New price in wei
     */
    function updateListing(address nftAddress, uint256 tokenId, uint256 newPrice)
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
        uint256 oldPrice = listing.price;
        listing.price = newPrice;
        listing.timestamp = block.timestamp;
        emit ListingUpdated(msg.sender, nftAddress, tokenId, oldPrice, newPrice);
    }

    /**
     * @notice Withdraw proceeds from sales
     */
    function withdrawProceeds() external nonReentrant {
        uint256 proceeds = s_proceeds[msg.sender];
        if (proceeds <= 0) {
            revert NFTMarketplace__NoProceeds();
        }
        s_proceeds[msg.sender] = 0;
        (bool success,) = payable(msg.sender).call{value: proceeds}("");
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
     */
    function emergencyWithdrawNFT(address nftAddress, uint256 tokenId, address to)
        external
        onlyOwner
        validRecipient(to)
    {
        IERC721 nft = IERC721(nftAddress);
        if (nft.ownerOf(tokenId) != address(this)) {
            revert NFTMarketplace__NFTNotHeldByContract();
        }
        nft.safeTransferFrom(address(this), to, tokenId);
    }

    ////////////////////////////////////////
    ///////    GETTER FUNCTIONS   ///////
    //////////////////////////////////////

    function getListing(address nftAddress, uint256 tokenId) external view returns (Listing memory) {
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

    function getTotalMinted() external view returns (uint256) {
        return s_totalMinted;
    }

    function getTokenCounter() external view returns (uint256) {
        return s_tokenCounter;
    }

    function isNFTListed(address nftAddress, uint256 tokenId) external view returns (bool) {
        return s_listings[nftAddress][tokenId].seller != address(0);
    }

    function getNFTInfo(uint256 tokenId) external view returns (NFTInfo memory) {
        return s_nftInfo[tokenId];
    }

    function isCreator(address account) external view returns (bool) {
        return hasRole(CREATOR_ROLE, account);
    }

    function getAllCreators() external view returns (address[] memory) {
        return s_creatorList;
    }

    function getCreatorCount() external view returns (uint256) {
        return s_creatorList.length;
    }

    /**
     * @notice Get NFTs created by a specific creator
     * @param creator Creator address
     * @param offset Starting index for pagination
     * @param limit Maximum number of results to return
     */
    function getNFTsByCreator(address creator, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory tokenIds, uint256 total)
    {
        total = s_creatorToTokenIds[creator].length;
        if (offset >= total || limit == 0) {
            return (new uint256[](0), total);
        }
        uint256 length = (offset + limit > total) ? total - offset : limit;
        tokenIds = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            tokenIds[i] = s_creatorToTokenIds[creator][offset + i];
        }
    }

    /////////////////////////////////////
    ///////   RECEIVE FUNCTION  ////////
    ////////////////////////////////////

    receive() external payable {
        emit EthReceived(msg.sender, msg.value);
    }

    ////////////////////////////////////////
    ///////    OVERRIDE FUNCTIONS   ///////
    ////////////////////////////////////////

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
