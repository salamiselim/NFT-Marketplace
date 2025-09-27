
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {NFTMarketplace} from "../src/Marketplace.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// Mock ERC721 for testing
contract ERC721Mock is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract NFTMarketplaceTest is Test {
    event ItemListed(address indexed seller, address indexed nftAddress, uint256 indexed tokenId, uint256 price);
    event ItemBought(
        address indexed buyer, address indexed nftAddress, uint256 indexed tokenId, uint256 price, address seller
    );
    event EthReceived(address indexed sender, uint256 amount);

    NFTMarketplace public marketplace;
    ERC721Mock public nftMock;

    address public constant OWNER = address(0x1);
    address public constant SELLER = address(0x2);
    address public constant BUYER = address(0x3);
    uint256 public constant FEE_BPS = 250; // 2.5%
    uint256 public constant TOKEN_ID = 1;
    uint256 public constant PRICE = 1 ether;
    uint256 public constant HIGHER_PRICE = 2 ether;
    uint256 public constant LOW_PRICE = 0.5 ether;

    function setUp() public {
        // Deploy marketplace as owner
        vm.prank(OWNER);
        marketplace = new NFTMarketplace(FEE_BPS);

        // Deploy mock NFT
        nftMock = new ERC721Mock();

        // Fund users
        vm.deal(SELLER, 100 ether);
        vm.deal(BUYER, 100 ether);

        // Mint NFT to seller
        vm.prank(SELLER);
        nftMock.mint(SELLER, TOKEN_ID);
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

        vm.expectEmit(true, true, true, false, address(marketplace));
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
    vm.expectRevert(abi.encodeWithSelector(NFTMarketplace.NFTMarketplace__AlreadyListed.selector, address(nftMock), TOKEN_ID));
    marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
    vm.stopPrank();
    }

    function testFuzz_ListItem(uint256 price) public {
        price = bound(price, 1, type(uint256).max / 2); // Avoid overflow in fees
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, price);
        vm.stopPrank();

        assertEq(marketplace.getListing(address(nftMock), TOKEN_ID).price, price);
    }

    /////////////////////
    // Buy Item Tests //
    /////////////////////

    function test_BuyItem_Success() public {
        // List first
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.stopPrank();

        // Buy
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

    function test_BuyItem_OverpayAndRefund() public {
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.stopPrank();

        uint256 overpay = PRICE + 0.1 ether;
        uint256 buyerBalanceBefore = BUYER.balance;
        vm.prank(BUYER);
        marketplace.buyItem{value: overpay}(address(nftMock), TOKEN_ID);

        assertEq(BUYER.balance, buyerBalanceBefore - PRICE); // Refund happened
    }

    function test_BuyItem_EmitsEvent() public {
        // List first
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
        vm.expectRevert(abi.encodeWithSelector(NFTMarketplace.NFTMarketplace__NotListed.selector, address(nftMock), TOKEN_ID));
        marketplace.buyItem{value: PRICE}(address(nftMock), TOKEN_ID);
    }

    function testRevert_BuyItem_PriceNotMet() public {
    vm.startPrank(SELLER);
    nftMock.approve(address(marketplace), TOKEN_ID);
    marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
    vm.stopPrank();

    vm.prank(BUYER);
    vm.expectRevert(abi.encodeWithSelector(NFTMarketplace.NFTMarketplace__PriceNotMet.selector, address(nftMock), TOKEN_ID, PRICE));
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
    vm.expectRevert(abi.encodeWithSelector(NFTMarketplace.NFTMarketplace__NotListed.selector, address(nftMock), TOKEN_ID));
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
        // List and buy
        vm.startPrank(SELLER);
        nftMock.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(nftMock), TOKEN_ID, PRICE);
        vm.stopPrank();

        vm.prank(BUYER);
        marketplace.buyItem{value: PRICE}(address(nftMock), TOKEN_ID);

        // Withdraw as seller
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

    function test_ReceiveEth_Success() public {
        uint256 amount = 1 ether;
        vm.deal(BUYER, amount);
        vm.prank(BUYER);
        vm.expectEmit(true, false, false, true, address(marketplace));
        emit EthReceived(BUYER, amount);
        (bool success, ) = address(marketplace).call{value: amount}("");
        assertTrue(success);
        assertEq(address(marketplace).balance, amount);
    }
}