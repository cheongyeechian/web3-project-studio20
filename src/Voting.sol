// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract VotingManager is Ownable, ReentrancyGuard {
    // State variables
    IERC20 public token; // The ERC20 token used for voting
    uint256 private _projectIds;

    // Structs
    struct Project {
        string name;
        string description;
        uint256 startTime;
        uint256 endTime;
        uint256 totalVotes;
        bool isActive;
        bool isFinalized;
        address winner;
    }

    struct Vote {
        uint256 amount;
        uint256 timestamp;
        bool hasUnstaked;
    }

    // Mappings
    mapping(uint256 => Project) public projects;
    mapping(uint256 => mapping(address => Vote)) public votes;
    mapping(address => uint256) public totalStakedTokens;
    mapping(uint256 => address[]) public projectVoters;

    // Events
    event ProjectCreated(
        uint256 indexed projectId,
        string name,
        uint256 startTime,
        uint256 endTime
    );
    event VoteCast(
        uint256 indexed projectId,
        address indexed voter,
        uint256 amount
    );
    event ProjectFinalized(
        uint256 indexed projectId,
        address winner,
        uint256 totalVotes
    );
    event TokensUnstaked(address indexed voter, uint256 amount, bool isWinner);

    // Custom errors
    error ProjectNotActive();
    error ProjectAlreadyFinalized();
    error InvalidVotingPeriod();
    error InsufficientAllowance();
    error NoVotesCast();
    error AlreadyUnstaked();
    error ProjectNotFinalized();

    // Modifiers
    modifier projectExists(uint256 projectId) {
        require(projectId < _projectIds, "Project does not exist");
        _;
    }

    modifier projectActive(uint256 projectId) {
        if (!projects[projectId].isActive) revert ProjectNotActive();
        if (projects[projectId].isFinalized) revert ProjectAlreadyFinalized();
        if (
            block.timestamp < projects[projectId].startTime ||
            block.timestamp > projects[projectId].endTime
        ) {
            revert InvalidVotingPeriod();
        }
        _;
    }

    constructor(address _token) Ownable(msg.sender) {
        require(_token != address(0), "Invalid token address");
        token = IERC20(_token);
    }

    // Admin function to create a new project
    function createProject(
        string memory name,
        string memory description,
        uint256 startTime,
        uint256 duration
    ) external onlyOwner returns (uint256) {
        require(
            startTime > block.timestamp,
            "Start time must be in the future"
        );
        require(duration > 0, "Duration must be positive");

        uint256 projectId = _projectIds;
        uint256 endTime = startTime + duration;

        projects[projectId] = Project({
            name: name,
            description: description,
            startTime: startTime,
            endTime: endTime,
            totalVotes: 0,
            isActive: true,
            isFinalized: false,
            winner: address(0)
        });

        _projectIds += 1;

        emit ProjectCreated(projectId, name, startTime, endTime);
        return projectId;
    }

    // User function to vote on a project
    function vote(
        uint256 projectId,
        uint256 amount
    ) external nonReentrant projectExists(projectId) projectActive(projectId) {
        require(amount > 0, "Amount must be positive");

        // Check if user has enough token allowance
        if (token.allowance(msg.sender, address(this)) < amount) {
            revert InsufficientAllowance();
        }

        // Transfer tokens from voter to contract
        require(
            token.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );

        // Update vote tracking
        if (votes[projectId][msg.sender].amount == 0) {
            projectVoters[projectId].push(msg.sender);
        }

        votes[projectId][msg.sender].amount += amount;
        votes[projectId][msg.sender].timestamp = block.timestamp;
        votes[projectId][msg.sender].hasUnstaked = false;
        totalStakedTokens[msg.sender] += amount;
        projects[projectId].totalVotes += amount;

        emit VoteCast(projectId, msg.sender, amount);
    }

    // Admin function to finalize a project and determine winner
    function finalizeProject(
        uint256 projectId
    ) external onlyOwner projectExists(projectId) {
        Project storage project = projects[projectId];
        require(block.timestamp > project.endTime, "Voting period not ended");
        require(!project.isFinalized, "Project already finalized");
        require(project.totalVotes > 0, "No votes cast");

        project.isActive = false;
        project.isFinalized = true;

        // Find the winner (address with most votes)
        address currentWinner = address(0);
        uint256 highestVotes = 0;

        for (uint256 i = 0; i < projectVoters[projectId].length; i++) {
            address voter = projectVoters[projectId][i];
            uint256 voterVotes = votes[projectId][voter].amount;

            if (voterVotes > highestVotes) {
                highestVotes = voterVotes;
                currentWinner = voter;
            }
        }

        project.winner = currentWinner;
        emit ProjectFinalized(projectId, currentWinner, project.totalVotes);
    }

    // View function to get project details
    function getProject(
        uint256 projectId
    ) external view projectExists(projectId) returns (Project memory) {
        return projects[projectId];
    }

    // View function to get total number of projects
    function getTotalProjects() external view returns (uint256) {
        return _projectIds;
    }

    // User function to unstake tokens from completed projects
    function unstakeTokens(
        uint256 projectId
    ) external nonReentrant projectExists(projectId) {
        Project storage project = projects[projectId];
        require(block.timestamp > project.endTime, "Voting period not ended");
        require(project.isFinalized, "Project not finalized");

        Vote storage userVote = votes[projectId][msg.sender];
        uint256 amount = userVote.amount;

        require(amount > 0, "No tokens to unstake");
        require(!userVote.hasUnstaked, "Already unstaked");

        // Mark as unstaked to prevent multiple claims
        userVote.hasUnstaked = true;
        totalStakedTokens[msg.sender] -= amount;

        // Calculate amount to return based on winner status
        uint256 returnAmount = amount;
        bool isWinner = (msg.sender == project.winner);

        // Winner gets 2x their staked amount
        if (isWinner) {
            returnAmount = amount * 2;
        }

        // Transfer tokens back to user
        require(
            token.transfer(msg.sender, returnAmount),
            "Token transfer failed"
        );

        emit TokensUnstaked(msg.sender, returnAmount, isWinner);
    }

    // View function to check unstakeable balance for a project
    function getUnstakeableBalance(
        uint256 projectId,
        address voter
    ) external view projectExists(projectId) returns (uint256) {
        Project storage project = projects[projectId];
        if (block.timestamp <= project.endTime || !project.isFinalized) {
            return 0;
        }

        Vote storage userVote = votes[projectId][voter];
        if (userVote.hasUnstaked) {
            return 0;
        }

        uint256 baseAmount = userVote.amount;
        if (voter == project.winner) {
            return baseAmount * 2;
        }
        return baseAmount;
    }

    // View function to get user's total staked tokens
    function getUserTotalStaked(address voter) external view returns (uint256) {
        return totalStakedTokens[voter];
    }
}
