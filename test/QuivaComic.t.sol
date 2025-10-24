// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {QuivaComic} from "../src/QuivaComic.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract QuivaComicTest is Test {
    // Events from QuivaComic.sol
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

    QuivaComic public comic;

    address public constant OWNER = address(0x1);
    address public constant CREATOR = address(0x2);
    address public constant RECIPIENT = address(0x3);
    address public constant USER = address(0x4);

    string public constant BASE_URI = "ipfs://base/";
    string public constant TOKEN_URI = "ipfs://comic1";
    string public constant TOKEN_URI_2 = "ipfs://comic2";

    function setUp() public {
        vm.prank(OWNER);
        comic = new QuivaComic(BASE_URI);
    }

    //////////////////////////
    // Constructor & Setup //
    //////////////////////////

    function test_Constructor_SetsBaseURI() public view {
        assertEq(comic.getBaseURI(), BASE_URI);
    }

    function test_Constructor_GrantsRoles() public view {
        assertTrue(comic.hasRole(comic.DEFAULT_ADMIN_ROLE(), OWNER));
        assertTrue(comic.isCreator(OWNER));
        assertEq(comic.getCreatorCount(), 1);
        assertEq(comic.getAllCreators()[0], OWNER);
    }

    function test_Constructor_TokenCounterStartsAtOne() public view {
        assertEq(comic.getTokenCounter(), 1);
        assertEq(comic.getTotalTokenTypes(), 0);
    }

    function test_Constructor_SetsNameAndSymbol() public view {
        assertEq(comic.name(), "Quiva Comic");
        assertEq(comic.symbol(), "QUIVA");
    }

    //////////////////////
    // Creator Management //
    //////////////////////

    function test_AddCreator_Success() public {
        vm.prank(OWNER);
        vm.expectEmit(true, true, false, false, address(comic));
        emit CreatorAdded(CREATOR, OWNER);
        comic.addCreator(CREATOR);

        assertTrue(comic.isCreator(CREATOR));
        assertEq(comic.getCreatorCount(), 2);
        address[] memory creators = comic.getAllCreators();
        assertEq(creators[1], CREATOR);
    }

    function test_AddCreators_BatchSuccess() public {
        address[] memory newCreators = new address[](2);
        newCreators[0] = CREATOR;
        newCreators[1] = RECIPIENT;

        vm.startPrank(OWNER);
        vm.expectEmit(true, true, false, false, address(comic));
        emit CreatorAdded(CREATOR, OWNER);
        vm.expectEmit(true, true, false, false, address(comic));
        emit CreatorAdded(RECIPIENT, OWNER);
        comic.addCreators(newCreators);
        vm.stopPrank();

        assertTrue(comic.isCreator(CREATOR));
        assertTrue(comic.isCreator(RECIPIENT));
        assertEq(comic.getCreatorCount(), 3);
    }

    function testRevert_AddCreator_AlreadyExists() public {
        vm.prank(OWNER);
        comic.addCreator(CREATOR);

        vm.prank(OWNER);
        vm.expectRevert(QuivaComic.QuivaComic__CreatorAlreadyExists.selector);
        comic.addCreator(CREATOR);
    }

    function testRevert_AddCreator_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        comic.addCreator(CREATOR);
    }

    function testRevert_AddCreators_EmptyArray() public {
        address[] memory empty = new address[](0);
        vm.prank(OWNER);
        vm.expectRevert(QuivaComic.QuivaComic__EmptyArray.selector);
        comic.addCreators(empty);
    }

    function test_RemoveCreator_Success() public {
        vm.prank(OWNER);
        comic.addCreator(CREATOR);

        vm.prank(OWNER);
        vm.expectEmit(true, true, false, false, address(comic));
        emit CreatorRemoved(CREATOR, OWNER);
        comic.removeCreator(CREATOR);

        assertFalse(comic.isCreator(CREATOR));
        assertEq(comic.getCreatorCount(), 1);
    }

    function testRevert_RemoveCreator_NotFound() public {
        vm.prank(OWNER);
        vm.expectRevert(QuivaComic.QuivaComic__CreatorNotFound.selector);
        comic.removeCreator(CREATOR);
    }

    function testRevert_RemoveCreator_NotOwner() public {
        vm.prank(OWNER);
        comic.addCreator(CREATOR);

        vm.prank(USER);
        vm.expectRevert();
        comic.removeCreator(CREATOR);
    }

    //////////////////////
    // Minting Tests //
    //////////////////////

    function test_MintNFT_UniqueNFT() public {
        vm.expectEmit(true, true, true, true, address(comic));
        emit NFTMinted(OWNER, RECIPIENT, 1, 1, TOKEN_URI);

        vm.prank(OWNER);
        uint256 tokenId = comic.mintNFT(RECIPIENT, 1, TOKEN_URI, 1); // Unique 1-of-1

        assertEq(tokenId, 1);
        assertEq(comic.balanceOf(RECIPIENT, 1), 1);
        assertEq(comic.totalSupply(1), 1);
        assertEq(comic.uri(1), TOKEN_URI);
        assertEq(comic.getTotalTokenTypes(), 1);

        QuivaComic.TokenMetadata memory meta = comic.getTokenMetadata(1);
        assertEq(meta.creator, OWNER);
        assertEq(meta.maxSupply, 1);
    }

    function test_MintNFT_Edition() public {
        vm.prank(OWNER);
        uint256 tokenId = comic.mintNFT(RECIPIENT, 100, TOKEN_URI, 1000); // 100 copies, max 1000

        assertEq(tokenId, 1);
        assertEq(comic.balanceOf(RECIPIENT, 1), 100);
        assertEq(comic.totalSupply(1), 100);
        assertEq(comic.uri(1), TOKEN_URI);
        assertEq(comic.getTotalTokenTypes(), 1);

        QuivaComic.TokenMetadata memory meta = comic.getTokenMetadata(1);
        assertEq(meta.maxSupply, 1000);
    }

    function test_MintNFTToSelf_Success() public {
        vm.prank(OWNER);
        uint256 tokenId = comic.mintNFTToSelf(TOKEN_URI);

        assertEq(tokenId, 1);
        assertEq(comic.balanceOf(OWNER, 1), 1);
        assertEq(comic.uri(1), TOKEN_URI);
        assertEq(comic.getTotalTokenTypes(), 1);
    }

    function test_MintMore_Success() public {
        // Initial mint
        vm.prank(OWNER);
        uint256 tokenId = comic.mintNFT(RECIPIENT, 50, TOKEN_URI, 200);

        // Mint more of same token
        vm.expectEmit(true, true, true, true, address(comic));
        emit NFTMinted(OWNER, RECIPIENT, tokenId, 75, TOKEN_URI);

        vm.prank(OWNER);
        comic.mintMore(tokenId, RECIPIENT, 75);

        assertEq(comic.balanceOf(RECIPIENT, tokenId), 125);
        assertEq(comic.totalSupply(tokenId), 125);
        assertEq(comic.getTotalTokenTypes(), 1);
    }

    function testRevert_MintMore_ExceedsMaxSupply() public {
        vm.prank(OWNER);
        uint256 tokenId = comic.mintNFT(RECIPIENT, 50, TOKEN_URI, 100);

        vm.prank(OWNER);
        vm.expectRevert("Exceeds max supply");
        comic.mintMore(tokenId, RECIPIENT, 51);
    }

    function testRevert_MintMore_NotCreator() public {
        vm.prank(OWNER);
        comic.addCreator(CREATOR);
        vm.prank(CREATOR);
        uint256 tokenId = comic.mintNFT(RECIPIENT, 1, TOKEN_URI, 0);

        vm.prank(OWNER);
        vm.expectRevert("Not token creator");
        comic.mintMore(tokenId, RECIPIENT, 1);
    }

    function testRevert_MintMore_TokenDoesNotExist() public {
        vm.prank(OWNER);
        vm.expectRevert(QuivaComic.QuivaComic__TokenDoesNotExist.selector);
        comic.mintMore(999, RECIPIENT, 1);
    }

    function test_BatchMintNFTs_Success() public {
    address[] memory recipients = new address[](2);
    uint256[] memory amounts = new uint256[](2);
    string[] memory uris = new string[](2);
    uint256[] memory maxSupplies = new uint256[](2);

    recipients[0] = RECIPIENT;
    recipients[1] = USER;
    amounts[0] = 10;
    amounts[1] = 5;
    uris[0] = TOKEN_URI;
    uris[1] = TOKEN_URI_2;
    maxSupplies[0] = 100;
    maxSupplies[1] = 50;

    vm.startPrank(OWNER);
    // Expect two mint events
    vm.expectEmit(true, true, true, true, address(comic));
    emit NFTMinted(OWNER, RECIPIENT, 1, 10, TOKEN_URI);
    vm.expectEmit(true, true, true, true, address(comic));
    emit NFTMinted(OWNER, USER, 2, 5, TOKEN_URI_2);

    uint256[] memory tokenIds = comic.batchMintNFTs(recipients, amounts, uris, maxSupplies);
    vm.stopPrank();

    assertEq(tokenIds[0], 1);
    assertEq(tokenIds[1], 2);
    assertEq(comic.balanceOf(RECIPIENT, 1), 10);
    assertEq(comic.balanceOf(USER, 2), 5);
    assertEq(comic.getTotalTokenTypes(), 2);
    }

    function testRevert_BatchMintNFTs_ArrayMismatch() public {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](2);
        string[] memory uris = new string[](1);
        uint256[] memory maxSupplies = new uint256[](1);

        vm.prank(OWNER);
        vm.expectRevert(QuivaComic.QuivaComic__ArrayLengthMismatch.selector);
        comic.batchMintNFTs(recipients, amounts, uris, maxSupplies);
    }

    function testRevert_BatchMintNFTs_EmptyArray() public {
        address[] memory empty = new address[](0);
        uint256[] memory amounts = new uint256[](0);
        string[] memory uris = new string[](0);
        uint256[] memory maxSupplies = new uint256[](0);

       

        vm.prank(OWNER);
        vm.expectRevert(QuivaComic.QuivaComic__EmptyArray.selector);
        comic.batchMintNFTs(empty, amounts, uris, maxSupplies);
    }

    function test_MintEdition_Success() public {
        vm.prank(OWNER);
        uint256 tokenId = comic.mintEdition(RECIPIENT, 25, TOKEN_URI, 500);

        assertEq(tokenId, 1);
        assertEq(comic.balanceOf(RECIPIENT, 1), 25);
        assertEq(comic.uri(1), TOKEN_URI);
    }

    function testRevert_MintNFT_InvalidAmount() public {
        vm.prank(OWNER);
        vm.expectRevert(QuivaComic.QuivaComic__InvalidAmount.selector);
        comic.mintNFT(RECIPIENT, 0, TOKEN_URI, 1);
    }

    function testRevert_MintNFT_InvalidURI() public {
        vm.prank(OWNER);
        vm.expectRevert(QuivaComic.QuivaComic__InvalidTokenURI.selector);
        comic.mintNFT(RECIPIENT, 1, "", 1);
    }

    function testRevert_MintNFT_NotCreator() public {
        vm.prank(USER);
        vm.expectRevert(QuivaComic.QuivaComic__OnlyCreatorCanMint.selector);
        comic.mintNFT(RECIPIENT, 1, TOKEN_URI, 1);
    }

    //////////////////////
    // Metadata & URI //
    //////////////////////

    function test_URI_SpecificURI() public {
        vm.prank(OWNER);
        comic.mintNFT(RECIPIENT, 1, TOKEN_URI, 1);
        assertEq(comic.uri(1), TOKEN_URI);
    }

    function testRevert_URI_TokenDoesNotExist() public {
        vm.expectRevert(QuivaComic.QuivaComic__TokenDoesNotExist.selector);
        comic.uri(999);
    }

    function test_SetBaseURI_Success() public {
        string memory newURI = "ipfs://newbase/";
        vm.prank(OWNER);
        vm.expectEmit(false, false, false, true, address(comic));
        emit BaseURIUpdated(newURI);
        comic.setBaseURI(newURI);
        assertEq(comic.getBaseURI(), newURI);
    }

    function testRevert_SetBaseURI_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        comic.setBaseURI("ipfs://hack/");
    }

    //////////////////////
    // Getters & Views //
    //////////////////////

    function test_GetTokenMetadata_Success() public {
        vm.prank(OWNER);
        comic.mintNFT(RECIPIENT, 1, TOKEN_URI, 100);

        QuivaComic.TokenMetadata memory meta = comic.getTokenMetadata(1);
        assertEq(meta.creator, OWNER);
        assertEq(meta.uri, TOKEN_URI);
        assertEq(meta.maxSupply, 100);
        assertGt(meta.mintTimestamp, 0);
    }

    function test_GetCreatorOf_Success() public {
        vm.prank(OWNER);
        comic.mintNFT(RECIPIENT, 1, TOKEN_URI, 1);
        assertEq(comic.getCreatorOf(1), OWNER);
    }

    function test_GetTokensByCreator_Success() public {
    vm.startPrank(OWNER); // ← ALL calls from OWNER
    comic.mintNFT(RECIPIENT, 1, TOKEN_URI, 1);
    comic.mintNFT(RECIPIENT, 1, TOKEN_URI_2, 1);
    vm.stopPrank();

    uint256[] memory tokens = comic.getTokensByCreator(OWNER);
    assertEq(tokens.length, 2);
    assertEq(tokens[0], 1);
    assertEq(tokens[1], 2);
   }

    function test_GetTokensByCreatorPaginated_Success() public {
        vm.startPrank(OWNER);
        comic.mintNFT(RECIPIENT, 1, TOKEN_URI, 1);
        comic.mintNFT(RECIPIENT, 1, TOKEN_URI_2, 1);
        comic.mintNFT(RECIPIENT, 1, "ipfs://3", 1);
        vm.stopPrank();

        (uint256[] memory tokens, uint256 total) = comic.getTokensByCreatorPaginated(OWNER, 1, 1);
        assertEq(total, 3);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], 2);
    }

    function test_GetTokensByOwner_Success() public {
    vm.startPrank(OWNER);
    comic.mintNFT(RECIPIENT, 10, TOKEN_URI, 100); // tokenId=1
    comic.mintNFT(USER, 5, TOKEN_URI_2, 50);      // tokenId=2
    vm.stopPrank();

    (uint256[] memory ids, uint256[] memory balances) = comic.getTokensByOwner(RECIPIENT);
    assertEq(ids.length, 1);
    assertEq(ids[0], 1);
    assertEq(balances[0], 10);

    (ids, balances) = comic.getTokensByOwner(USER);
    assertEq(ids.length, 1);
    assertEq(ids[0], 2);
    assertEq(balances[0], 5);
   }

    function test_GetTokensByOwner_Empty() public view {
        (uint256[] memory ids, uint256[] memory balances) = comic.getTokensByOwner(USER);
        assertEq(ids.length, 0);
        assertEq(balances.length, 0);
    }

    function test_SupportsInterface() public view {
        assertTrue(comic.supportsInterface(type(IERC1155).interfaceId));
        assertTrue(comic.supportsInterface(type(IAccessControl).interfaceId));
    }
}