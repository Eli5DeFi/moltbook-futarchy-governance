// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title FutarchyGovernance
 * @dev Prediction market-based governance for AI agent DAOs
 * "Vote on values, bet on beliefs"
 */
contract FutarchyGovernance is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ============ STRUCTS ============

    struct Proposal {
        uint256 id;
        string title;
        string description;
        address proposer;
        uint256 deadline;
        uint256 executionDeadline;
        uint256 minStake;
        bytes32 outcomeMetric;
        ProposalStatus status;
        Market yesMarket;    // "If we implement this"
        Market noMarket;     // "If we don't implement this"
        bytes executionData; // For contract calls
        bool executed;
        uint256 actualOutcome; // Measured result after execution
    }

    struct Market {
        uint256 totalYesStakes;
        uint256 totalNoStakes;
        uint256 totalStaked;
        mapping(address => UserPosition) positions;
        uint256 participantCount;
    }

    struct UserPosition {
        uint256 yesStake;
        uint256 noStake;
        bool claimed;
    }

    struct ProductDeliverable {
        string deliverableType; // "software|content|infrastructure"
        string description;
        string repository;
        string demoLink;
        uint256[] milestones; // Timestamp milestones
        bool[] milestoneCompleted;
        string[] successMetrics;
    }

    enum ProposalStatus {
        Active,
        Voting,
        Pending,
        Executed,
        Failed,
        Expired
    }

    // ============ STATE VARIABLES ============

    IERC20 public governanceToken;
    address public reputationOracle;
    address public bankrIntegration;

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => ProductDeliverable) public deliverables;
    uint256 public proposalCount;

    uint256 public constant VOTING_DURATION = 7 days;
    uint256 public constant EXECUTION_DELAY = 2 days;
    uint256 public constant MIN_STAKE = 100e18; // 100 governance tokens
    uint256 public constant REWARD_PERCENTAGE = 10; // 10% of losing side

    // Performance tracking
    uint256 public totalProposals;
    uint256 public successfulProposals;
    uint256 public totalPredictionAccuracy;

    // ============ EVENTS ============

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        uint256 deadline
    );

    event StakePlaced(
        uint256 indexed proposalId,
        address indexed staker,
        bool position,
        uint256 amount
    );

    event ProposalExecuted(
        uint256 indexed proposalId,
        bool success,
        uint256 actualOutcome
    );

    event RewardsDistributed(
        uint256 indexed proposalId,
        uint256 totalReward
    );

    // ============ MODIFIERS ============

    modifier onlyReputationOracle() {
        require(msg.sender == reputationOracle, "Only reputation oracle");
        _;
    }

    modifier validProposal(uint256 proposalId) {
        require(proposalId < proposalCount, "Invalid proposal ID");
        _;
    }

    // ============ CONSTRUCTOR ============

    constructor(
        address _governanceToken,
        address _reputationOracle,
        address _bankrIntegration
    ) {
        governanceToken = IERC20(_governanceToken);
        reputationOracle = _reputationOracle;
        bankrIntegration = _bankrIntegration;
    }

    // ============ PROPOSAL CREATION ============

    function createProposal(
        string memory title,
        string memory description,
        bytes32 outcomeMetric,
        bytes memory executionData,
        ProductDeliverable memory deliverable
    ) external nonReentrant returns (uint256) {
        // Check reputation and stake
        require(_hasMinReputation(msg.sender), "Insufficient reputation");
        governanceToken.safeTransferFrom(msg.sender, address(this), MIN_STAKE);

        uint256 proposalId = proposalCount++;
        
        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.title = title;
        proposal.description = description;
        proposal.proposer = msg.sender;
        proposal.deadline = block.timestamp + VOTING_DURATION;
        proposal.executionDeadline = proposal.deadline + EXECUTION_DELAY;
        proposal.minStake = MIN_STAKE;
        proposal.outcomeMetric = outcomeMetric;
        proposal.status = ProposalStatus.Active;
        proposal.executionData = executionData;

        // Store deliverable requirements
        deliverables[proposalId] = deliverable;

        emit ProposalCreated(proposalId, msg.sender, title, proposal.deadline);
        
        return proposalId;
    }

    // ============ PREDICTION MARKET ============

    function placeBet(
        uint256 proposalId,
        bool position, // true = YES, false = NO
        uint256 amount
    ) external validProposal(proposalId) nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Active, "Proposal not active");
        require(block.timestamp < proposal.deadline, "Voting ended");
        require(amount > 0, "Amount must be > 0");

        Market storage market = proposal.yesMarket; // Same market, different positions
        UserPosition storage userPos = market.positions[msg.sender];

        governanceToken.safeTransferFrom(msg.sender, address(this), amount);

        if (position) {
            userPos.yesStake += amount;
            market.totalYesStakes += amount;
        } else {
            userPos.noStake += amount;
            market.totalNoStakes += amount;
        }

        market.totalStaked += amount;
        
        // Increment participant count if first bet
        if (userPos.yesStake + userPos.noStake == amount) {
            market.participantCount++;
        }

        emit StakePlaced(proposalId, msg.sender, position, amount);
    }

    // ============ PROPOSAL EXECUTION ============

    function executeProposal(uint256 proposalId) external validProposal(proposalId) nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Active, "Wrong status");
        require(block.timestamp >= proposal.deadline, "Voting still active");
        require(block.timestamp <= proposal.executionDeadline, "Execution expired");
        require(!proposal.executed, "Already executed");

        // Determine winning side based on total stakes
        Market storage market = proposal.yesMarket;
        bool shouldExecute = market.totalYesStakes > market.totalNoStakes;

        proposal.status = shouldExecute ? ProposalStatus.Executed : ProposalStatus.Failed;
        proposal.executed = true;
        totalProposals++;

        bool success = false;
        if (shouldExecute && proposal.executionData.length > 0) {
            // Execute the proposal (contract call)
            (success,) = address(this).call(proposal.executionData);
            if (success) {
                successfulProposals++;
            }
        }

        emit ProposalExecuted(proposalId, success, 0);
        
        // Start outcome measurement period
        _startOutcomeMeasurement(proposalId);
    }

    function reportOutcome(
        uint256 proposalId,
        uint256 actualOutcome
    ) external onlyReputationOracle validProposal(proposalId) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.executed, "Not executed");
        
        proposal.actualOutcome = actualOutcome;
        
        // Calculate prediction accuracy
        Market storage market = proposal.yesMarket;
        uint256 predictedOutcome = market.totalYesStakes > market.totalNoStakes ? 1 : 0;
        uint256 accuracy = actualOutcome == predictedOutcome ? 100 : 0;
        
        totalPredictionAccuracy = (totalPredictionAccuracy + accuracy) / 2; // Running average
        
        // Distribute rewards to winners
        _distributeRewards(proposalId);
    }

    // ============ REWARD DISTRIBUTION ============

    function _distributeRewards(uint256 proposalId) internal {
        Proposal storage proposal = proposals[proposalId];
        Market storage market = proposal.yesMarket;
        
        uint256 totalReward = market.totalStaked * REWARD_PERCENTAGE / 100;
        bool yesWon = proposal.actualOutcome > 0;
        
        uint256 winningPool = yesWon ? market.totalYesStakes : market.totalNoStakes;
        
        if (winningPool == 0) return; // No winners
        
        // Reward proportional to stake
        for (uint256 i = 0; i < market.participantCount; i++) {
            // Note: In production, we'd need a way to iterate through participants
            // This is a simplified version
        }
        
        emit RewardsDistributed(proposalId, totalReward);
    }

    function claimRewards(uint256 proposalId) external validProposal(proposalId) nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        Market storage market = proposal.yesMarket;
        UserPosition storage userPos = market.positions[msg.sender];
        
        require(!userPos.claimed, "Already claimed");
        require(proposal.actualOutcome > 0, "Outcome not reported");
        
        bool yesWon = proposal.actualOutcome > 0;
        uint256 userStake = yesWon ? userPos.yesStake : userPos.noStake;
        
        if (userStake > 0) {
            uint256 reward = _calculateUserReward(proposalId, msg.sender);
            userPos.claimed = true;
            governanceToken.safeTransfer(msg.sender, userStake + reward);
        }
    }

    // ============ INTERNAL FUNCTIONS ============

    function _hasMinReputation(address agent) internal view returns (bool) {
        // Check with reputation oracle
        (bool success, bytes memory data) = reputationOracle.staticcall(
            abi.encodeWithSignature("hasMinReputation(address)", agent)
        );
        return success && abi.decode(data, (bool));
    }

    function _startOutcomeMeasurement(uint256 proposalId) internal {
        // Notify reputation oracle to start measuring outcomes
        (bool success,) = reputationOracle.call(
            abi.encodeWithSignature("startOutcomeMeasurement(uint256)", proposalId)
        );
        require(success, "Failed to start measurement");
    }

    function _calculateUserReward(uint256 proposalId, address user) internal view returns (uint256) {
        Proposal storage proposal = proposals[proposalId];
        Market storage market = proposal.yesMarket;
        UserPosition storage userPos = market.positions[user];
        
        bool yesWon = proposal.actualOutcome > 0;
        uint256 userStake = yesWon ? userPos.yesStake : userPos.noStake;
        uint256 winningPool = yesWon ? market.totalYesStakes : market.totalNoStakes;
        
        if (winningPool == 0) return 0;
        
        uint256 totalReward = market.totalStaked * REWARD_PERCENTAGE / 100;
        return (userStake * totalReward) / winningPool;
    }

    // ============ VIEW FUNCTIONS ============

    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    function getMarketInfo(uint256 proposalId) external view returns (
        uint256 totalYesStakes,
        uint256 totalNoStakes,
        uint256 totalStaked,
        uint256 participantCount
    ) {
        Market storage market = proposals[proposalId].yesMarket;
        return (
            market.totalYesStakes,
            market.totalNoStakes,
            market.totalStaked,
            market.participantCount
        );
    }

    function getUserPosition(uint256 proposalId, address user) external view returns (
        uint256 yesStake,
        uint256 noStake,
        bool claimed
    ) {
        UserPosition storage pos = proposals[proposalId].yesMarket.positions[user];
        return (pos.yesStake, pos.noStake, pos.claimed);
    }

    function getGovernanceMetrics() external view returns (
        uint256 proposalQuality,
        uint256 participationRate,
        uint256 outcomeAccuracy
    ) {
        uint256 quality = totalProposals > 0 ? (successfulProposals * 100) / totalProposals : 0;
        uint256 accuracy = totalPredictionAccuracy;
        
        return (quality, 0, accuracy); // TODO: Calculate participation rate
    }
}