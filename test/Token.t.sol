// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Token.sol";

contract TokenTest is Test {
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

        vm.warp(1000);

        token = new Token(1_000_000, trustedForwarder);

        vm.label(owner, "Owner (Test Contract)");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(address(token), "Token");
    }

    function testInitialSupply() public view {
        assertEq(token.totalSupply(), 1_000_000 * 10 ** 18);
        assertEq(token.balanceOf(address(token)), 1_000_000 * 10 ** 18);
    }

    function testClaim() public {
        token.claim();
        assertEq(token.balanceOf(owner), 10 * 10 ** 18);
        assertEq(token.lastClaimedTime(owner), block.timestamp);

        vm.expectRevert("Claim cooldown active");
        token.claim();

        vm.warp(block.timestamp + 24 hours + 1);

        token.claim();
        assertEq(token.balanceOf(owner), 20 * 10 ** 18);
        assertEq(token.lastClaimedTime(owner), block.timestamp);
    }

    function testMultipleUsersClaim() public {
        // First claims
        vm.prank(user1);
        token.claim();
        assertEq(token.balanceOf(user1), 10 * 10 ** 18);
        uint256 user1FirstClaimTime = block.timestamp;
        assertEq(token.lastClaimedTime(user1), user1FirstClaimTime);

        vm.prank(user2);
        token.claim();
        assertEq(token.balanceOf(user2), 10 * 10 ** 18);
        uint256 user2FirstClaimTime = block.timestamp;
        assertEq(token.lastClaimedTime(user2), user2FirstClaimTime);

        // Immediate claim attempts (should fail)
        vm.prank(user1);
        vm.expectRevert("Claim cooldown active");
        token.claim();

        vm.prank(user2);
        vm.expectRevert("Claim cooldown active");
        token.claim();

        // Wait for user1's cooldown
        vm.warp(user1FirstClaimTime + 24 hours + 1);

        // User1 claims again
        vm.prank(user1);
        token.claim();
        assertEq(token.balanceOf(user1), 20 * 10 ** 18);
        assertEq(token.lastClaimedTime(user1), block.timestamp);

        // User2 claims again (should succeed since enough time has passed)
        vm.prank(user2);
        token.claim();
        assertEq(token.balanceOf(user2), 20 * 10 ** 18);
        assertEq(token.lastClaimedTime(user2), block.timestamp);
    }
}
