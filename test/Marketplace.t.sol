// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NFTMarketplace} from "../src/Marketplace.sol";
import {QuivaComic} from "../src/QuivaComic.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract ERC721Mock is ERC721, IERC721Receiver {
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract NFTMarketplaceTest is Test {
    // Events
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

    NFTMarketplace public marketplace;
    QuivaComic public quivaComic;
    ERC721Mock public mockNFT;

    address public constant OWNER = address(0x1);
    address public constant SELLER = address(0x2);
    address public constant BUYER = address(0x3);
    address public constant CREATOR = address(0x4);

    uint256 public constant FEE_BPS = 250; // 2.5%
    uint256 public constant TOKEN_ID = 1;
    uint256 public constant PRICE = 1 ether;
    uint256 public constant HIGHER_PRICE = 2 ether;
    uint256 public constant OVERPAY = PRICE + 0.1 ether;

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
        mockNFT = new ERC721Mock();

        // Fund users
        vm.deal(SELLER, 100 ether);
        vm.deal(BUYER, 100 ether);

        // Mint NFT to SELLER
        vm.prank(SELLER);
        mockNFT.mint(SELLER, TOKEN_ID);
    }

    function test_ListItem_Success() public {
        vm.startPrank(SELLER);
        mockNFT.approve(address(marketplace), TOKEN_ID);
        vm.expectEmit(true, true, true, true, address(marketplace));
        emit ItemListed(SELLER, address(mockNFT), TOKEN_ID, PRICE);
        marketplace.listItem(address(mockNFT), TOKEN_ID, PRICE);
        vm.stopPrank();

        NFTMarketplace.Listing memory listing = marketplace.getListing(address(mockNFT), TOKEN_ID);
        assertEq(listing.price, PRICE);
        assertEq(listing.seller, SELLER);
        assertEq(mockNFT.ownerOf(TOKEN_ID), address(marketplace));
        assertEq(marketplace.getCurrentListings(), 1);
    }

    function testRevert_ListItem_PriceZero() public {
        vm.startPrank(SELLER);
        mockNFT.approve(address(marketplace), TOKEN_ID);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__PriceMustBeAboveZero.selector);
        marketplace.listItem(address(mockNFT), TOKEN_ID, 0);
        vm.stopPrank();
    }

    function testRevert_ListItem_NotApproved() public {
        vm.prank(SELLER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NotApprovedForMarketplace.selector);
        marketplace.listItem(address(mockNFT), TOKEN_ID, PRICE);
    }

    function testRevert_ListItem_AlreadyListed() public {
        vm.startPrank(SELLER);
        mockNFT.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(mockNFT), TOKEN_ID, PRICE);
        vm.expectRevert(
            abi.encodeWithSelector(NFTMarketplace.NFTMarketplace__AlreadyListed.selector, address(mockNFT), TOKEN_ID)
        );
        marketplace.listItem(address(mockNFT), TOKEN_ID, PRICE);
        vm.stopPrank();
    }

    function test_ListQuivaComicNFT_Success() public {
        vm.prank(CREATOR);
        uint256 tokenId = quivaComic.mintNFT(SELLER, "ipfs://comic1");

        vm.startPrank(SELLER);
        quivaComic.approve(address(marketplace), tokenId);
        marketplace.listItem(address(quivaComic), tokenId, PRICE);
        vm.stopPrank();

        NFTMarketplace.Listing memory listing = marketplace.getListing(address(quivaComic), tokenId);
        assertEq(listing.price, PRICE);
        assertEq(listing.seller, SELLER);
    }

    function test_BuyItem_Success() public {
        vm.startPrank(SELLER);
        mockNFT.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(mockNFT), TOKEN_ID, PRICE);
        vm.stopPrank();

        uint256 buyerBalanceBefore = BUYER.balance;
        vm.prank(BUYER);
        marketplace.buyItem{value: PRICE}(address(mockNFT), TOKEN_ID);

        assertEq(mockNFT.ownerOf(TOKEN_ID), BUYER);
        uint256 fee = (PRICE * FEE_BPS) / 10000;
        uint256 proceeds = PRICE - fee;
        assertEq(marketplace.getProceeds(SELLER), proceeds);
        assertEq(marketplace.getProceeds(OWNER), fee);
        assertEq(marketplace.getTotalSales(), 1);
        assertEq(marketplace.getTotalVolume(), PRICE);
        assertEq(marketplace.getCurrentListings(), 0);
        assertEq(BUYER.balance, buyerBalanceBefore - PRICE);
    }

    function test_BuyItem_OverpayAndRefund() public {
        vm.startPrank(SELLER);
        mockNFT.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(mockNFT), TOKEN_ID, PRICE);
        vm.stopPrank();

        uint256 buyerBalanceBefore = BUYER.balance;
        vm.prank(BUYER);
        marketplace.buyItem{value: OVERPAY}(address(mockNFT), TOKEN_ID);
        assertEq(BUYER.balance, buyerBalanceBefore - PRICE);
    }

    function test_BuyItem_EmitsEvent() public {
        vm.startPrank(SELLER);
        mockNFT.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(mockNFT), TOKEN_ID, PRICE);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true, address(marketplace));
        emit ItemBought(BUYER, address(mockNFT), TOKEN_ID, PRICE, SELLER);
        vm.prank(BUYER);
        marketplace.buyItem{value: PRICE}(address(mockNFT), TOKEN_ID);
    }

    function testRevert_BuyItem_NotListed() public {
        vm.prank(BUYER);
        vm.expectRevert(
            abi.encodeWithSelector(NFTMarketplace.NFTMarketplace__NotListed.selector, address(mockNFT), TOKEN_ID)
        );
        marketplace.buyItem{value: PRICE}(address(mockNFT), TOKEN_ID);
    }

    function testRevert_BuyItem_PriceNotMet() public {
        vm.startPrank(SELLER);
        mockNFT.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(mockNFT), TOKEN_ID, PRICE);
        vm.stopPrank();

        vm.prank(BUYER);
        vm.expectRevert(
            abi.encodeWithSelector(
                NFTMarketplace.NFTMarketplace__PriceNotMet.selector, address(mockNFT), TOKEN_ID, PRICE
            )
        );
        marketplace.buyItem{value: PRICE - 1}(address(mockNFT), TOKEN_ID);
    }

    function test_CancelListing_Success() public {
        vm.startPrank(SELLER);
        mockNFT.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(mockNFT), TOKEN_ID, PRICE);
        vm.expectEmit(true, true, true, false, address(marketplace));
        emit ItemCanceled(SELLER, address(mockNFT), TOKEN_ID);
        marketplace.cancelListing(address(mockNFT), TOKEN_ID);
        vm.stopPrank();

        assertEq(mockNFT.ownerOf(TOKEN_ID), SELLER);
        assertFalse(marketplace.isNFTListed(address(mockNFT), TOKEN_ID));
        assertEq(marketplace.getCurrentListings(), 0);
    }

    function testRevert_CancelListing_NotListed() public {
        vm.prank(SELLER);
        vm.expectRevert(
            abi.encodeWithSelector(NFTMarketplace.NFTMarketplace__NotListed.selector, address(mockNFT), TOKEN_ID)
        );
        marketplace.cancelListing(address(mockNFT), TOKEN_ID);
    }

    function testRevert_CancelListing_NotSeller() public {
        vm.startPrank(SELLER);
        mockNFT.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(mockNFT), TOKEN_ID, PRICE);
        vm.stopPrank();

        vm.prank(BUYER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NotOwner.selector);
        marketplace.cancelListing(address(mockNFT), TOKEN_ID);
    }

    function test_UpdateListing_Success() public {
        vm.startPrank(SELLER);
        mockNFT.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(mockNFT), TOKEN_ID, PRICE);
        vm.expectEmit(true, true, true, true, address(marketplace));
        emit ListingUpdated(SELLER, address(mockNFT), TOKEN_ID, PRICE, HIGHER_PRICE);
        marketplace.updateListing(address(mockNFT), TOKEN_ID, HIGHER_PRICE);
        vm.stopPrank();

        assertEq(marketplace.getListing(address(mockNFT), TOKEN_ID).price, HIGHER_PRICE);
    }

    function testRevert_UpdateListing_NotSeller() public {
        vm.startPrank(SELLER);
        mockNFT.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(mockNFT), TOKEN_ID, PRICE);
        vm.stopPrank();

        vm.prank(BUYER);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NotOwner.selector);
        marketplace.updateListing(address(mockNFT), TOKEN_ID, HIGHER_PRICE);
    }

    function test_WithdrawProceeds_Success() public {
        vm.startPrank(SELLER);
        mockNFT.approve(address(marketplace), TOKEN_ID);
        marketplace.listItem(address(mockNFT), TOKEN_ID, PRICE);
        vm.stopPrank();

        vm.prank(BUYER);
        marketplace.buyItem{value: PRICE}(address(mockNFT), TOKEN_ID);

        uint256 sellerBalanceBefore = SELLER.balance;
        uint256 fee = (PRICE * FEE_BPS) / 10000;
        uint256 proceeds = PRICE - fee;

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
