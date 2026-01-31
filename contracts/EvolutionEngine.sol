// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title EvolutionEngine
 * @dev Autonomous governance parameter optimization based on performance metrics
 * Allows the Futarchy system to evolve and improve itself over time
 */
contract EvolutionEngine is Ownable, ReentrancyGuard {
    using Math for uint256;

    // ============ STRUCTS ============

    struct GovernanceMetrics {
        uint256 proposalQuality;     // % of successful proposals
        uint256 participationRate;   // % of eligible agents voting
        uint256 outcomeAccuracy;     // Prediction vs reality accuracy
        uint256 productDelivery;     // % of proposals delivering products
        uint256 timeToExecution;     // Average time from proposal to execution
        uint256 stakingEfficiency;   // Reward distribution effectiveness
    }

    struct PerformanceThresholds {
        uint256 minProposalQuality;  // Minimum acceptable quality
        uint256 minParticipation;    // Minimum participation rate
        uint256 minAccuracy;         // Minimum prediction accuracy
        uint256 minDelivery;         // Minimum product delivery rate
        uint256 maxExecutionTime;    // Maximum acceptable execution time
    }

    struct EvolutionAction {
        uint256 actionId;
        string actionType;           // "increase_stake", "decrease_time", etc.
        uint256 parameter;           // Parameter to modify
        uint256 oldValue;
        uint256 newValue;
        uint256 timestamp;
        bool executed;
        bytes32 justification;       // Hash of reasoning
    }

    struct AdaptationRule {
        string metricName;
        uint256 threshold;
        string actionType;
        uint256 adjustmentFactor;    // How much to adjust (percentage)
        uint256 cooldownPeriod;      // Min time between adjustments
        uint256 lastTriggered;
        bool active;
    }

    // ============ STATE VARIABLES ============

    address public futarchyGovernance;
    address public reputationOracle;
    address public bankrIntegration;

    GovernanceMetrics public currentMetrics;
    PerformanceThresholds public thresholds;

    mapping(uint256 => EvolutionAction) public evolutionActions;
    mapping(string => AdaptationRule) public adaptationRules;
    uint256 public actionCount;

    // Performance history for trend analysis
    mapping(uint256 => GovernanceMetrics) public historicalMetrics; // timestamp => metrics
    uint256[] public metricTimestamps;
    uint256 public constant METRIC_HISTORY_LIMIT = 100;

    // Autonomous adjustment parameters
    uint256 public constant ADJUSTMENT_COOLDOWN = 7 days;
    uint256 public constant MIN_DATA_POINTS = 5;
    uint256 public constant MAX_ADJUSTMENT_FACTOR = 50; // Max 50% change per adjustment

    // Current governance parameters (cached for quick access)
    uint256 public minStakeAmount = 100e18;
    uint256 public votingDuration = 7 days;
    uint256 public executionDelay = 2 days;
    uint256 public rewardPercentage = 10;
    uint256 public participationBonus = 15;

    // ============ EVENTS ============

    event MetricsUpdated(
        uint256 timestamp,
        uint256 proposalQuality,
        uint256 participationRate,
        uint256 outcomeAccuracy,
        uint256 productDelivery
    );

    event EvolutionTriggered(
        uint256 indexed actionId,
        string actionType,
        uint256 oldValue,
        uint256 newValue,
        string reason
    );

    event ThresholdAdjusted(
        string metricName,
        uint256 oldThreshold,
        uint256 newThreshold
    );

    event AdaptationRuleUpdated(
        string metricName,
        uint256 threshold,
        string actionType,
        uint256 adjustmentFactor
    );

    // ============ MODIFIERS ============

    modifier onlyGovernanceSystem() {
        require(
            msg.sender == futarchyGovernance || 
            msg.sender == reputationOracle || 
            msg.sender == bankrIntegration,
            "Only governance system"
        );
        _;
    }

    // ============ CONSTRUCTOR ============

    constructor(
        address _futarchyGovernance,
        address _reputationOracle,
        address _bankrIntegration
    ) {
        futarchyGovernance = _futarchyGovernance;
        reputationOracle = _reputationOracle;
        bankrIntegration = _bankrIntegration;

        // Initialize default thresholds
        thresholds = PerformanceThresholds({
            minProposalQuality: 70,    // 70% success rate
            minParticipation: 50,      // 50% participation
            minAccuracy: 60,           // 60% prediction accuracy
            minDelivery: 80,           // 80% product delivery
            maxExecutionTime: 14 days  // Max 2 weeks to execute
        });

        // Initialize adaptation rules
        _initializeAdaptationRules();
    }

    // ============ METRIC COLLECTION ============

    function updateMetrics(
        uint256 proposalQuality,
        uint256 participationRate,
        uint256 outcomeAccuracy,
        uint256 productDelivery,
        uint256 timeToExecution,
        uint256 stakingEfficiency
    ) external onlyGovernanceSystem {
        currentMetrics = GovernanceMetrics({
            proposalQuality: proposalQuality,
            participationRate: participationRate,
            outcomeAccuracy: outcomeAccuracy,
            productDelivery: productDelivery,
            timeToExecution: timeToExecution,
            stakingEfficiency: stakingEfficiency
        });

        // Store in history
        uint256 timestamp = block.timestamp;
        historicalMetrics[timestamp] = currentMetrics;
        metricTimestamps.push(timestamp);

        // Maintain history limit
        if (metricTimestamps.length > METRIC_HISTORY_LIMIT) {
            uint256 oldTimestamp = metricTimestamps[0];
            delete historicalMetrics[oldTimestamp];
            
            // Shift array (gas intensive, but necessary for now)
            for (uint256 i = 0; i < metricTimestamps.length - 1; i++) {
                metricTimestamps[i] = metricTimestamps[i + 1];
            }
            metricTimestamps.pop();
        }

        emit MetricsUpdated(
            timestamp,
            proposalQuality,
            participationRate,
            outcomeAccuracy,
            productDelivery
        );

        // Trigger autonomous evolution
        _checkAndTriggerEvolution();
    }

    // ============ AUTONOMOUS EVOLUTION ============

    function _checkAndTriggerEvolution() internal {
        if (metricTimestamps.length < MIN_DATA_POINTS) return;

        // Check each metric against thresholds and adaptation rules
        _evaluateMetric("proposalQuality", currentMetrics.proposalQuality);
        _evaluateMetric("participationRate", currentMetrics.participationRate);
        _evaluateMetric("outcomeAccuracy", currentMetrics.outcomeAccuracy);
        _evaluateMetric("productDelivery", currentMetrics.productDelivery);
        _evaluateMetric("timeToExecution", currentMetrics.timeToExecution);
        _evaluateMetric("stakingEfficiency", currentMetrics.stakingEfficiency);
    }

    function _evaluateMetric(string memory metricName, uint256 currentValue) internal {
        AdaptationRule storage rule = adaptationRules[metricName];
        if (!rule.active) return;

        // Check cooldown
        if (block.timestamp - rule.lastTriggered < rule.cooldownPeriod) return;

        // Check if adaptation is needed
        bool needsAdjustment = false;
        bool isBelow = false;

        if (keccak256(abi.encodePacked(metricName)) == keccak256("timeToExecution")) {
            // For execution time, we want it BELOW the threshold
            needsAdjustment = currentValue > rule.threshold;
            isBelow = false;
        } else {
            // For other metrics, we want them ABOVE the threshold
            needsAdjustment = currentValue < rule.threshold;
            isBelow = true;
        }

        if (needsAdjustment) {
            _executeAdaptation(rule, currentValue, isBelow);
        }
    }

    function _executeAdaptation(
        AdaptationRule storage rule,
        uint256 currentValue,
        bool isBelow
    ) internal {
        uint256 actionId = actionCount++;
        uint256 oldValue;
        uint256 newValue;

        // Execute specific adaptation based on action type
        if (keccak256(abi.encodePacked(rule.actionType)) == keccak256("increase_stake")) {
            oldValue = minStakeAmount;
            newValue = oldValue + (oldValue * rule.adjustmentFactor) / 100;
            newValue = Math.min(newValue, oldValue * 150 / 100); // Max 50% increase
            minStakeAmount = newValue;
            _updateGovernanceParameter("minStake", newValue);
            
        } else if (keccak256(abi.encodePacked(rule.actionType)) == keccak256("decrease_stake")) {
            oldValue = minStakeAmount;
            newValue = oldValue - (oldValue * rule.adjustmentFactor) / 100;
            newValue = Math.max(newValue, oldValue * 50 / 100); // Max 50% decrease
            minStakeAmount = newValue;
            _updateGovernanceParameter("minStake", newValue);
            
        } else if (keccak256(abi.encodePacked(rule.actionType)) == keccak256("adjust_voting_time")) {
            oldValue = votingDuration;
            if (isBelow) {
                newValue = oldValue + (oldValue * rule.adjustmentFactor) / 100;
            } else {
                newValue = oldValue - (oldValue * rule.adjustmentFactor) / 100;
            }
            newValue = Math.max(newValue, 3 days);  // Min 3 days
            newValue = Math.min(newValue, 14 days); // Max 14 days
            votingDuration = newValue;
            _updateGovernanceParameter("votingDuration", newValue);
            
        } else if (keccak256(abi.encodePacked(rule.actionType)) == keccak256("adjust_rewards")) {
            oldValue = rewardPercentage;
            if (isBelow) {
                newValue = oldValue + (oldValue * rule.adjustmentFactor) / 100;
            } else {
                newValue = oldValue - (oldValue * rule.adjustmentFactor) / 100;
            }
            newValue = Math.max(newValue, 5);  // Min 5%
            newValue = Math.min(newValue, 25); // Max 25%
            rewardPercentage = newValue;
            _updateBankrParameter("rewardPercentage", newValue);
        }

        // Record the evolution action
        evolutionActions[actionId] = EvolutionAction({
            actionId: actionId,
            actionType: rule.actionType,
            parameter: 0, // Could specify which parameter
            oldValue: oldValue,
            newValue: newValue,
            timestamp: block.timestamp,
            executed: true,
            justification: keccak256(abi.encodePacked("Metric below threshold: ", rule.metricName))
        });

        rule.lastTriggered = block.timestamp;

        emit EvolutionTriggered(
            actionId,
            rule.actionType,
            oldValue,
            newValue,
            string(abi.encodePacked("Optimizing ", rule.metricName))
        );
    }

    // ============ PARAMETER UPDATES ============

    function _updateGovernanceParameter(string memory paramName, uint256 newValue) internal {
        // Call governance contract to update parameter
        (bool success,) = futarchyGovernance.call(
            abi.encodeWithSignature(
                "updateParameter(string,uint256)", 
                paramName, 
                newValue
            )
        );
        // Note: In production, we'd want to handle failure cases
    }

    function _updateBankrParameter(string memory paramName, uint256 newValue) internal {
        // Call Bankr integration to update parameter
        (bool success,) = bankrIntegration.call(
            abi.encodeWithSignature(
                "updateParameter(string,uint256)", 
                paramName, 
                newValue
            )
        );
    }

    // ============ ADAPTATION RULE MANAGEMENT ============

    function _initializeAdaptationRules() internal {
        // Rule: If proposal quality is low, increase stake requirements
        adaptationRules["proposalQuality"] = AdaptationRule({
            metricName: "proposalQuality",
            threshold: 70,
            actionType: "increase_stake",
            adjustmentFactor: 20, // 20% increase
            cooldownPeriod: 7 days,
            lastTriggered: 0,
            active: true
        });

        // Rule: If participation is low, increase rewards
        adaptationRules["participationRate"] = AdaptationRule({
            metricName: "participationRate",
            threshold: 50,
            actionType: "adjust_rewards",
            adjustmentFactor: 15, // 15% increase
            cooldownPeriod: 7 days,
            lastTriggered: 0,
            active: true
        });

        // Rule: If execution time is too long, decrease voting duration
        adaptationRules["timeToExecution"] = AdaptationRule({
            metricName: "timeToExecution",
            threshold: 14 days,
            actionType: "adjust_voting_time",
            adjustmentFactor: 10, // 10% decrease
            cooldownPeriod: 14 days,
            lastTriggered: 0,
            active: true
        });
    }

    function updateAdaptationRule(
        string memory metricName,
        uint256 threshold,
        string memory actionType,
        uint256 adjustmentFactor,
        uint256 cooldownPeriod,
        bool active
    ) external onlyOwner {
        require(adjustmentFactor <= MAX_ADJUSTMENT_FACTOR, "Adjustment too large");
        
        adaptationRules[metricName] = AdaptationRule({
            metricName: metricName,
            threshold: threshold,
            actionType: actionType,
            adjustmentFactor: adjustmentFactor,
            cooldownPeriod: cooldownPeriod,
            lastTriggered: 0,
            active: active
        });

        emit AdaptationRuleUpdated(metricName, threshold, actionType, adjustmentFactor);
    }

    // ============ ANALYSIS FUNCTIONS ============

    function analyzePerformanceTrends() external view returns (
        bool improving,
        uint256 trendDirection,
        uint256 averageQuality,
        uint256 averageParticipation
    ) {
        if (metricTimestamps.length < 3) {
            return (false, 0, 0, 0);
        }

        // Calculate recent vs older performance
        uint256 recentStart = metricTimestamps.length >= 6 ? metricTimestamps.length - 3 : 0;
        uint256 olderEnd = metricTimestamps.length >= 6 ? metricTimestamps.length - 6 : 0;

        uint256 recentQuality = 0;
        uint256 olderQuality = 0;
        uint256 recentCount = 0;
        uint256 olderCount = 0;

        // Calculate recent average
        for (uint256 i = recentStart; i < metricTimestamps.length; i++) {
            recentQuality += historicalMetrics[metricTimestamps[i]].proposalQuality;
            recentCount++;
        }

        // Calculate older average
        for (uint256 i = olderEnd; i < recentStart; i++) {
            olderQuality += historicalMetrics[metricTimestamps[i]].proposalQuality;
            olderCount++;
        }

        if (recentCount > 0 && olderCount > 0) {
            recentQuality /= recentCount;
            olderQuality /= olderCount;
            
            improving = recentQuality > olderQuality;
            trendDirection = recentQuality > olderQuality ? 1 : 2; // 1 = up, 2 = down
        }

        // Calculate overall averages
        uint256 totalQuality = 0;
        uint256 totalParticipation = 0;
        for (uint256 i = 0; i < metricTimestamps.length; i++) {
            totalQuality += historicalMetrics[metricTimestamps[i]].proposalQuality;
            totalParticipation += historicalMetrics[metricTimestamps[i]].participationRate;
        }

        averageQuality = totalQuality / metricTimestamps.length;
        averageParticipation = totalParticipation / metricTimestamps.length;
    }

    // ============ VIEW FUNCTIONS ============

    function getCurrentMetrics() external view returns (GovernanceMetrics memory) {
        return currentMetrics;
    }

    function getThresholds() external view returns (PerformanceThresholds memory) {
        return thresholds;
    }

    function getEvolutionAction(uint256 actionId) external view returns (EvolutionAction memory) {
        return evolutionActions[actionId];
    }

    function getAdaptationRule(string memory metricName) external view returns (AdaptationRule memory) {
        return adaptationRules[metricName];
    }

    function getMetricsHistory() external view returns (
        uint256[] memory timestamps,
        GovernanceMetrics[] memory metrics
    ) {
        timestamps = metricTimestamps;
        metrics = new GovernanceMetrics[](timestamps.length);
        
        for (uint256 i = 0; i < timestamps.length; i++) {
            metrics[i] = historicalMetrics[timestamps[i]];
        }
    }

    function getCurrentParameters() external view returns (
        uint256 _minStake,
        uint256 _votingDuration,
        uint256 _executionDelay,
        uint256 _rewardPercentage,
        uint256 _participationBonus
    ) {
        return (
            minStakeAmount,
            votingDuration,
            executionDelay,
            rewardPercentage,
            participationBonus
        );
    }

    // ============ ADMIN FUNCTIONS ============

    function updateThresholds(
        uint256 minQuality,
        uint256 minParticipation,
        uint256 minAccuracy,
        uint256 minDelivery,
        uint256 maxExecTime
    ) external onlyOwner {
        thresholds = PerformanceThresholds({
            minProposalQuality: minQuality,
            minParticipation: minParticipation,
            minAccuracy: minAccuracy,
            minDelivery: minDelivery,
            maxExecutionTime: maxExecTime
        });
    }

    function setGovernanceContracts(
        address _futarchy,
        address _reputation,
        address _bankr
    ) external onlyOwner {
        futarchyGovernance = _futarchy;
        reputationOracle = _reputation;
        bankrIntegration = _bankr;
    }
}