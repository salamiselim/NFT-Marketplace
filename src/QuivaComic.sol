// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title QuivaComic
 * @author SALAMI SELIM
 * @notice NFT Collection for comic creators with role-based minting
 * @dev Only addresses with CREATOR_ROLE can mint NFTs
 */
contract QuivaComic is ERC721URIStorage, ERC721Enumerable, Ownable, AccessControl, ReentrancyGuard {
    //////////////////////////////
    //////////  ERRORS  /////////
    /////////////////////////////
    error QuivaComic__OnlyCreatorCanMint();
    error QuivaComic__InvalidTokenURI();
    error QuivaComic__CreatorAlreadyExists();
    error QuivaComic__CreatorNotFound();
    error QuivaComic__ArrayLengthMismatch();
    error QuivaComic__EmptyArray();

    ////////////////////////////
    //////  EVENTS  ///////////
    ////////////////////////////
    event NFTMinted(address indexed creator, address indexed to, uint256 indexed tokenId, string tokenURI);

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

    struct NFTMetadata {
        address creator;
        uint256 mintTimestamp;
    }

    // Token ID -> NFT Metadata
    mapping(uint256 => NFTMetadata) private s_nftMetadata;

    // Creator address -> Array of token IDs they created
    mapping(address => uint256[]) private s_creatorTokens;

    // List of all creators (for enumeration)
    address[] private s_creatorList;

    // Token counter
    uint256 private s_tokenCounter;

    // Collection settings
    string private s_baseTokenURI;

    // Statistics
    uint256 private s_totalMinted;

    ///////////////////////////////////
    ///////   MODIFIERS  ///////////
    ////////////////////////////////

    modifier onlyCreator() {
        if (!hasRole(CREATOR_ROLE, msg.sender)) {
            revert QuivaComic__OnlyCreatorCanMint();
        }
        _;
    }

    ///////////////////////////////
    /////// CONSTRUCTOR //////////
    /////////////////////////////

    constructor(string memory baseTokenURI) ERC721("Quiva Comic", "QUIVA") Ownable(msg.sender) {
        s_baseTokenURI = baseTokenURI;

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

    function addCreator(address creator) external onlyOwner {
        if (hasRole(CREATOR_ROLE, creator)) {
            revert QuivaComic__CreatorAlreadyExists();
        }

        _grantRole(CREATOR_ROLE, creator);
        s_creatorList.push(creator);

        emit CreatorAdded(creator, msg.sender);
    }

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

    function removeCreator(address creator) external onlyOwner {
        if (!hasRole(CREATOR_ROLE, creator)) {
            revert QuivaComic__CreatorNotFound();
        }

        _revokeRole(CREATOR_ROLE, creator);

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
     * @dev Internal mint logic — no reentrancy guard
     */
    function _mintNFT(address to, string memory _tokenURI) internal returns (uint256 tokenId) {
        if (bytes(_tokenURI).length == 0) {
            revert QuivaComic__InvalidTokenURI();
        }

        tokenId = s_tokenCounter;
        s_tokenCounter++;
        s_totalMinted++;

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, _tokenURI);

        s_nftMetadata[tokenId] = NFTMetadata({creator: msg.sender, mintTimestamp: block.timestamp});

        s_creatorTokens[msg.sender].push(tokenId);

        emit NFTMinted(msg.sender, to, tokenId, _tokenURI);
    }

    /**
     * @notice Mint NFT to a specific address (only creators)
     * @param to Address to mint NFT to
     * @param _tokenURI Metadata URI for the NFT
     * @return tokenId The ID of the minted token
     */
    function mintNFT(address to, string memory _tokenURI) public onlyCreator nonReentrant returns (uint256) {
        return _mintNFT(to, _tokenURI);
    }

    /**
     * @notice Mint NFT to creator's own address
     */
    function mintNFTToSelf(string memory _tokenURI) external onlyCreator nonReentrant returns (uint256) {
        return _mintNFT(msg.sender, _tokenURI);
    }

    /**
     * @notice Batch mint NFTs to multiple addresses
     */
    function batchMintNFTs(address[] memory recipients, string[] memory tokenURIs)
        external
        onlyCreator
        nonReentrant
        returns (uint256[] memory tokenIds)
    {
        if (recipients.length != tokenURIs.length) {
            revert QuivaComic__ArrayLengthMismatch();
        }
        if (recipients.length == 0) {
            revert QuivaComic__EmptyArray();
        }

        tokenIds = new uint256[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            tokenIds[i] = _mintNFT(recipients[i], tokenURIs[i]);
        }
    }

    /**
     * @notice Mint multiple NFTs to a single address
     */
    function mintMultiple(address to, uint256 count, string memory baseURI)
        external
        onlyCreator
        nonReentrant
        returns (uint256[] memory tokenIds)
    {
        if (count == 0) {
            revert QuivaComic__EmptyArray();
        }

        tokenIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            string memory fullURI = string(abi.encodePacked(baseURI, _toString(s_tokenCounter)));
            tokenIds[i] = _mintNFT(to, fullURI);
        }
    }

    //////////////////////////////////////
    ///////    OWNER FUNCTIONS /////////
    ////////////////////////////////////

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        s_baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    ////////////////////////////////////////
    ///////    GETTER FUNCTIONS   ///////
    //////////////////////////////////////

    function getTokenCounter() external view returns (uint256) {
        return s_tokenCounter;
    }

    function getTotalMinted() external view returns (uint256) {
        return s_totalMinted;
    }

    function getBaseURI() external view returns (string memory) {
        return s_baseTokenURI;
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

    function getNFTMetadata(uint256 tokenId) external view returns (NFTMetadata memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return s_nftMetadata[tokenId];
    }

    function getCreatorOf(uint256 tokenId) external view returns (address) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return s_nftMetadata[tokenId].creator;
    }

    function getTokensByCreator(address creator) external view returns (uint256[] memory) {
        return s_creatorTokens[creator];
    }

    function getTokensByCreatorPaginated(address creator, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory tokens, uint256 total)
    {
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

    function getTokensByOwner(address owner) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(owner);
        uint256[] memory tokens = new uint256[](balance);

        for (uint256 i = 0; i < balance; i++) {
            tokens[i] = tokenOfOwnerByIndex(owner, i);
        }

        return tokens;
    }

    ////////////////////////////////////////
    ///////   INTERNAL FUNCTIONS   ////////
    ////////////////////////////////////////

    function _baseURI() internal view override returns (string memory) {
        return s_baseTokenURI;
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    ////////////////////////////////////////
    ///////    OVERRIDE FUNCTIONS   ///////
    ////////////////////////////////////////

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721URIStorage, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
