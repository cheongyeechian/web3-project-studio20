// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Voting.sol";
import "../src/Token.sol";

contract VotingTest is Test {
    VotingManager public voting;
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

        // Deploy voting contract
        voting = new VotingManager(address(token));

        // Label addresses for better trace output
        vm.label(owner, "Owner (Test Contract)");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(address(token), "Token");
        vm.label(address(voting), "Voting");
    }

    function testCreateProject() public {
        string memory name = "Test Project";
        string memory description = "Test Description";
        // Ensure start time is after current block.timestamp (which is 1000 due to warp)
        uint256 startTime = block.timestamp + 1 days;
        uint256 duration = 7 days;

        uint256 projectId = voting.createProject(
            name,
            description,
            startTime,
            duration
        );
        assertEq(projectId, 0); // First project ID is 0

        VotingManager.Project memory project = voting.getProject(projectId);
        assertEq(project.name, name);
        assertEq(project.description, description);
        assertEq(project.startTime, startTime);
        assertEq(project.endTime, startTime + duration);
        assertTrue(project.isActive); // Should be active initially
        assertFalse(project.isFinalized);
    }

    function testVoting() public {
        // Create project starting in 1 day, lasting 7 days
        uint256 startTime = block.timestamp + 1 days;
        uint256 duration = 7 days;
        uint256 projectId = voting.createProject(
            "Test Project",
            "Test Description",
            startTime,
            duration
        );

        // --- Get tokens to users (need 5 each, total 10) ---
        // Owner claims tokens
        token.claim(); // Owner has 10 tokens at timestamp 1000
        assertEq(token.balanceOf(owner), 10 * 10 ** 18);

        // Transfer 5 tokens to user1, 5 to user2
        token.transfer(user1, 5 * 10 ** 18);
        token.transfer(user2, 5 * 10 ** 18);
        assertEq(token.balanceOf(user1), 5 * 10 ** 18);
        assertEq(token.balanceOf(user2), 5 * 10 ** 18);
        assertEq(token.balanceOf(owner), 0); // Owner transferred all claimed tokens

        // Warp time to the middle of the voting period
        vm.warp(startTime + duration / 2);

        // User1 votes with 5 tokens
        vm.startPrank(user1);
        token.approve(address(voting), 5 * 10 ** 18);
        voting.vote(projectId, 5 * 10 ** 18);
        vm.stopPrank();

        // User2 votes with 5 tokens
        vm.startPrank(user2);
        token.approve(address(voting), 5 * 10 ** 18);
        voting.vote(projectId, 5 * 10 ** 18);
        vm.stopPrank();

        // Check voting results
        VotingManager.Project memory project = voting.getProject(projectId);
        assertEq(project.totalVotes, 10 * 10 ** 18); // 5 + 5
        assertEq(token.balanceOf(address(voting)), 10 * 10 ** 18); // Contract holds staked tokens

        (uint256 user1Votes, , ) = voting.votes(projectId, user1);
        (uint256 user2Votes, , ) = voting.votes(projectId, user2);
        assertEq(user1Votes, 5 * 10 ** 18);
        assertEq(user2Votes, 5 * 10 ** 18);
    }

    function testProjectFinalization() public {
        // Create project
        uint256 startTime = block.timestamp + 1 days;
        uint256 duration = 7 days;
        uint256 projectId = voting.createProject(
            "Test Project",
            "Test Description",
            startTime,
            duration
        );

        // --- Get tokens to users (user1 needs 6, user2 needs 4, total 10) ---
        token.claim(); // Owner has 10 tokens at timestamp 1000
        token.transfer(user1, 6 * 10 ** 18);
        token.transfer(user2, 4 * 10 ** 18);

        // Warp to voting period
        vm.warp(startTime + duration / 2);

        // Users vote
        vm.startPrank(user1);
        token.approve(address(voting), 6 * 10 ** 18);
        voting.vote(projectId, 6 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(voting), 4 * 10 ** 18);
        voting.vote(projectId, 4 * 10 ** 18);
        vm.stopPrank();

        // Warp to after end of voting period
        vm.warp(startTime + duration + 1);

        // Finalize project (by owner)
        voting.finalizeProject(projectId);

        // Check project status
        VotingManager.Project memory project = voting.getProject(projectId);
        assertTrue(project.isFinalized);
        assertFalse(project.isActive); // Should be inactive after finalization
        assertEq(project.totalVotes, 10 * 10 ** 18); // 6 + 4
        assertEq(project.winner, user1); // User1 had more votes
    }

    function testUnstaking() public {
        // Create project
        uint256 startTime = block.timestamp + 1 days;
        uint256 duration = 7 days;
        uint256 projectId = voting.createProject(
            "Test Project",
            "Test Description",
            startTime,
            duration
        );

        // --- Get tokens to user1 (needs 5) ---
        token.claim(); // Owner has 10 tokens at timestamp 1000

        // Transfer 5 tokens to user1 for voting
        token.transfer(user1, 5 * 10 ** 18);

        // Transfer 5 tokens to the voting contract to cover potential rewards
        token.transfer(address(voting), 5 * 10 ** 18);

        // Warp to voting period
        vm.warp(startTime + duration / 2);

        // User1 votes
        vm.startPrank(user1);
        token.approve(address(voting), 5 * 10 ** 18);
        voting.vote(projectId, 5 * 10 ** 18);
        vm.stopPrank();

        // Warp to after end of voting period
        vm.warp(startTime + duration + 1);

        // Finalize project (required for unstaking)
        voting.finalizeProject(projectId);

        // Check if user1 is the winner (it will be since only user1 voted)
        VotingManager.Project memory project = voting.getProject(projectId);
        assertTrue(project.winner == user1, "User1 should be the winner");

        // Get user1's unstakeable balance (should be 2x since they're the winner)
        uint256 unstakeableBalance = voting.getUnstakeableBalance(
            projectId,
            user1
        );
        assertEq(
            unstakeableBalance,
            10 * 10 ** 18,
            "Winner should get 2x tokens back"
        );

        // User1 unstakes tokens
        vm.startPrank(user1);
        voting.unstakeTokens(projectId);
        vm.stopPrank();

        // Check balances - user1 should get 2x tokens back as the winner
        assertEq(
            token.balanceOf(user1),
            10 * 10 ** 18,
            "User1 should have 10 tokens after unstaking (2x reward)"
        );
        assertEq(
            token.balanceOf(address(voting)),
            0,
            "Voting contract should have 0 tokens left"
        );

        // Check vote record
        (uint256 user1VotesAfter, , bool hasUnstaked) = voting.votes(
            projectId,
            user1
        );
        assertEq(
            user1VotesAfter,
            5 * 10 ** 18,
            "User1 votes should be recorded as 5"
        );
        assertTrue(hasUnstaked, "User1's vote should be marked as unstaked");
    }

    function testWinnerGets2xReward() public {
        // Create project
        uint256 startTime = block.timestamp + 1 days;
        uint256 duration = 7 days;
        uint256 projectId = voting.createProject(
            "Test Project",
            "Test Description",
            startTime,
            duration
        );

        // Get tokens for rewards and voting
        token.claim(); // Owner has 10 tokens at timestamp 1000

        // Need more tokens to cover 2x reward
        vm.warp(1000 + 1 days); // Advance time to be able to claim again
        token.claim(); // Owner claims another 10 tokens
        vm.warp(1000 + 2 days); // Advance time to be able to claim again
        token.claim(); // Owner claims another 10 tokens

        // Now owner has 30 tokens total
        // Transfer 20 tokens to voting contract for rewards
        uint256 initialSupply = 20 * 10 ** 18;
        token.transfer(address(voting), initialSupply);

        // Transfer 6 tokens to user1, 4 to user2 (user1 will win)
        token.transfer(user1, 6 * 10 ** 18);
        token.transfer(user2, 4 * 10 ** 18);

        // Warp to voting period (restore the timeline for the test)
        vm.warp(startTime + duration / 2);

        // Users vote
        vm.startPrank(user1);
        token.approve(address(voting), 6 * 10 ** 18);
        voting.vote(projectId, 6 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(voting), 4 * 10 ** 18);
        voting.vote(projectId, 4 * 10 ** 18);
        vm.stopPrank();

        // Tokens in contract = initial 20 + 6 from user1 + 4 from user2 = 30
        assertEq(
            token.balanceOf(address(voting)),
            initialSupply + 10 * 10 ** 18
        );

        // Warp to after end of voting period
        vm.warp(startTime + duration + 1);

        // Finalize project (required for unstaking)
        voting.finalizeProject(projectId);

        // Check the winner is user1
        VotingManager.Project memory project = voting.getProject(projectId);
        assertEq(project.winner, user1);

        // Check the unstakeable balance for user1 (should be 2x)
        uint256 user1UnstakeableBalance = voting.getUnstakeableBalance(
            projectId,
            user1
        );
        assertEq(user1UnstakeableBalance, 12 * 10 ** 18); // 6 * 2 = 12

        // Check the unstakeable balance for user2 (should be 1x)
        uint256 user2UnstakeableBalance = voting.getUnstakeableBalance(
            projectId,
            user2
        );
        assertEq(user2UnstakeableBalance, 4 * 10 ** 18); // 4 * 1 = 4

        // User1 (winner) unstakes tokens and gets 2x reward
        vm.startPrank(user1);
        voting.unstakeTokens(projectId);
        vm.stopPrank();

        // Check balances - user1 started with 0 after voting and should now have 12 tokens (2x reward)
        assertEq(token.balanceOf(user1), 12 * 10 ** 18); // 6 * 2 = 12

        // User2 (non-winner) unstakes tokens and gets 1x back
        vm.startPrank(user2);
        voting.unstakeTokens(projectId);
        vm.stopPrank();

        // Check balances - user2 started with 0 after voting and should now have 4 tokens back
        assertEq(token.balanceOf(user2), 4 * 10 ** 18); // 4 * 1 = 4
    }

    function testRevertWhenUnstakingTwice() public {
        // Create project
        uint256 startTime = block.timestamp + 1 days;
        uint256 duration = 7 days;
        uint256 projectId = voting.createProject(
            "Test Project",
            "Test Description",
            startTime,
            duration
        );

        // Get tokens
        token.claim();
        token.transfer(user1, 5 * 10 ** 18);

        // Transfer 5 tokens to the voting contract to cover potential rewards
        token.transfer(address(voting), 5 * 10 ** 18);

        // Warp to voting period
        vm.warp(startTime + duration / 2);

        // User1 votes
        vm.startPrank(user1);
        token.approve(address(voting), 5 * 10 ** 18);
        voting.vote(projectId, 5 * 10 ** 18);
        vm.stopPrank();

        // Warp to after end of voting period
        vm.warp(startTime + duration + 1);

        // Finalize project
        voting.finalizeProject(projectId);

        // User1 unstakes tokens once
        vm.startPrank(user1);
        voting.unstakeTokens(projectId);

        // Try to unstake again
        vm.expectRevert("Already unstaked");
        voting.unstakeTokens(projectId);
        vm.stopPrank();
    }

    function testRevertWhenVotingWithZeroTokens() public {
        uint256 startTime = block.timestamp + 1 days;
        uint256 duration = 7 days;
        uint256 projectId = voting.createProject(
            "Test Project",
            "Test Description",
            startTime,
            duration
        );

        // Warp to voting period
        vm.warp(startTime + duration / 2);

        // Try to vote with 0 tokens
        vm.startPrank(user1);
        token.approve(address(voting), 0);
        vm.expectRevert("Amount must be positive");
        voting.vote(projectId, 0);
        vm.stopPrank();
    }

    function testRevertWhenVotingAfterPeriodEnds() public {
        uint256 startTime = block.timestamp + 1 days;
        uint256 duration = 7 days;
        uint256 projectId = voting.createProject(
            "Test Project",
            "Test Description",
            startTime,
            duration
        );

        // Get tokens to user1
        token.claim();
        token.transfer(user1, 5 * 10 ** 18);

        // Warp to after voting period
        vm.warp(startTime + duration + 1);

        // Try to vote after period ends
        vm.startPrank(user1);
        token.approve(address(voting), 5 * 10 ** 18);
        vm.expectRevert(VotingManager.InvalidVotingPeriod.selector);
        voting.vote(projectId, 5 * 10 ** 18);
        vm.stopPrank();
    }

    function testRevertWhenCreatingInvalidProject() public {
        // Try to create project with start time in the past
        vm.expectRevert("Start time must be in the future");
        voting.createProject(
            "Invalid Project",
            "Test Description",
            block.timestamp - 1,
            7 days
        );

        // Try to create project with zero duration
        vm.expectRevert("Duration must be positive");
        voting.createProject(
            "Invalid Project",
            "Test Description",
            block.timestamp + 1 days,
            0
        );
    }

    function testRevertWhenUnstakingFromNonExistentProject() public {
        uint256 nonExistentProjectId = 999;

        vm.startPrank(user1);
        vm.expectRevert("Project does not exist");
        voting.unstakeTokens(nonExistentProjectId);
        vm.stopPrank();
    }

    function testRevertWhenUnstakingWithoutFinalization() public {
        // Create project
        uint256 startTime = block.timestamp + 1 days;
        uint256 duration = 7 days;
        uint256 projectId = voting.createProject(
            "Test Project",
            "Test Description",
            startTime,
            duration
        );

        // Get tokens for user1
        token.claim();
        token.transfer(user1, 5 * 10 ** 18);

        // Warp to voting period
        vm.warp(startTime + duration / 2);

        // User1 votes
        vm.startPrank(user1);
        token.approve(address(voting), 5 * 10 ** 18);
        voting.vote(projectId, 5 * 10 ** 18);
        vm.stopPrank();

        // Warp to after end of voting period
        vm.warp(startTime + duration + 1);

        // Try to unstake without finalizing
        vm.startPrank(user1);
        vm.expectRevert("Project not finalized");
        voting.unstakeTokens(projectId);
        vm.stopPrank();
    }
}
