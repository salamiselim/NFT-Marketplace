// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {QuivaComic} from "../src/QuivaComic.sol";

contract QuivaComicTest is Test {
    // Events from QuivaComic.sol
    event NFTMinted(address indexed creator, address indexed to, uint256 indexed tokenId, string tokenURI);
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
        assertEq(comic.getTotalMinted(), 0);
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
        vm.expectRevert(); // OwnableUnauthorizedAccount
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
        vm.expectRevert(); // OwnableUnauthorizedAccount
        comic.removeCreator(CREATOR);
    }

    //////////////////////
    // Minting Tests //
    //////////////////////

    function test_MintNFT_Success() public {
        vm.expectEmit(true, true, true, true, address(comic));
        emit NFTMinted(OWNER, RECIPIENT, 1, TOKEN_URI);

        vm.prank(OWNER);
        uint256 tokenId = comic.mintNFT(RECIPIENT, TOKEN_URI);

        assertEq(tokenId, 1);
        assertEq(comic.ownerOf(1), RECIPIENT);

        assertEq(comic.tokenURI(1), string(abi.encodePacked(BASE_URI, TOKEN_URI)));
    }

    function test_MintNFTToSelf_Success() public {
        vm.prank(OWNER);
        uint256 tokenId = comic.mintNFTToSelf(TOKEN_URI);

        assertEq(tokenId, 1);
        assertEq(comic.ownerOf(1), OWNER);

        assertEq(comic.tokenURI(1), string(abi.encodePacked(BASE_URI, TOKEN_URI)));
    }

    function test_BatchMintNFTs_Success() public {
        address[] memory recipients = new address[](2);
        string[] memory uris = new string[](2);
        recipients[0] = RECIPIENT;
        recipients[1] = USER;
        uris[0] = TOKEN_URI;
        uris[1] = TOKEN_URI_2;

        vm.prank(OWNER);
        uint256[] memory tokenIds = comic.batchMintNFTs(recipients, uris);

        assertEq(tokenIds.length, 2);
        assertEq(comic.ownerOf(1), RECIPIENT);
        assertEq(comic.ownerOf(2), USER);

        assertEq(comic.tokenURI(1), string(abi.encodePacked(BASE_URI, TOKEN_URI)));
        assertEq(comic.tokenURI(2), string(abi.encodePacked(BASE_URI, TOKEN_URI_2)));
    }

    function test_MintMultiple_Success() public {
        vm.prank(OWNER);
        uint256[] memory tokenIds = comic.mintMultiple(RECIPIENT, 3, "ipfs://comic");

        assertEq(tokenIds.length, 3);
        assertEq(comic.ownerOf(1), RECIPIENT);
        assertEq(comic.ownerOf(2), RECIPIENT);
        assertEq(comic.ownerOf(3), RECIPIENT);

        assertEq(comic.tokenURI(1), string(abi.encodePacked(BASE_URI, "ipfs://comic1")));
        assertEq(comic.tokenURI(2), string(abi.encodePacked(BASE_URI, "ipfs://comic2")));
        assertEq(comic.tokenURI(3), string(abi.encodePacked(BASE_URI, "ipfs://comic3")));
    }

    function testRevert_MintNFT_NotCreator() public {
        vm.prank(USER);
        vm.expectRevert(QuivaComic.QuivaComic__OnlyCreatorCanMint.selector);
        comic.mintNFT(RECIPIENT, TOKEN_URI);
    }

    function testRevert_MintNFT_InvalidTokenURI() public {
        vm.prank(OWNER);
        vm.expectRevert(QuivaComic.QuivaComic__InvalidTokenURI.selector);
        comic.mintNFT(RECIPIENT, "");
    }

    function testRevert_BatchMintNFTs_MismatchArrays() public {
        address[] memory recipients = new address[](2);
        string[] memory uris = new string[](1);
        vm.prank(OWNER);
        vm.expectRevert(QuivaComic.QuivaComic__ArrayLengthMismatch.selector);
        comic.batchMintNFTs(recipients, uris);
    }

    function testRevert_BatchMintNFTs_EmptyArray() public {
        address[] memory empty = new address[](0);
        string[] memory emptyUris = new string[](0);
        vm.prank(OWNER);
        vm.expectRevert(QuivaComic.QuivaComic__EmptyArray.selector);
        comic.batchMintNFTs(empty, emptyUris);
    }

    function testRevert_MintMultiple_ZeroCount() public {
        vm.prank(OWNER);
        vm.expectRevert(QuivaComic.QuivaComic__EmptyArray.selector);
        comic.mintMultiple(RECIPIENT, 0, "ipfs://");
    }

    //////////////////////
    // Getters Tests //
    //////////////////////

    function test_GetTokensByCreator_Success() public {
        vm.startPrank(OWNER);
        comic.mintNFT(RECIPIENT, TOKEN_URI);
        comic.mintNFT(USER, TOKEN_URI_2);
        vm.stopPrank();

        uint256[] memory tokens = comic.getTokensByCreator(OWNER);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], 1);
        assertEq(tokens[1], 2);
    }

    function test_GetTokensByCreatorPaginated_Success() public {
        vm.startPrank(OWNER);
        comic.mintNFT(RECIPIENT, TOKEN_URI);
        comic.mintNFT(USER, TOKEN_URI_2);
        comic.mintNFT(RECIPIENT, "ipfs://comic3");
        vm.stopPrank();

        (uint256[] memory tokens, uint256 total) = comic.getTokensByCreatorPaginated(OWNER, 1, 1);
        assertEq(total, 3);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], 2);
    }

    function test_GetTokensByOwner_Success() public {
        vm.startPrank(OWNER);
        comic.mintNFT(RECIPIENT, TOKEN_URI);
        comic.mintNFT(RECIPIENT, TOKEN_URI_2);
        vm.stopPrank();

        uint256[] memory tokens = comic.getTokensByOwner(RECIPIENT);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], 1);
        assertEq(tokens[1], 2);
    }

    function test_GetCreatorOf_Success() public {
        vm.prank(OWNER);
        uint256 tokenId = comic.mintNFT(RECIPIENT, TOKEN_URI);
        assertEq(comic.getCreatorOf(tokenId), OWNER);
    }

    //////////////////////
    // Owner Functions //
    //////////////////////

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
        vm.expectRevert(); // OwnableUnauthorizedAccount
        comic.setBaseURI("ipfs://hack/");
    }

    //////////////////////
    // Fuzz Tests //
    //////////////////////

    function testFuzz_MintNFT(string memory uri) public {
        vm.assume(bytes(uri).length > 0);

        vm.prank(OWNER);
        uint256 tokenId = comic.mintNFT(RECIPIENT, uri);

        string memory expectedURI = string(abi.encodePacked(BASE_URI, uri));
        assertEq(comic.tokenURI(tokenId), expectedURI);
    }

    function testFuzz_AddCreator(address creator) public {
        vm.assume(creator != address(0));
        vm.assume(creator != OWNER);
        vm.prank(OWNER);
        comic.addCreator(creator);
        assertTrue(comic.isCreator(creator));
    }
}
