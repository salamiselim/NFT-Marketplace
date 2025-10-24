// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title QuivaComic
 * @author SALAMI SELIM
 * @notice ERC1155 NFT Collection for comic creators with role-based minting
 * @dev Only addresses with CREATOR_ROLE can mint NFTs
 * @dev Supports both single NFTs (amount=1) and editions (amount>1)
 */
contract QuivaComic is ERC1155Supply, Ownable, AccessControl, ReentrancyGuard {
    using Strings for uint256;

    //////////////////////////////
    //////////  ERRORS  /////////
    //////////////////////////////
    error QuivaComic__OnlyCreatorCanMint();
    error QuivaComic__InvalidTokenURI();
    error QuivaComic__CreatorAlreadyExists();
    error QuivaComic__CreatorNotFound();
    error QuivaComic__ArrayLengthMismatch();
    error QuivaComic__EmptyArray();
    error QuivaComic__InvalidAmount();
    error QuivaComic__TokenDoesNotExist();

    ////////////////////////////
    //////  EVENTS  ///////////
    ////////////////////////////
    event NFTMinted(
        address indexed creator,
        address indexed to,
        uint256 indexed tokenId,
        uint256 amount,
        string tokenURI
    );

    event CreatorAdded(address indexed creator, address indexed addedBy);
    event CreatorRemoved(address indexed creator, address indexed removedBy);
    event BaseURIUpdated(string newBaseURI);

    ///////////////////////////////
    /////  ROLES & CONSTANTS /////
    ///////////////////////////////
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");

    ///////////////////////////////
    /////  STATE VARIABLES //////
    ///////////////////////////////
    
    struct TokenMetadata {
        address creator;
        uint256 mintTimestamp;
        string uri;
        uint256 maxSupply; // 0 = unlimited
    }

    // Collection info
    string public name = "Quiva Comic";
    string public symbol = "QUIVA";

    // Token ID -> Token Metadata
    mapping(uint256 => TokenMetadata) private s_tokenMetadata;

    // Creator address -> Array of token IDs they created
    mapping(address => uint256[]) private s_creatorTokens;

    // List of all creators (for enumeration)
    address[] private s_creatorList;

    // Token counter (for unique token IDs)
    uint256 private s_tokenCounter;

    // Base URI for all tokens
    string private s_baseURI;

    // Statistics
    uint256 private s_totalTokenTypes; // Number of unique token IDs created

    ///////////////////////////////////
    ///////   MODIFIERS  ///////////
    ////////////////////////////////
    
    modifier onlyCreator() {
        if (!hasRole(CREATOR_ROLE, msg.sender)) {
            revert QuivaComic__OnlyCreatorCanMint();
        }
        _;
    }

    modifier tokenExists(uint256 tokenId) {
        if (s_tokenMetadata[tokenId].creator == address(0)) {
            revert QuivaComic__TokenDoesNotExist();
        }
        _;
    }

    ///////////////////////////////
    /////// CONSTRUCTOR //////////
    /////////////////////////////
    
    constructor(string memory baseURI_) ERC1155("") Ownable(msg.sender) {
        s_baseURI = baseURI_;
        
        // Grant the deployer the default admin role and creator role
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CREATOR_ROLE, msg.sender);
        
        s_creatorList.push(msg.sender);
        
        // Start token counter at 1
        s_tokenCounter = 1;
    }

    //////////////////////////////////////
    ///////  CREATOR MANAGEMENT  ////////
    ////////////////////////////////////

    /**
     * @notice Add a new creator (only owner)
     */
    function addCreator(address creator) external onlyOwner {
        if (hasRole(CREATOR_ROLE, creator)) {
            revert QuivaComic__CreatorAlreadyExists();
        }
        
        _grantRole(CREATOR_ROLE, creator);
        s_creatorList.push(creator);
        
        emit CreatorAdded(creator, msg.sender);
    }

    /**
     * @notice Add multiple creators at once (only owner)
     */
    function addCreators(address[] memory creators) external onlyOwner {
        if (creators.length == 0) {
            revert QuivaComic__EmptyArray();
        }

        for (uint256 i = 0; i < creators.length; i++) {
            if (!hasRole(CREATOR_ROLE, creators[i])) {
                _grantRole(CREATOR_ROLE, creators[i]);
                s_creatorList.push(creators[i]);
                
                emit CreatorAdded(creators[i], msg.sender);
            }
        }
    }

    /**
     * @notice Remove a creator (only owner)
     */
    function removeCreator(address creator) external onlyOwner {
        if (!hasRole(CREATOR_ROLE, creator)) {
            revert QuivaComic__CreatorNotFound();
        }
        
        _revokeRole(CREATOR_ROLE, creator);
        
        // Remove from creator list
        for (uint256 i = 0; i < s_creatorList.length; i++) {
            if (s_creatorList[i] == creator) {
                s_creatorList[i] = s_creatorList[s_creatorList.length - 1];
                s_creatorList.pop();
                break;
            }
        }
        
        emit CreatorRemoved(creator, msg.sender);
    }

    //////////////////////////////////////
    ///////  MINTING FUNCTIONS  /////////
    ////////////////////////////////////

    /**
     * @notice Mint new token type (only creators)
     * @param to Address to mint to
     * @param amount Amount to mint (1 for unique NFT, >1 for editions)
     * @param tokenURI_ Metadata URI for this token
     * @param maxSupply Maximum supply (0 for unlimited)
     * @return tokenId The ID of the minted token
     */
    function mintNFT(
        address to,
        uint256 amount,
        string memory tokenURI_,
        uint256 maxSupply
    ) public onlyCreator nonReentrant returns (uint256) {
        if (bytes(tokenURI_).length == 0) {
            revert QuivaComic__InvalidTokenURI();
        }
        if (amount == 0) {
            revert QuivaComic__InvalidAmount();
        }

        uint256 tokenId = s_tokenCounter;
        s_tokenCounter++;
        s_totalTokenTypes++;

        // Mint the tokens
        _mint(to, tokenId, amount, "");

        // Store metadata
        s_tokenMetadata[tokenId] = TokenMetadata({
            creator: msg.sender,
            mintTimestamp: block.timestamp,
            uri: tokenURI_,
            maxSupply: maxSupply
        });

        // Track creator's tokens
        s_creatorTokens[msg.sender].push(tokenId);

        emit NFTMinted(msg.sender, to, tokenId, amount, tokenURI_);
        return tokenId;
    }

    /**
     * @notice Mint single unique NFT to self (convenience function)
     */
    function mintNFTToSelf(string memory tokenURI_) external onlyCreator returns (uint256) {
        return mintNFT(msg.sender, 1, tokenURI_, 1); // Single unique NFT
    }

    /**
     * @notice Mint more of an existing token type (only original creator)
     */
    function mintMore(
        uint256 tokenId,
        address to,
        uint256 amount
    ) external onlyCreator nonReentrant tokenExists(tokenId) {
        TokenMetadata memory metadata = s_tokenMetadata[tokenId];
        
        // Only original creator can mint more
        require(metadata.creator == msg.sender, "Not token creator");
        
        // Check max supply
        if (metadata.maxSupply > 0) {
            require(
                totalSupply(tokenId) + amount <= metadata.maxSupply,
                "Exceeds max supply"
            );
        }

        _mint(to, tokenId, amount, "");
        
        emit NFTMinted(msg.sender, to, tokenId, amount, metadata.uri);
    }

    /**
     * @notice Batch mint multiple token types
     */
    function batchMintNFTs(
        address[] memory recipients,
        uint256[] memory amounts,
        string[] memory tokenURIs,
        uint256[] memory maxSupplies
    ) external onlyCreator returns (uint256[] memory tokenIds) {
        if (
            recipients.length != amounts.length ||
            recipients.length != tokenURIs.length ||
            recipients.length != maxSupplies.length
        ) {
            revert QuivaComic__ArrayLengthMismatch();
        }
        if (recipients.length == 0) {
            revert QuivaComic__EmptyArray();
        }

        tokenIds = new uint256[](recipients.length);

        for (uint256 i = 0; i < recipients.length; i++) {
            tokenIds[i] = mintNFT(recipients[i], amounts[i], tokenURIs[i], maxSupplies[i]);
        }

        return tokenIds;
    }

    /**
     * @notice Mint multiple copies of same token type to single address
     */
    function mintEdition(
        address to,
        uint256 amount,
        string memory tokenURI_,
        uint256 maxSupply
    ) external onlyCreator returns (uint256) {
        return mintNFT(to, amount, tokenURI_, maxSupply);
    }

    //////////////////////////////////////
    ///////    OWNER FUNCTIONS /////////
    ////////////////////////////////////

    /**
     * @notice Update the base URI (only owner)
     */
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        s_baseURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    ////////////////////////////////////////
    ///////    GETTER FUNCTIONS   ///////
    //////////////////////////////////////

    function getTokenCounter() external view returns (uint256) {
        return s_tokenCounter;
    }

    function getTotalTokenTypes() external view returns (uint256) {
        return s_totalTokenTypes;
    }

    function getBaseURI() external view returns (string memory) {
        return s_baseURI;
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

    function getTokenMetadata(uint256 tokenId) 
        external 
        view 
        tokenExists(tokenId) 
        returns (TokenMetadata memory) 
    {
        return s_tokenMetadata[tokenId];
    }

    function getCreatorOf(uint256 tokenId) 
        external 
        view 
        tokenExists(tokenId) 
        returns (address) 
    {
        return s_tokenMetadata[tokenId].creator;
    }

    function getTokensByCreator(address creator) external view returns (uint256[] memory) {
        return s_creatorTokens[creator];
    }

    function getTokensByCreatorPaginated(
        address creator,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory tokens, uint256 total) {
        uint256[] memory allTokens = s_creatorTokens[creator];
        total = allTokens.length;

        if (offset >= total || limit == 0) {
            return (new uint256[](0), total);
        }

        uint256 length = (offset + limit > total) ? total - offset : limit;
        tokens = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            tokens[i] = allTokens[offset + i];
        }
    }

    /**
     * @notice Get all token IDs owned by an address with their balances
     */
    function getTokensByOwner(address owner) 
        external 
        view 
        returns (uint256[] memory tokenIds, uint256[] memory balances) 
    {
        // Count how many different tokens the owner has
        uint256 count = 0;
        for (uint256 i = 1; i < s_tokenCounter; i++) {
            if (balanceOf(owner, i) > 0) {
                count++;
            }
        }

        tokenIds = new uint256[](count);
        balances = new uint256[](count);
        
        uint256 index = 0;
        for (uint256 i = 1; i < s_tokenCounter; i++) {
            uint256 balance = balanceOf(owner, i);
            if (balance > 0) {
                tokenIds[index] = i;
                balances[index] = balance;
                index++;
            }
        }
    }

    ////////////////////////////////////////
    ///////   URI FUNCTIONS   /////////////
    ////////////////////////////////////////

    /**
     * @notice Returns the URI for a token ID
     */
    function uri(uint256 tokenId) 
        public 
        view 
        override 
        tokenExists(tokenId) 
        returns (string memory) 
    {
        string memory tokenURI_ = s_tokenMetadata[tokenId].uri;
        
        // If token has specific URI, return it
        if (bytes(tokenURI_).length > 0) {
            return tokenURI_;
        }
        
        // Otherwise return baseURI + tokenId
        return string(abi.encodePacked(s_baseURI, tokenId.toString()));
    }

    ////////////////////////////////////////
    ///////    OVERRIDE FUNCTIONS   ///////
    ////////////////////////////////////////

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}