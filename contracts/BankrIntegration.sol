// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title BankrIntegration
 * @dev Economic layer for Moltbook Futarchy governance
 * Handles staking, rewards, treasury management, and economic incentives
 */
contract BankrIntegration is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ============ STRUCTS ============

    struct StakeInfo {
        uint256 amount;
        uint256 lockTime;
        uint256 unlockTime;
        bool withdrawn;
        uint256 proposalId;
        StakeType stakeType;
    }

    struct RewardDistribution {
        uint256 proposalId;
        uint256 totalAmount;
        uint256 distributedAmount;
        uint256 participantCount;
        mapping(address => uint256) userRewards;
        mapping(address => bool) claimed;
        bool finalized;
    }

    struct TreasuryStats {
        uint256 totalDeposits;
        uint256 totalWithdrawals;
        uint256 totalRewardsDistributed;
        uint256 activeStakes;
        uint256 lockedAmount;
    }

    struct EconomicMetrics {
        uint256 participationRate;
        uint256 avgStakeSize;
        uint256 treasuryHealth;
        uint256 rewardEfficiency;
    }

    enum StakeType {
        Proposal,
        Governance,
        Insurance
    }

    // ============ STATE VARIABLES ============

    IERC20 public governanceToken;
    address public futarchyGovernance;
    address public reputationOracle;

    mapping(address => mapping(uint256 => StakeInfo)) public stakes; // user => stakeId => stake
    mapping(address => uint256) public userStakeCount;
    mapping(uint256 => RewardDistribution) public rewards; // proposalId => rewards

    TreasuryStats public treasury;
    uint256 public totalParticipants;

    // Economic parameters
    uint256 public constant BASE_STAKE_REQUIREMENT = 100e18; // 100 tokens
    uint256 public constant MAX_LOCK_DURATION = 365 days;
    uint256 public constant REWARD_BOOST_MULTIPLIER = 150; // 1.5x for longer locks
    uint256 public constant TREASURY_FEE = 2; // 2% fee on rewards
    uint256 public constant INSURANCE_POOL_RATIO = 10; // 10% goes to insurance

    // Dynamic parameters (can be adjusted by governance)
    uint256 public stakingMultiplier = 100; // 1.0x baseline
    uint256 public participationBonus = 10; // 10% bonus for active participants
    uint256 public qualityThreshold = 80; // 80% success rate threshold

    // ============ EVENTS ============

    event StakePlaced(
        address indexed user,
        uint256 indexed stakeId,
        uint256 amount,
        uint256 lockTime,
        StakeType stakeType
    );

    event StakeWithdrawn(
        address indexed user,
        uint256 indexed stakeId,
        uint256 amount,
        uint256 penalty
    );

    event RewardsDistributed(
        uint256 indexed proposalId,
        uint256 totalAmount,
        uint256 participantCount
    );

    event RewardClaimed(
        address indexed user,
        uint256 indexed proposalId,
        uint256 amount
    );

    event EconomicParametersUpdated(
        uint256 stakingMultiplier,
        uint256 participationBonus,
        uint256 qualityThreshold
    );

    // ============ MODIFIERS ============

    modifier onlyGovernance() {
        require(msg.sender == futarchyGovernance, "Only governance");
        _;
    }

    modifier validStake(address user, uint256 stakeId) {
        require(stakeId < userStakeCount[user], "Invalid stake ID");
        require(!stakes[user][stakeId].withdrawn, "Stake already withdrawn");
        _;
    }

    // ============ CONSTRUCTOR ============

    constructor(
        address _governanceToken,
        address _futarchyGovernance,
        address _reputationOracle
    ) {
        governanceToken = IERC20(_governanceToken);
        futarchyGovernance = _futarchyGovernance;
        reputationOracle = _reputationOracle;
    }

    // ============ STAKING FUNCTIONS ============

    function stakeForProposal(
        uint256 proposalId,
        uint256 amount,
        uint256 lockDuration
    ) external nonReentrant returns (uint256 stakeId) {
        require(amount >= _getMinStakeAmount(msg.sender), "Insufficient stake amount");
        require(lockDuration <= MAX_LOCK_DURATION, "Lock duration too long");

        governanceToken.safeTransferFrom(msg.sender, address(this), amount);

        stakeId = userStakeCount[msg.sender]++;
        stakes[msg.sender][stakeId] = StakeInfo({
            amount: amount,
            lockTime: lockDuration,
            unlockTime: block.timestamp + lockDuration,
            withdrawn: false,
            proposalId: proposalId,
            stakeType: StakeType.Proposal
        });

        treasury.totalDeposits += amount;
        treasury.activeStakes++;
        treasury.lockedAmount += amount;

        emit StakePlaced(msg.sender, stakeId, amount, lockDuration, StakeType.Proposal);
    }

    function stakeForGovernance(uint256 amount, uint256 lockDuration) external nonReentrant returns (uint256 stakeId) {
        require(amount >= BASE_STAKE_REQUIREMENT, "Below minimum stake");
        require(lockDuration >= 30 days, "Minimum 30 day lock for governance");

        governanceToken.safeTransferFrom(msg.sender, address(this), amount);

        stakeId = userStakeCount[msg.sender]++;
        stakes[msg.sender][stakeId] = StakeInfo({
            amount: amount,
            lockTime: lockDuration,
            unlockTime: block.timestamp + lockDuration,
            withdrawn: false,
            proposalId: 0, // No specific proposal
            stakeType: StakeType.Governance
        });

        treasury.totalDeposits += amount;
        treasury.activeStakes++;
        treasury.lockedAmount += amount;

        emit StakePlaced(msg.sender, stakeId, amount, lockDuration, StakeType.Governance);
    }

    function withdrawStake(uint256 stakeId) external validStake(msg.sender, stakeId) nonReentrant {
        StakeInfo storage stake = stakes[msg.sender][stakeId];
        
        uint256 penalty = 0;
        if (block.timestamp < stake.unlockTime) {
            // Early withdrawal penalty
            uint256 timeRemaining = stake.unlockTime - block.timestamp;
            penalty = (stake.amount * timeRemaining) / (stake.lockTime * 4); // Max 25% penalty
        }

        uint256 withdrawAmount = stake.amount - penalty;
        stake.withdrawn = true;

        treasury.totalWithdrawals += stake.amount;
        treasury.activeStakes--;
        treasury.lockedAmount -= stake.amount;

        if (penalty > 0) {
            // Penalty goes to treasury
            governanceToken.safeTransfer(address(this), penalty);
        }

        governanceToken.safeTransfer(msg.sender, withdrawAmount);

        emit StakeWithdrawn(msg.sender, stakeId, withdrawAmount, penalty);
    }

    // ============ REWARD DISTRIBUTION ============

    function initializeRewardDistribution(
        uint256 proposalId,
        address[] memory participants,
        uint256[] memory stakes
    ) external onlyGovernance {
        require(participants.length == stakes.length, "Array length mismatch");
        
        RewardDistribution storage distribution = rewards[proposalId];
        require(!distribution.finalized, "Already finalized");

        uint256 totalStaked = 0;
        for (uint256 i = 0; i < stakes.length; i++) {
            totalStaked += stakes[i];
        }

        uint256 rewardAmount = _calculateTotalReward(proposalId, totalStaked);
        distribution.totalAmount = rewardAmount;
        distribution.participantCount = participants.length;

        // Calculate individual rewards based on stake and performance
        for (uint256 i = 0; i < participants.length; i++) {
            uint256 baseReward = (rewardAmount * stakes[i]) / totalStaked;
            uint256 bonusReward = _calculateBonusReward(participants[i], proposalId);
            distribution.userRewards[participants[i]] = baseReward + bonusReward;
        }

        emit RewardsDistributed(proposalId, rewardAmount, participants.length);
    }

    function claimReward(uint256 proposalId) external nonReentrant {
        RewardDistribution storage distribution = rewards[proposalId];
        require(distribution.totalAmount > 0, "No rewards to claim");
        require(!distribution.claimed[msg.sender], "Already claimed");
        require(distribution.userRewards[msg.sender] > 0, "No rewards available");

        uint256 rewardAmount = distribution.userRewards[msg.sender];
        distribution.claimed[msg.sender] = true;
        distribution.distributedAmount += rewardAmount;

        treasury.totalRewardsDistributed += rewardAmount;

        governanceToken.safeTransfer(msg.sender, rewardAmount);

        emit RewardClaimed(msg.sender, proposalId, rewardAmount);
    }

    // ============ TREASURY MANAGEMENT ============

    function depositToTreasury(uint256 amount) external {
        governanceToken.safeTransferFrom(msg.sender, address(this), amount);
        treasury.totalDeposits += amount;
    }

    function distributeTreasuryRewards(
        address[] memory recipients,
        uint256[] memory amounts
    ) external onlyGovernance {
        require(recipients.length == amounts.length, "Array length mismatch");
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        require(governanceToken.balanceOf(address(this)) >= totalAmount, "Insufficient treasury");

        for (uint256 i = 0; i < recipients.length; i++) {
            governanceToken.safeTransfer(recipients[i], amounts[i]);
        }

        treasury.totalRewardsDistributed += totalAmount;
    }

    // ============ ECONOMIC OPTIMIZATION ============

    function adjustEconomicParameters(
        uint256 newStakingMultiplier,
        uint256 newParticipationBonus,
        uint256 newQualityThreshold
    ) external onlyGovernance {
        require(newStakingMultiplier >= 50 && newStakingMultiplier <= 200, "Invalid multiplier");
        require(newParticipationBonus <= 50, "Bonus too high");
        require(newQualityThreshold >= 50 && newQualityThreshold <= 95, "Invalid threshold");

        stakingMultiplier = newStakingMultiplier;
        participationBonus = newParticipationBonus;
        qualityThreshold = newQualityThreshold;

        emit EconomicParametersUpdated(
            newStakingMultiplier,
            newParticipationBonus,
            newQualityThreshold
        );
    }

    // ============ INTERNAL FUNCTIONS ============

    function _getMinStakeAmount(address user) internal view returns (uint256) {
        // Get voting weight from reputation oracle
        (bool success, bytes memory data) = reputationOracle.staticcall(
            abi.encodeWithSignature("getVotingWeight(address)", user)
        );
        
        if (!success) return BASE_STAKE_REQUIREMENT;
        
        uint256 weight = abi.decode(data, (uint256));
        
        // Higher reputation allows lower stakes
        if (weight > 1000e18) return BASE_STAKE_REQUIREMENT / 2; // 50% discount
        if (weight > 500e18) return (BASE_STAKE_REQUIREMENT * 75) / 100; // 25% discount
        
        return BASE_STAKE_REQUIREMENT;
    }

    function _calculateTotalReward(uint256 proposalId, uint256 totalStaked) internal view returns (uint256) {
        // Base reward is 5% of total stakes
        uint256 baseReward = (totalStaked * 5) / 100;
        
        // Apply multiplier based on governance success rate
        uint256 multipliedReward = (baseReward * stakingMultiplier) / 100;
        
        // Treasury fee
        uint256 treasuryFee = (multipliedReward * TREASURY_FEE) / 100;
        
        return multipliedReward - treasuryFee;
    }

    function _calculateBonusReward(address user, uint256 proposalId) internal view returns (uint256) {
        // Get user's historical performance
        // For now, return a base bonus
        return 0; // TODO: Implement performance-based bonuses
    }

    // ============ VIEW FUNCTIONS ============

    function getStakeInfo(address user, uint256 stakeId) external view returns (StakeInfo memory) {
        return stakes[user][stakeId];
    }

    function getUserStakes(address user) external view returns (StakeInfo[] memory) {
        uint256 count = userStakeCount[user];
        StakeInfo[] memory userStakes = new StakeInfo[](count);
        
        for (uint256 i = 0; i < count; i++) {
            userStakes[i] = stakes[user][i];
        }
        
        return userStakes;
    }

    function getRewardInfo(uint256 proposalId, address user) external view returns (
        uint256 totalReward,
        uint256 userReward,
        bool claimed
    ) {
        RewardDistribution storage distribution = rewards[proposalId];
        return (
            distribution.totalAmount,
            distribution.userRewards[user],
            distribution.claimed[user]
        );
    }

    function getTreasuryStats() external view returns (TreasuryStats memory) {
        return treasury;
    }

    function getEconomicMetrics() external view returns (EconomicMetrics memory) {
        uint256 totalBalance = governanceToken.balanceOf(address(this));
        
        return EconomicMetrics({
            participationRate: totalParticipants > 0 ? (treasury.activeStakes * 100) / totalParticipants : 0,
            avgStakeSize: treasury.activeStakes > 0 ? treasury.lockedAmount / treasury.activeStakes : 0,
            treasuryHealth: treasury.totalDeposits > 0 ? (totalBalance * 100) / treasury.totalDeposits : 0,
            rewardEfficiency: treasury.totalDeposits > 0 ? (treasury.totalRewardsDistributed * 100) / treasury.totalDeposits : 0
        });
    }

    // ============ EMERGENCY FUNCTIONS ============

    function emergencyWithdraw() external onlyOwner {
        uint256 balance = governanceToken.balanceOf(address(this));
        governanceToken.safeTransfer(owner(), balance);
    }
}