// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Shop.sol";
import "../src/Token.sol";

contract ShopTest is Test {
    ShopManager public shop;
    Token public token;
    address public owner;
    address public user1;
    address public user2;
    address public trustedForwarder;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        trustedForwarder = address(0x3);

        // Start at a known timestamp
        vm.warp(1000);

        // Deploy token
        token = new Token(1_000_000, trustedForwarder);

        // Deploy shop contract
        shop = new ShopManager(address(token));

        // Transfer token ownership to shop
        token.transferOwnership(address(shop));

        // Label addresses for better trace output
        vm.label(owner, "Owner (Test Contract)");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(address(token), "Token");
        vm.label(address(shop), "Shop");
    }

    function testListItem() public {
        string memory name = "Test Item";
        string memory description = "Test Description";
        uint256 price = 10 * 10 ** 18; // 10 tokens (CLAIM_AMOUNT)
        string memory uri = "ipfs://test-uri";

        uint256 itemId = shop.listItem(name, description, price, uri);
        assertEq(itemId, 0); // First item ID is 0

        ShopManager.Item memory item = shop.getItem(itemId);
        assertEq(item.name, name);
        assertEq(item.description, description);
        assertEq(item.price, price);
        assertTrue(item.isAvailable);
    }

    function testPurchaseItem() public {
        uint256 price = 10 * 10 ** 18; // 10 tokens
        // List item
        uint256 itemId = shop.listItem(
            "Test Item",
            "Test Description",
            price,
            "ipfs://test-uri"
        );

        // Owner claims tokens (needs 10 tokens for user1)
        // No need to prank owner, address(this) is owner
        token.claim(); // Owner has 10 tokens at timestamp 1000
        assertEq(token.balanceOf(owner), price);

        // Transfer tokens to user1
        token.transfer(user1, price);
        assertEq(token.balanceOf(user1), price);
        assertEq(token.balanceOf(owner), 0);

        // Purchase item by user1
        vm.startPrank(user1);
        token.approve(address(shop), price);
        shop.purchaseItem(itemId);
        vm.stopPrank();

        // Verify purchase
        ShopManager.Item memory item = shop.getItem(itemId);
        assertFalse(item.isAvailable); // Item should now be unavailable
        assertEq(shop.ownerOf(itemId), user1); // user1 owns the NFT
        assertEq(token.balanceOf(address(shop)), price); // Shop holds the tokens
        assertEq(token.balanceOf(user1), 0); // user1 spent their tokens
        assertEq(shop.tokenURI(itemId), "ipfs://test-uri");
    }

    function testRemoveItem() public {
        uint256 price = 10 * 10 ** 18;
        // List item
        uint256 itemId = shop.listItem(
            "Test Item",
            "Test Description",
            price,
            "ipfs://test-uri"
        );

        // Remove item (only owner can do this)
        // No need to prank owner
        shop.removeItem(itemId);

        // Verify removal
        ShopManager.Item memory item = shop.getItem(itemId);
        assertFalse(item.isAvailable);

        // Check that trying to get ownerOf or tokenURI reverts for removed (but minted metadata) items
        // Note: The NFT isn't minted until purchase, so ownerOf will revert anyway if not purchased.
        // If we wanted to test removing *after* purchase, the logic would differ.
    }

    function testWithdrawBurnedTokens() public {
        uint256 price = 10 * 10 ** 18; // 10 tokens
        // List item
        uint256 itemId = shop.listItem(
            "Test Item",
            "Test Description",
            price,
            "ipfs://test-uri"
        );

        // --- Get tokens to user1 ---
        // Owner claims tokens
        token.claim(); // Owner has 10 tokens at timestamp 1000
        // Transfer tokens to user1
        token.transfer(user1, price);

        // Initial supply
        uint256 initialSupply = token.totalSupply();

        // --- User1 purchases ---
        vm.startPrank(user1);
        token.approve(address(shop), price);
        shop.purchaseItem(itemId);
        vm.stopPrank();

        // --- Verification ---
        assertEq(token.balanceOf(address(shop)), price); // Shop has 10 tokens

        // Withdraw and burn tokens (by owner)
        shop.withdrawBurnedTokens();

        // Verify tokens were burned
        assertEq(token.totalSupply(), initialSupply - price); // Total supply decreased
        assertEq(token.balanceOf(address(shop)), 0); // Shop balance is zero
    }

    function test_RevertWhen_ItemNotAvailable() public {
        uint256 price = 10 * 10 ** 18;
        // List item
        uint256 itemId = shop.listItem(
            "Test Item",
            "Test Description",
            price,
            "ipfs://test-uri"
        );
        // Remove item
        shop.removeItem(itemId);

        // --- Get tokens to user1 ---
        // Owner claims tokens
        token.claim(); // Owner has 10 tokens at timestamp 1000
        // Transfer tokens to user1
        token.transfer(user1, price);
        // --- Attempt purchase ---
        vm.startPrank(user1);
        token.approve(address(shop), price);
        vm.expectRevert("Item not available");
        shop.purchaseItem(itemId);
        vm.stopPrank();
    }

    function testTokensBurnedAfterPurchase() public {
        // List an item
        uint256 itemId = shop.listItem(
            "Test Item",
            "Test Description",
            10 * 10 ** 18,
            "ipfs://test-uri"
        );

        // Get tokens to user1
        token.claim();
        token.transfer(user1, 10 * 10 ** 18);

        // Initial token supply
        uint256 initialSupply = token.totalSupply();

        // User1 purchases item
        vm.startPrank(user1);
        token.approve(address(shop), 10 * 10 ** 18);
        shop.purchaseItem(itemId);
        vm.stopPrank();

        // Verify tokens were burned (total supply decreased)
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(address(shop)), 10 * 10 ** 18); // Tokens are held by shop

        // Owner withdraws and burns tokens
        shop.withdrawBurnedTokens();
        assertEq(token.totalSupply(), initialSupply - (10 * 10 ** 18));
        assertEq(token.balanceOf(address(shop)), 0);
    }
}
