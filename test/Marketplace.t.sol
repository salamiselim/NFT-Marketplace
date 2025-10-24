// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NFTMarketplace} from "../src/Marketplace.sol";
import {QuivaComic} from "../src/QuivaComic.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract ERC1155Mock is ERC1155 {
    constructor() ERC1155("") {}

    function mint(address to, uint256 tokenId, uint256 amount) external {
        _mint(to, tokenId, amount, "");
    }
}

contract NFTMarketplaceTest is Test {
    // Events
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

    NFTMarketplace public marketplace;
    QuivaComic public quivaComic;
    ERC1155Mock public mockNFT;

    address public constant OWNER = address(0x1);
    address public constant SELLER = address(0x2);
    address public constant BUYER = address(0x3);
    address public constant CREATOR = address(0x4);

    uint256 public constant FEE_BPS = 250; // 2.5%
    uint256 public constant TOKEN_ID = 1;
    uint256 public constant AMOUNT = 10; // ERC1155: Amount to list/buy
    uint256 public constant PRICE_PER_ITEM = 0.1 ether; // Price per single item
    uint256 public constant TOTAL_PRICE = PRICE_PER_ITEM * AMOUNT; // Total for 10 items
    uint256 public constant HIGHER_PRICE = 0.2 ether;
    uint256 public constant OVERPAY = TOTAL_PRICE + 0.1 ether;

    function setUp() public {
        // Deploy QuivaComic
        vm.prank(OWNER);
        quivaComic = new QuivaComic("ipfs://base/");

        // Add CREATOR
        vm.prank(OWNER);
        quivaComic.addCreator(CREATOR);

        // Deploy Marketplace
        vm.prank(OWNER);
        marketplace = new NFTMarketplace(FEE_BPS);

        // Deploy Mock NFT
        mockNFT = new ERC1155Mock();

        // Fund users
        vm.deal(SELLER, 100 ether);
        vm.deal(BUYER, 100 ether);

        // Mint ERC1155 tokens to SELLER (50 copies)
        mockNFT.mint(SELLER, TOKEN_ID, 50);
    }

    //////////////////////////
    // List Item Tests //
    //////////////////////////

    function test_ListItem_Success() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        
        vm.expectEmit(true, true, true, true, address(marketplace));
        emit ItemListed(SELLER, address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        vm.stopPrank();

        NFTMarketplace.Listing memory listing = marketplace.getListing(address(mockNFT), TOKEN_ID);
        assertEq(listing.pricePerItem, PRICE_PER_ITEM);
        assertEq(listing.amount, AMOUNT);
        assertEq(listing.seller, SELLER);
        assertEq(mockNFT.balanceOf(address(marketplace), TOKEN_ID), AMOUNT);
        assertEq(marketplace.getCurrentListings(), 1);
    }

    function testRevert_ListItem_PriceZero() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__PriceMustBeAboveZero.selector);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, 0);
        vm.stopPrank();
    }

    function testRevert_ListItem_AmountZero() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidAmount.selector);
        marketplace.listItem(address(mockNFT), TOKEN_ID, 0, PRICE_PER_ITEM);
        vm.stopPrank();
    }

    function testRevert_ListItem_NotApproved() public {
        vm.prank(SELLER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NotApprovedForMarketplace.selector);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
    }

    function testRevert_ListItem_InsufficientBalance() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InsufficientBalance.selector);
        marketplace.listItem(address(mockNFT), TOKEN_ID, 100, PRICE_PER_ITEM); // Only have 50
        vm.stopPrank();
    }

    function testRevert_ListItem_AlreadyListed() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        
        vm.expectRevert(
            abi.encodeWithSelector(
                NFTMarketplace.NFTMarketplace__AlreadyListed.selector,
                address(mockNFT),
                TOKEN_ID
            )
        );
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        vm.stopPrank();
    }

    function test_ListQuivaComicNFT_Success() public {
        vm.prank(CREATOR);
        uint256 tokenId = quivaComic.mintNFT(SELLER, 20, "ipfs://comic1", 100);

        vm.startPrank(SELLER);
        quivaComic.setApprovalForAll(address(marketplace), true);
        marketplace.listItem(address(quivaComic), tokenId, 10, PRICE_PER_ITEM);
        vm.stopPrank();

        NFTMarketplace.Listing memory listing = marketplace.getListing(address(quivaComic), tokenId);
        assertEq(listing.pricePerItem, PRICE_PER_ITEM);
        assertEq(listing.amount, 10);
        assertEq(listing.seller, SELLER);
    }

    //////////////////////////
    // Buy Item Tests //
    //////////////////////////

    function test_BuyItem_Success() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        vm.stopPrank();

        uint256 buyerBalanceBefore = BUYER.balance;
        
        vm.prank(BUYER);
        marketplace.buyItem{value: TOTAL_PRICE}(address(mockNFT), TOKEN_ID, AMOUNT);

        assertEq(mockNFT.balanceOf(BUYER, TOKEN_ID), AMOUNT);
        
        uint256 fee = (TOTAL_PRICE * FEE_BPS) / 10000;
        uint256 proceeds = TOTAL_PRICE - fee;
        
        assertEq(marketplace.getProceeds(SELLER), proceeds);
        assertEq(marketplace.getProceeds(OWNER), fee);
        assertEq(marketplace.getTotalSales(), 1);
        assertEq(marketplace.getTotalVolume(), TOTAL_PRICE);
        assertEq(marketplace.getCurrentListings(), 0);
        assertEq(BUYER.balance, buyerBalanceBefore - TOTAL_PRICE);
    }

    function test_BuyItem_PartialPurchase() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        vm.stopPrank();

        uint256 buyAmount = 5; // Buy only 5 out of 10
        uint256 cost = PRICE_PER_ITEM * buyAmount;

        vm.prank(BUYER);
        marketplace.buyItem{value: cost}(address(mockNFT), TOKEN_ID, buyAmount);

        assertEq(mockNFT.balanceOf(BUYER, TOKEN_ID), buyAmount);
        
        // Check listing still exists with reduced amount
        NFTMarketplace.Listing memory listing = marketplace.getListing(address(mockNFT), TOKEN_ID);
        assertEq(listing.amount, AMOUNT - buyAmount);
        assertEq(marketplace.getCurrentListings(), 1); // Still listed
    }

    function test_BuyItem_OverpayAndRefund() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        vm.stopPrank();

        uint256 buyerBalanceBefore = BUYER.balance;
        
        vm.prank(BUYER);
        marketplace.buyItem{value: OVERPAY}(address(mockNFT), TOKEN_ID, AMOUNT);
        
        assertEq(BUYER.balance, buyerBalanceBefore - TOTAL_PRICE);
    }

    function test_BuyItem_EmitsEvent() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true, address(marketplace));
        emit ItemBought(BUYER, address(mockNFT), TOKEN_ID, AMOUNT, TOTAL_PRICE, SELLER);
        
        vm.prank(BUYER);
        marketplace.buyItem{value: TOTAL_PRICE}(address(mockNFT), TOKEN_ID, AMOUNT);
    }

    function testRevert_BuyItem_NotListed() public {
        vm.prank(BUYER);
        vm.expectRevert(
            abi.encodeWithSelector(
                NFTMarketplace.NFTMarketplace__NotListed.selector,
                address(mockNFT),
                TOKEN_ID
            )
        );
        marketplace.buyItem{value: TOTAL_PRICE}(address(mockNFT), TOKEN_ID, AMOUNT);
    }

    function testRevert_BuyItem_AmountZero() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        vm.stopPrank();

        vm.prank(BUYER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidAmount.selector);
        marketplace.buyItem{value: TOTAL_PRICE}(address(mockNFT), TOKEN_ID, 0);
    }

    function testRevert_BuyItem_ExceedsAvailable() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        vm.stopPrank();

        vm.prank(BUYER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidAmount.selector);
        marketplace.buyItem{value: TOTAL_PRICE * 2}(address(mockNFT), TOKEN_ID, AMOUNT * 2);
    }

    function testRevert_BuyItem_PriceNotMet() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        vm.stopPrank();

        vm.prank(BUYER);
        vm.expectRevert(
            abi.encodeWithSelector(
                NFTMarketplace.NFTMarketplace__PriceNotMet.selector,
                address(mockNFT),
                TOKEN_ID,
                TOTAL_PRICE
            )
        );
        marketplace.buyItem{value: TOTAL_PRICE - 1}(address(mockNFT), TOKEN_ID, AMOUNT);
    }

    //////////////////////////
    // Cancel Listing Tests //
    //////////////////////////

    function test_CancelListing_Success() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        
        vm.expectEmit(true, true, true, true, address(marketplace));
        emit ItemCanceled(SELLER, address(mockNFT), TOKEN_ID, AMOUNT);
        marketplace.cancelListing(address(mockNFT), TOKEN_ID);
        vm.stopPrank();

        assertEq(mockNFT.balanceOf(SELLER, TOKEN_ID), 50); // Got back all 50 (40 + 10)
        assertFalse(marketplace.isNFTListed(address(mockNFT), TOKEN_ID));
        assertEq(marketplace.getCurrentListings(), 0);
    }

    function testRevert_CancelListing_NotListed() public {
        vm.prank(SELLER);
        vm.expectRevert(
            abi.encodeWithSelector(
                NFTMarketplace.NFTMarketplace__NotListed.selector,
                address(mockNFT),
                TOKEN_ID
            )
        );
        marketplace.cancelListing(address(mockNFT), TOKEN_ID);
    }

    function testRevert_CancelListing_NotSeller() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        vm.stopPrank();

        vm.prank(BUYER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NotOwner.selector);
        marketplace.cancelListing(address(mockNFT), TOKEN_ID);
    }

    //////////////////////////
    // Update Listing Tests //
    //////////////////////////

    function test_UpdateListing_Success() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        
        vm.expectEmit(true, true, true, true, address(marketplace));
        emit ListingUpdated(SELLER, address(mockNFT), TOKEN_ID, PRICE_PER_ITEM, HIGHER_PRICE);
        marketplace.updateListing(address(mockNFT), TOKEN_ID, HIGHER_PRICE);
        vm.stopPrank();

        assertEq(marketplace.getListing(address(mockNFT), TOKEN_ID).pricePerItem, HIGHER_PRICE);
    }

    function testRevert_UpdateListing_PriceZero() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        
        vm.expectRevert(NFTMarketplace.NFTMarketplace__PriceMustBeAboveZero.selector);
        marketplace.updateListing(address(mockNFT), TOKEN_ID, 0);
        vm.stopPrank();
    }

    function testRevert_UpdateListing_NotSeller() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        vm.stopPrank();

        vm.prank(BUYER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NotOwner.selector);
        marketplace.updateListing(address(mockNFT), TOKEN_ID, HIGHER_PRICE);
    }

    //////////////////////////
    // Withdraw Proceeds Tests //
    //////////////////////////

    function test_WithdrawProceeds_Success() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        vm.stopPrank();

        vm.prank(BUYER);
        marketplace.buyItem{value: TOTAL_PRICE}(address(mockNFT), TOKEN_ID, AMOUNT);

        uint256 sellerBalanceBefore = SELLER.balance;
        uint256 fee = (TOTAL_PRICE * FEE_BPS) / 10000;
        uint256 proceeds = TOTAL_PRICE - fee;

        vm.prank(SELLER);
        vm.expectEmit(true, false, false, true, address(marketplace));
        emit ProceedsWithdrawn(SELLER, proceeds);
        marketplace.withdrawProceeds();

        assertEq(SELLER.balance, sellerBalanceBefore + proceeds);
        assertEq(marketplace.getProceeds(SELLER), 0);
    }

    function testRevert_WithdrawProceeds_NoProceeds() public {
        vm.prank(SELLER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NoProceeds.selector);
        marketplace.withdrawProceeds();
    }

    //////////////////////////
    // Owner Functions Tests //
    //////////////////////////

    function test_UpdateMarketplaceFee_Success() public {
        uint256 newFee = 500;
        vm.prank(OWNER);
        marketplace.updateMarketplaceFee(newFee);
        assertEq(marketplace.getMarketplaceFee(), newFee);
    }

    function testRevert_UpdateMarketplaceFee_Invalid() public {
        uint256 invalidFee = 1500;
        vm.prank(OWNER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidFee.selector);
        marketplace.updateMarketplaceFee(invalidFee);
    }

    function testRevert_UpdateMarketplaceFee_NotOwner() public {
        vm.prank(SELLER);
        vm.expectRevert();
        marketplace.updateMarketplaceFee(500);
    }

    //////////////////////////
    // Helper Functions Tests //
    //////////////////////////

    function test_CalculateTotalPrice_Success() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listItem(address(mockNFT), TOKEN_ID, AMOUNT, PRICE_PER_ITEM);
        vm.stopPrank();

        (uint256 totalPrice, uint256 fee, uint256 proceeds) = 
            marketplace.calculateTotalPrice(address(mockNFT), TOKEN_ID, 5);

        uint256 expectedTotal = PRICE_PER_ITEM * 5;
        uint256 expectedFee = (expectedTotal * FEE_BPS) / 10000;
        uint256 expectedProceeds = expectedTotal - expectedFee;

        assertEq(totalPrice, expectedTotal);
        assertEq(fee, expectedFee);
        assertEq(proceeds, expectedProceeds);
    }

    //////////////////////////
    // Receive ETH Tests //
    //////////////////////////

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

    //////////////////////////
    // Integration Tests //
    //////////////////////////

    function test_MultiplePartialBuys() public {
        vm.startPrank(SELLER);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listItem(address(mockNFT), TOKEN_ID, 20, PRICE_PER_ITEM);
        vm.stopPrank();

        // Buyer 1 buys 5
        vm.prank(BUYER);
        marketplace.buyItem{value: PRICE_PER_ITEM * 5}(address(mockNFT), TOKEN_ID, 5);
        assertEq(mockNFT.balanceOf(BUYER, TOKEN_ID), 5);

        // Buyer 2 buys 10
        address buyer2 = makeAddr("buyer2");
        vm.deal(buyer2, 100 ether);
        vm.prank(buyer2);
        marketplace.buyItem{value: PRICE_PER_ITEM * 10}(address(mockNFT), TOKEN_ID, 10);
        assertEq(mockNFT.balanceOf(buyer2, TOKEN_ID), 10);

        // Check listing updated
        NFTMarketplace.Listing memory listing = marketplace.getListing(address(mockNFT), TOKEN_ID);
        assertEq(listing.amount, 5); // 20 - 5 - 10 = 5 remaining
    }
}