// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title ReputationOracle
 * @dev Hybrid reputation system combining ERC-8004 and Moltbook Karma
 * Provides weighted voting power for Futarchy governance
 */
contract ReputationOracle is Ownable, ReentrancyGuard {
    using Math for uint256;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // ============ STRUCTS ============

    struct AgentReputation {
        uint256 erc8004Score;     // On-chain reputation from ERC-8004
        uint256 moltbookKarma;    // Social reputation from Moltbook
        uint256 governanceWeight;  // Combined voting weight
        uint256 lastUpdate;
        bool verified;
        string moltbookUsername;
        bytes32 identityProof;
    }

    struct ERC8004Data {
        uint256 totalScore;
        uint256 positiveVotes;
        uint256 negativeVotes;
        uint256 lastActivity;
        bool isActive;
    }

    struct MoltbookData {
        uint256 karma;
        uint256 posts;
        uint256 interactions;
        uint256 qualityScore;
        uint256 lastActivity;
    }

    struct IdentityProof {
        address agentAddress;
        string moltbookUsername;
        uint256 timestamp;
        bytes signature;
    }

    // ============ STATE VARIABLES ============

    mapping(address => AgentReputation) public reputation;
    mapping(string => address) public usernameToAddress; // Moltbook username -> address
    mapping(bytes32 => bool) public usedProofs; // Prevent replay attacks

    address public erc8004Contract;
    address public moltbookOracle; // Trusted oracle for Moltbook data
    address public governanceContract;

    uint256 public constant MIN_ERC8004_SCORE = 100;
    uint256 public constant MIN_MOLTBOOK_KARMA = 50;
    uint256 public constant MAX_REPUTATION_AGE = 30 days;
    uint256 public constant WEIGHT_MULTIPLIER = 1e18;

    // Outcome measurement tracking
    mapping(uint256 => OutcomeMeasurement) public measurements;
    
    struct OutcomeMeasurement {
        uint256 proposalId;
        uint256 startTime;
        uint256 endTime;
        bool measured;
        uint256 result;
    }

    // ============ EVENTS ============

    event ReputationUpdated(
        address indexed agent,
        uint256 erc8004Score,
        uint256 moltbookKarma,
        uint256 governanceWeight
    );

    event IdentityVerified(
        address indexed agent,
        string moltbookUsername,
        uint256 timestamp
    );

    event OutcomeMeasurementStarted(
        uint256 indexed proposalId,
        uint256 startTime
    );

    event OutcomeReported(
        uint256 indexed proposalId,
        uint256 outcome
    );

    // ============ MODIFIERS ============

    modifier onlyMoltbookOracle() {
        require(msg.sender == moltbookOracle, "Only Moltbook oracle");
        _;
    }

    modifier onlyGovernance() {
        require(msg.sender == governanceContract, "Only governance");
        _;
    }

    // ============ CONSTRUCTOR ============

    constructor(
        address _erc8004Contract,
        address _moltbookOracle,
        address _governanceContract
    ) {
        erc8004Contract = _erc8004Contract;
        moltbookOracle = _moltbookOracle;
        governanceContract = _governanceContract;
    }

    // ============ IDENTITY VERIFICATION ============

    function verifyIdentity(
        string memory moltbookUsername,
        IdentityProof memory proof
    ) external nonReentrant {
        require(proof.agentAddress == msg.sender, "Invalid address");
        require(
            keccak256(abi.encodePacked(proof.moltbookUsername)) == 
            keccak256(abi.encodePacked(moltbookUsername)), 
            "Username mismatch"
        );

        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            proof.agentAddress,
            proof.moltbookUsername,
            proof.timestamp
        )).toEthSignedMessageHash();

        require(!usedProofs[messageHash], "Proof already used");
        
        // For now, we'll trust the signature from the user
        // In production, this would verify against Moltbook's signing key
        
        usedProofs[messageHash] = true;
        usernameToAddress[moltbookUsername] = msg.sender;

        AgentReputation storage rep = reputation[msg.sender];
        rep.moltbookUsername = moltbookUsername;
        rep.identityProof = messageHash;
        rep.verified = true;
        rep.lastUpdate = block.timestamp;

        emit IdentityVerified(msg.sender, moltbookUsername, block.timestamp);
    }

    // ============ REPUTATION UPDATES ============

    function updateReputation(address agent) external nonReentrant {
        require(reputation[agent].verified, "Agent not verified");
        require(
            block.timestamp - reputation[agent].lastUpdate > 1 hours,
            "Updated too recently"
        );

        // Fetch ERC-8004 data
        ERC8004Data memory erc8004Data = _fetchERC8004Data(agent);
        
        // Fetch Moltbook data (requires oracle)
        // For now, we'll use a placeholder that can be updated by oracle
        MoltbookData memory moltbookData = _fetchMoltbookData(agent);

        // Calculate composite reputation
        uint256 erc8004Score = _calculateERC8004Score(erc8004Data);
        uint256 moltbookKarma = _calculateMoltbookScore(moltbookData);
        uint256 governanceWeight = _calculateGovernanceWeight(erc8004Score, moltbookKarma);

        AgentReputation storage rep = reputation[agent];
        rep.erc8004Score = erc8004Score;
        rep.moltbookKarma = moltbookKarma;
        rep.governanceWeight = governanceWeight;
        rep.lastUpdate = block.timestamp;

        emit ReputationUpdated(agent, erc8004Score, moltbookKarma, governanceWeight);
    }

    function updateMoltbookData(
        address agent,
        uint256 karma,
        uint256 posts,
        uint256 interactions,
        uint256 qualityScore
    ) external onlyMoltbookOracle {
        require(reputation[agent].verified, "Agent not verified");

        // Store the Moltbook data for the agent
        // This would be called by the Moltbook oracle service
        MoltbookData memory data = MoltbookData({
            karma: karma,
            posts: posts,
            interactions: interactions,
            qualityScore: qualityScore,
            lastActivity: block.timestamp
        });

        // Update reputation with new Moltbook data
        AgentReputation storage rep = reputation[agent];
        uint256 moltbookScore = _calculateMoltbookScore(data);
        uint256 newWeight = _calculateGovernanceWeight(rep.erc8004Score, moltbookScore);
        
        rep.moltbookKarma = moltbookScore;
        rep.governanceWeight = newWeight;
        rep.lastUpdate = block.timestamp;

        emit ReputationUpdated(agent, rep.erc8004Score, moltbookScore, newWeight);
    }

    // ============ OUTCOME MEASUREMENT ============

    function startOutcomeMeasurement(uint256 proposalId) external onlyGovernance {
        measurements[proposalId] = OutcomeMeasurement({
            proposalId: proposalId,
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days, // 7 day measurement period
            measured: false,
            result: 0
        });

        emit OutcomeMeasurementStarted(proposalId, block.timestamp);
    }

    function reportOutcome(uint256 proposalId, uint256 outcome) external onlyMoltbookOracle {
        OutcomeMeasurement storage measurement = measurements[proposalId];
        require(!measurement.measured, "Already measured");
        require(block.timestamp >= measurement.endTime, "Measurement period not ended");

        measurement.result = outcome;
        measurement.measured = true;

        emit OutcomeReported(proposalId, outcome);

        // Notify governance contract
        (bool success,) = governanceContract.call(
            abi.encodeWithSignature("reportOutcome(uint256,uint256)", proposalId, outcome)
        );
        require(success, "Failed to report to governance");
    }

    // ============ INTERNAL FUNCTIONS ============

    function _fetchERC8004Data(address agent) internal view returns (ERC8004Data memory) {
        // In production, this would call the actual ERC-8004 contract
        // For now, returning mock data
        return ERC8004Data({
            totalScore: 500,
            positiveVotes: 100,
            negativeVotes: 10,
            lastActivity: block.timestamp - 1 days,
            isActive: true
        });
    }

    function _fetchMoltbookData(address agent) internal view returns (MoltbookData memory) {
        // This would be populated by the Moltbook oracle
        // For now, returning default values
        return MoltbookData({
            karma: 100,
            posts: 50,
            interactions: 200,
            qualityScore: 80,
            lastActivity: block.timestamp - 6 hours
        });
    }

    function _calculateERC8004Score(ERC8004Data memory data) internal pure returns (uint256) {
        if (!data.isActive) return 0;
        
        // Calculate score based on positive/negative ratio and total activity
        uint256 positiveRatio = data.positiveVotes * 100 / 
                               (data.positiveVotes + data.negativeVotes + 1);
        
        // Combine total score with ratio for final ERC-8004 score
        return (data.totalScore * positiveRatio) / 100;
    }

    function _calculateMoltbookScore(MoltbookData memory data) internal pure returns (uint256) {
        // Weighted combination of karma, posts, interactions, and quality
        uint256 karmaWeight = data.karma * 40 / 100; // 40% weight
        uint256 interactionWeight = data.interactions * 30 / 100; // 30% weight  
        uint256 qualityWeight = data.qualityScore * 20 / 100; // 20% weight
        uint256 postWeight = data.posts * 10 / 100; // 10% weight
        
        return karmaWeight + interactionWeight + qualityWeight + postWeight;
    }

    function _calculateGovernanceWeight(
        uint256 erc8004Score,
        uint256 moltbookKarma
    ) internal pure returns (uint256) {
        // Geometric mean to prevent gaming one dimension
        // Weight = sqrt(erc8004 * moltbook) * multiplier
        uint256 product = erc8004Score * moltbookKarma;
        if (product == 0) return 0;
        
        return Math.sqrt(product) * WEIGHT_MULTIPLIER / 100;
    }

    // ============ VIEW FUNCTIONS ============

    function hasMinReputation(address agent) external view returns (bool) {
        AgentReputation memory rep = reputation[agent];
        return rep.verified && 
               rep.erc8004Score >= MIN_ERC8004_SCORE &&
               rep.moltbookKarma >= MIN_MOLTBOOK_KARMA &&
               (block.timestamp - rep.lastUpdate) <= MAX_REPUTATION_AGE;
    }

    function getVotingWeight(address agent) external view returns (uint256) {
        if (!hasMinReputation(agent)) return 0;
        return reputation[agent].governanceWeight;
    }

    function getAgentReputation(address agent) external view returns (AgentReputation memory) {
        return reputation[agent];
    }

    function getOutcomeMeasurement(uint256 proposalId) external view returns (OutcomeMeasurement memory) {
        return measurements[proposalId];
    }

    // ============ ADMIN FUNCTIONS ============

    function setMoltbookOracle(address newOracle) external onlyOwner {
        moltbookOracle = newOracle;
    }

    function setERC8004Contract(address newContract) external onlyOwner {
        erc8004Contract = newContract;
    }

    function setGovernanceContract(address newContract) external onlyOwner {
        governanceContract = newContract;
    }
}