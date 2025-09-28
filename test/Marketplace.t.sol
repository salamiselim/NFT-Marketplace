// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {NFTMarketplace} from "../src/Marketplace.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

// Mock ERC721 for testing external NFTs
contract ERC721Mock is ERC721URIStorage {
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to, uint256 tokenId, string memory tokenURI) external {
        _mint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
    }
}

contract NFTMarketplaceTest is Test {
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
    event NFTMinted(address indexed creator, uint256 indexed tokenId, string tokenURI, address indexed to);
    event CreatorAdded(address indexed creator, address indexed addedBy);
    event CreatorRemoved(address indexed creator, address indexed removedBy);

    NFTMarketplace public marketplace;
    ERC721Mock public nftMock;

    address public constant OWNER = address(0x1);
    address public constant SELLER = address(0x2);
    address public constant BUYER = address(0x3);
    address public constant CREATOR = address(0x4);
    uint256 public constant FEE_BPS = 250; // 2.5%
    uint256 public constant TOKEN_ID = 1;
    uint256 public constant PRICE = 1 ether;
    uint256 public constant HIGHER_PRICE = 2 ether;
    uint256 public constant LOW_PRICE = 0.5 ether;
    string public constant TOKEN_URI = "ipfs://test-uri";

    function setUp() public {
        // Deploy marketplace as owner
        vm.prank(OWNER);
        marketplace = new NFTMarketplace(FEE_BPS, "NFT Marketplace", "NFTM");

        // Deploy mock NFT
        nftMock = new ERC721Mock();

        // Fund users
        vm.deal(SELLER, 100 ether);
        vm.deal(BUYER, 100 ether);
        vm.deal(CREATOR, 100 ether);

        // Mint NFT to seller
        vm.prank(SELLER);
        nftMock.mint(SELLER, TOKEN_ID, TOKEN_URI);
    }

    //////////////////////
    // Creator Role Tests //
    //////////////////////

    function test_AddCreator_Success() public {
        vm.prank(OWNER);
        vm.expectEmit(true, true, false, false, address(marketplace));
        emit CreatorAdded(CREATOR, OWNER);
        marketplace.addCreator(CREATOR);

        assertTrue(marketplace.isCreator(CREATOR));
        assertEq(marketplace.getCreatorCount(), 2); // Owner + new creator
        address[] memory creators = marketplace.getAllCreators();
        assertEq(creators[1], CREATOR);
    }

    function testRevert_AddCreator_AlreadyExists() public {
        vm.prank(OWNER);
        marketplace.addCreator(CREATOR);

        vm.prank(OWNER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__CreatorAlreadyExists.selector);
        marketplace.addCreator(CREATOR);
    }

    function testRevert_AddCreator_NotOwner() public {
        vm.prank(SELLER);
        vm.expectRevert(); // Ownable revert
        marketplace.addCreator(CREATOR);
    }

    function testRevert_AddCreator_InvalidRecipient() public {
        vm.prank(OWNER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidRecipient.selector);
        marketplace.addCreator(address(0));
    }

    function test_RemoveCreator_Success() public {
        vm.prank(OWNER);
        marketplace.addCreator(CREATOR);

        vm.prank(OWNER);
        vm.expectEmit(true, true, false, false, address(marketplace));
        emit CreatorRemoved(CREATOR, OWNER);
        marketplace.removeCreator(CREATOR);

        assertFalse(marketplace.isCreator(CREATOR));
        assertEq(marketplace.getCreatorCount(), 1); // Only owner remains
    }

    function testRevert_RemoveCreator_NotFound() public {
        vm.prank(OWNER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__CreatorNotFound.selector);
        marketplace.removeCreator(CREATOR);
    }

    function testRevert_RemoveCreator_NotOwner() public {
        vm.prank(OWNER);
        marketplace.addCreator(CREATOR);

        vm.prank(SELLER);
        vm.expectRevert(); // Ownable revert
        marketplace.removeCreator(CREATOR);
    }

    //////////////////////
    // Minting Tests //
    //////////////////////

    function test_MintNFT_Success() public {
        vm.prank(OWNER); // Owner has CREATOR_ROLE
        vm.expectEmit(true, true, true, true, address(marketplace));
        emit NFTMinted(OWNER, TOKEN_ID, TOKEN_URI, BUYER);
        uint256 tokenId = marketplace.mintNFT(BUYER, TOKEN_URI);

        assertEq(marketplace.ownerOf(tokenId), BUYER);
        assertEq(marketplace.tokenURI(tokenId), TOKEN_URI);
        assertEq(marketplace.getTotalMinted(), 1);
        assertEq(marketplace.getTokenCounter(), 2);
        NFTMarketplace.NFTInfo memory info = marketplace.getNFTInfo(tokenId);
        assertEq(info.creator, OWNER);
        assertTrue(info.isMarketplaceNFT);
    }

    function test_MintNFTToSelf_Success() public {
        vm.prank(OWNER);
        uint256 tokenId = marketplace.mintNFTToSelf(TOKEN_URI);

        assertEq(marketplace.ownerOf(tokenId), OWNER);
        assertEq(marketplace.tokenURI(tokenId), TOKEN_URI);
    }

    function test_BatchMintNFTs_Success() public {
        address[] memory recipients = new address[](2);
        string[] memory tokenURIs = new string[](2);
        recipients[0] = BUYER;
        recipients[1] = SELLER;
        tokenURIs[0] = TOKEN_URI;
        tokenURIs[1] = "ipfs://test-uri-2";

        vm.prank(OWNER);
        marketplace.batchMintNFTs(recipients, tokenURIs);

        assertEq(marketplace.ownerOf(1), BUYER);
        assertEq(marketplace.ownerOf(2), SELLER);
        assertEq(marketplace.getTotalMinted(), 2);
    }

    function testRevert_MintNFT_NotCreator() public {
        vm.prank(SELLER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__OnlyCreatorCanMint.selector);
        marketplace.mintNFT(BUYER, TOKEN_URI);
    }

    function testRevert_MintNFT_InvalidTokenURI() public {
        vm.prank(OWNER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidTokenURI.selector);
        marketplace.mintNFT(BUYER, "");
    }

    function testRevert_MintNFT_InvalidRecipient() public {
        vm.prank(OWNER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidRecipient.selector);
        marketplace.mintNFT(address(0), TOKEN_URI);
    }

    function testRevert_BatchMintNFTs_MismatchArrays() public {
        address[] memory recipients = new address[](2);
        string[] memory tokenURIs = new string[](1);
        vm.prank(OWNER);
        vm.expectRevert("Arrays length mismatch");
        marketplace.batchMintNFTs(recipients, tokenURIs);
    }

    function test_GetNFTsByCreator_Success() public {
    vm.startPrank(OWNER);
    console.log("Minting first NFT as:", msg.sender);
    marketplace.mintNFT(BUYER, TOKEN_URI);
    console.log("Minting second NFT as:", msg.sender);
    marketplace.mintNFT(SELLER, "ipfs://test-uri-2");
    vm.stopPrank();

    (uint256[] memory tokenIds, uint256 total) = marketplace.getNFTsByCreator(OWNER, 0, 2);
    assertEq(total, 2);
    assertEq(tokenIds.length, 2);
    assertEq(tokenIds[0], 1);
    assertEq(tokenIds[1], 2);
    }

    function test_GetNFTsByCreator_Pagination() public {
        vm.startPrank(OWNER);
        console.log("Minting first NFT as:", msg.sender);
        marketplace.mintNFT(BUYER, TOKEN_URI);
        console.log("Minting second NFT as:", msg.sender);
        marketplace.mintNFT(SELLER, "ipfs://test-uri-2");
        vm.stopPrank();

        (uint256[] memory tokenIds, uint256 total) = marketplace.getNFTsByCreator(OWNER, 1, 1);
        assertEq(total, 2);
        assertEq(tokenIds.length, 1);
        assertEq(tokenIds[0], 2);
    }

    //////////////////////
    // List Item Tests //
    //////////////////////

    function test_ListItem_Success() public {
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.stopPrank();

        NFTMarketplace.Listing memory listing = marketplace.getListing(address(nftMock), TOKEN_ID);
        assertEq(listing.price, PRICE);
        assertEq(listing.seller, SELLER);
        assertEq(nftMock.ownerOf(TOKEN_ID), address(marketplace));
        assertEq(marketplace.getCurrentListings(), 1);
    }

    function test_ListItem_EmitsEvent() public {
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        vm.expectEmit(true, true, true, true, address(marketplace));
        emit ItemListed(SELLER, address(nftMock), TOKEN_ID, PRICE);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.stopPrank();
    }

    function testRevert_ListItem_PriceZero() public {
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__PriceMustBeAboveZero.selector);
        marketplace.listItem(address(nftMock), TOKEN_ID, 0);
        vm.stopPrank();
    }

    function testRevert_ListItem_NotApproved() public {
        vm.prank(SELLER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NotApprovedForMarketplace.selector);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
    }

    function testRevert_ListItem_AlreadyListed() public {
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.expectRevert(
            abi.encodeWithSelector(NFTMarketplace.NFTMarketplace__AlreadyListed.selector, address(nftMock), TOKEN_ID)
        );
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.stopPrank();
    }

    function testFuzz_ListItem(uint256 price) public {
        price = bound(price, 1, type(uint256).max / 2);
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, price);
        vm.stopPrank();
        assertEq(marketplace.getListing(address(nftMock), TOKEN_ID).price, price);
    }

    function test_ListMarketplaceNFT_Success() public {
        vm.prank(OWNER);
        uint256 tokenId = marketplace.mintNFT(SELLER, TOKEN_URI);
        vm.startPrank(SELLER);
        marketplace.approve(address(marketplace), tokenId);
        marketplace.listItem(address(marketplace), tokenId, PRICE);
        vm.stopPrank();
        assertEq(marketplace.getListing(address(marketplace), tokenId).price, PRICE);
    }

    /////////////////////
    // Buy Item Tests //
    /////////////////////

    function test_BuyItem_Success() public {
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.stopPrank();

        vm.prank(BUYER);
        marketplace.buyItem{value: PRICE}(address(nftMock), TOKEN_ID);

        assertEq(nftMock.ownerOf(TOKEN_ID), BUYER);
        uint256 fee = (PRICE * FEE_BPS) / 10000;
        uint256 proceeds = PRICE - fee;
        assertEq(marketplace.getProceeds(SELLER), proceeds);
        assertEq(marketplace.getProceeds(OWNER), fee);
        assertEq(marketplace.getTotalSales(), 1);
        assertEq(marketplace.getTotalVolume(), PRICE);
        assertEq(marketplace.getCurrentListings(), 0);
    }

    function test_BuyItem_MarketplaceNFT_WithRoyalty() public {
        vm.prank(OWNER);
        uint256 tokenId = marketplace.mintNFT(SELLER, TOKEN_URI);
        vm.startPrank(SELLER);
        marketplace.approve(address(marketplace), tokenId);
        marketplace.listItem(address(marketplace), tokenId, PRICE);
        vm.stopPrank();

        vm.prank(BUYER);
        marketplace.buyItem{value: PRICE}(address(marketplace), tokenId);

        uint256 fee = (PRICE * FEE_BPS) / 10000;
        uint256 royalty = (PRICE * 250) / 10000; // 2.5% royalty
        uint256 proceeds = PRICE - fee - royalty;
        assertEq(marketplace.getProceeds(SELLER), proceeds);
        assertEq(marketplace.getProceeds(OWNER), fee + royalty);
    }

    function test_BuyItem_OverpayAndRefund() public {
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.stopPrank();

        uint256 overpay = PRICE + 0.1 ether;
        uint256 buyerBalanceBefore = BUYER.balance;
        vm.prank(BUYER);
        marketplace.buyItem{value: overpay}(address(nftMock), TOKEN_ID);
        assertEq(BUYER.balance, buyerBalanceBefore - PRICE);
    }

    function test_BuyItem_EmitsEvent() public {
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true, address(marketplace));
        emit ItemBought(BUYER, address(nftMock), TOKEN_ID, PRICE, SELLER);
        vm.prank(BUYER);
        marketplace.buyItem{value: PRICE}(address(nftMock), TOKEN_ID);
    }

    function testRevert_BuyItem_NotListed() public {
        vm.prank(BUYER);
        vm.expectRevert(
            abi.encodeWithSelector(NFTMarketplace.NFTMarketplace__NotListed.selector, address(nftMock), TOKEN_ID)
        );
        marketplace.buyItem{value: PRICE}(address(nftMock), TOKEN_ID);
    }

    function testRevert_BuyItem_PriceNotMet() public {
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.stopPrank();

        vm.prank(BUYER);
        vm.expectRevert(
            abi.encodeWithSelector(
                NFTMarketplace.NFTMarketplace__PriceNotMet.selector, address(nftMock), TOKEN_ID, PRICE
            )
        );
        marketplace.buyItem{value: PRICE - 1}(address(nftMock), TOKEN_ID);
    }

    /////////////////////////
    // Cancel Listing Tests //
    /////////////////////////

    function test_CancelListing_Success() public {
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        marketplace.cancelListing(address(nftMock), TOKEN_ID);
        vm.stopPrank();

        assertEq(nftMock.ownerOf(TOKEN_ID), SELLER);
        assertEq(marketplace.isNFTListed(address(nftMock), TOKEN_ID), false);
        assertEq(marketplace.getCurrentListings(), 0);
    }

    function testRevert_CancelListing_NotListed() public {
        vm.prank(SELLER);
        vm.expectRevert(
            abi.encodeWithSelector(NFTMarketplace.NFTMarketplace__NotListed.selector, address(nftMock), TOKEN_ID)
        );
        marketplace.cancelListing(address(nftMock), TOKEN_ID);
    }

    function testRevert_CancelListing_NotSeller() public {
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.stopPrank();

        vm.prank(BUYER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NotOwner.selector);
        marketplace.cancelListing(address(nftMock), TOKEN_ID);
    }

    /////////////////////////
    // Update Listing Tests //
    /////////////////////////

    function test_UpdateListing_Success() public {
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.expectEmit(true, true, true, true, address(marketplace));
        emit ListingUpdated(SELLER, address(nftMock), TOKEN_ID, PRICE, HIGHER_PRICE);
        marketplace.updateListing(address(nftMock), TOKEN_ID, HIGHER_PRICE);
        vm.stopPrank();

        assertEq(marketplace.getListing(address(nftMock), TOKEN_ID).price, HIGHER_PRICE);
    }

    function testRevert_UpdateListing_NotSeller() public {
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.stopPrank();

        vm.prank(BUYER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NotOwner.selector);
        marketplace.updateListing(address(nftMock), TOKEN_ID, HIGHER_PRICE);
    }

    ////////////////////////////
    // Withdraw Proceeds Tests //
    ////////////////////////////

    function test_WithdrawProceeds_Success() public {
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.stopPrank();

        vm.prank(BUYER);
        marketplace.buyItem{value: PRICE}(address(nftMock), TOKEN_ID);

        uint256 sellerBalanceBefore = SELLER.balance;
        uint256 fee = (PRICE * FEE_BPS) / 10000;
        uint256 proceeds = PRICE - fee;

        vm.prank(SELLER);
        marketplace.withdrawProceeds();

        assertEq(SELLER.balance, sellerBalanceBefore + proceeds);
        assertEq(marketplace.getProceeds(SELLER), 0);
    }

    function testRevert_WithdrawProceeds_NoProceeds() public {
        vm.prank(SELLER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NoProceeds.selector);
        marketplace.withdrawProceeds();
    }

    //////////////////////
    // Owner Fee Tests //
    //////////////////////

    function test_UpdateMarketplaceFee_Success() public {
        uint256 newFee = 500; // 5%
        vm.prank(OWNER);
        marketplace.updateMarketplaceFee(newFee);
        assertEq(marketplace.getMarketplaceFee(), newFee);
    }

    function testRevert_UpdateMarketplaceFee_Invalid() public {
        uint256 invalidFee = 1500; // >10%
        vm.prank(OWNER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidFee.selector);
        marketplace.updateMarketplaceFee(invalidFee);
    }

    function testRevert_UpdateMarketplaceFee_NotOwner() public {
        vm.prank(SELLER);
        vm.expectRevert(); // Ownable revert
        marketplace.updateMarketplaceFee(500);
    }

    ///////////////////////////
    // Emergency Withdraw Tests //
    ///////////////////////////

    function test_EmergencyWithdrawNFT_Success() public {
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.stopPrank();

        vm.prank(OWNER);
        marketplace.emergencyWithdrawNFT(address(nftMock), TOKEN_ID, BUYER);
        assertEq(nftMock.ownerOf(TOKEN_ID), BUYER);
    }

    function testRevert_EmergencyWithdrawNFT_NotOwner() public {
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.stopPrank();

        vm.prank(BUYER);
        vm.expectRevert(); // Ownable revert
        marketplace.emergencyWithdrawNFT(address(nftMock), TOKEN_ID, BUYER);
    }

    function testRevert_EmergencyWithdrawNFT_NotHeld() public {
        vm.prank(OWNER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NFTNotHeldByContract.selector);
        marketplace.emergencyWithdrawNFT(address(nftMock), TOKEN_ID, BUYER);
    }

    function testRevert_EmergencyWithdrawNFT_InvalidRecipient() public {
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.stopPrank();

        vm.prank(OWNER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidRecipient.selector);
        marketplace.emergencyWithdrawNFT(address(nftMock), TOKEN_ID, address(0));
    }

    //////////////////////
    // ETH Receive Tests //
    //////////////////////

    function test_ReceiveEth_Success() public {
        uint256 amount = 1 ether;
        vm.deal(BUYER, amount);
        vm.prank(BUYER);
        vm.expectEmit(true, false, false, true, address(marketplace));
        emit EthReceived(BUYER, amount);
        (bool success,) = address(marketplace).call{value: amount}("");
        assertTrue(success);
        assertEq(address(marketplace).balance, amount);
    }
}
