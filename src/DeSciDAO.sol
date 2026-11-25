// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./DeSciToken.sol";
import "./interfaces/IDeSci.sol";

/**
 * @title DeSciDAO
 * @author Jose Imoberdorf
 * @dev Decentralized Science DAO: the community funds research projects, pays them
 *      by milestones and owns the resulting IP-NFTs (adapted from DAO).
 *
 * Proposal types:
 *  - Funding:        fund a research project with milestones. On execution the funds move
 *                    from the treasury to MilestoneGrant and an IP-NFT is minted to the treasury.
 *  - CancelGrant:    cancel an active grant; unreleased funds return to the treasury.
 *  - AddReviewer:    register a scientific reviewer.
 *  - RemoveReviewer: remove a scientific reviewer.
 *
 * Rules kept from DAO:
 *  - Snapshot voting with ERC20Votes (the same tokens cannot vote twice).
 *  - Configuration bounds, treasury funds check, one active proposal per proposer,
 *    cancel when the proposer drops below the threshold, approval threshold,
 *    execution delay (timelock), grace period and proposal states.
 *
 * New DeSci rule:
 *  - Peer review: funding proposals need at least `minReviews` positive reviews from
 *    registered reviewers, and more positive than negative reviews, to be executed.
 */
contract DeSciDAO is Ownable {
    enum ProposalType {
        Funding,
        CancelGrant,
        AddReviewer,
        RemoveReviewer
    }

    enum ProposalState {
        Active, // Voting open
        Canceled, // Canceled by proposer, owner or anyone (proposer below threshold)
        Defeated, // Voting ended without quorum, approval or peer review
        Queued, // Passed, waiting for the execution delay
        Succeeded, // Passed and executable
        Expired, // Passed but not executed within the grace period
        Executed // Executed
    }

    struct Proposal {
        uint256 id;
        ProposalType proposalType;
        address proposer;
        string description;
        address target; // Researcher (Funding) or reviewer (AddReviewer / RemoveReviewer)
        address token; // Payment token (Funding)
        uint256 amount; // Total grant amount (Funding)
        uint256 grantId; // Grant to cancel (CancelGrant)
        bytes32 documentHash; // Research plan / legal agreement hash (Funding)
        uint256 forVotes;
        uint256 againstVotes;
        uint256 positiveReviews;
        uint256 negativeReviews;
        uint256 startTime;
        uint256 endTime;
        uint256 snapshot; // Timepoint at which voting power is measured
        uint256 eta; // Earliest execution time
        uint256 expiresAt; // Execution deadline
        bool executed;
        bool canceled;
    }

    // Connected contracts
    DeSciToken public immutable governanceToken;
    IDeSciTreasury public immutable treasury;
    IMilestoneGrant public immutable grantManager;
    IResearchIPNFT public immutable researchIPNFT;
    IReviewerRegistry public immutable reviewerRegistry;

    // Proposal tracking
    uint256 public proposalCount;
    mapping(uint256 => Proposal) private proposals;
    mapping(uint256 => uint256[]) private milestoneAmounts;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => mapping(address => bool)) public votedFor;
    mapping(uint256 => mapping(address => bool)) public hasReviewed;

    // Latest proposal of each proposer, stored as id + 1 (0 = none)
    mapping(address => uint256) public latestProposalIds;

    // Results of executed funding proposals
    mapping(uint256 => uint256) public grantOfProposal;
    mapping(uint256 => uint256) public ipTokenOfProposal;

    // DAO configuration
    uint256 public proposalThreshold; // Minimum votes required to create a proposal
    uint256 public votingPeriod; // Duration of voting period in seconds
    uint256 public quorumVotes; // Minimum votes required for a proposal to pass

    // Voting period bounds
    uint256 public constant MIN_VOTING_PERIOD = 1 days;
    uint256 public constant MAX_VOTING_PERIOD = 30 days;

    // Approval threshold in basis points (10000 = 100%)
    uint256 public constant BPS = 10000;
    uint256 public constant MIN_APPROVAL_BPS = 5000; // Simple majority
    uint256 public constant MAX_APPROVAL_BPS = 9000; // 90%
    uint256 public approvalThresholdBps = 5000;

    // Execution delay (timelock) and grace period
    uint256 public constant MAX_EXECUTION_DELAY = 30 days;
    uint256 public constant MIN_GRACE_PERIOD = 1 days;
    uint256 public constant MAX_GRACE_PERIOD = 90 days;
    uint256 public executionDelay = 0;
    uint256 public gracePeriod = 14 days;

    // Peer review and milestones
    uint256 public constant MAX_MIN_REVIEWS = 5;
    uint256 public constant MAX_MILESTONES = 10;
    uint256 public minReviews = 1;

    // Events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        ProposalType proposalType,
        string description,
        uint256 startTime,
        uint256 endTime
    );
    event FundingProposed(
        uint256 indexed proposalId,
        address indexed researcher,
        address token,
        uint256 amount,
        uint256 milestoneCount,
        bytes32 documentHash
    );
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 votes);
    event ProposalReviewed(uint256 indexed proposalId, address indexed reviewer, bytes32 reportHash, bool recommend);
    event ProposalExecuted(uint256 indexed proposalId);
    event ResearchFunded(uint256 indexed proposalId, uint256 indexed grantId, uint256 indexed ipTokenId);
    event ProposalCanceled(uint256 indexed proposalId);
    event ConfigurationUpdated(uint256 proposalThreshold, uint256 votingPeriod, uint256 quorumVotes);
    event ExecutionRulesUpdated(uint256 approvalThresholdBps, uint256 executionDelay, uint256 gracePeriod);
    event MinReviewsUpdated(uint256 minReviews);

    /**
     * @dev Constructor
     * @param _governanceToken DeSciToken address
     * @param _treasury DeSciTreasury address
     * @param _grantManager MilestoneGrant address
     * @param _researchIPNFT ResearchIPNFT address
     * @param _reviewerRegistry ReviewerRegistry address
     * @param _proposalThreshold Minimum votes required to create a proposal
     * @param _votingPeriod Duration of voting period in seconds
     * @param _quorumVotes Minimum votes required for a proposal to pass
     */
    constructor(
        address _governanceToken,
        address _treasury,
        address _grantManager,
        address _researchIPNFT,
        address _reviewerRegistry,
        uint256 _proposalThreshold,
        uint256 _votingPeriod,
        uint256 _quorumVotes
    ) Ownable(msg.sender) {
        require(_governanceToken != address(0), "Invalid token address");
        require(_treasury != address(0), "Invalid treasury address");
        require(_grantManager != address(0), "Invalid grant manager address");
        require(_researchIPNFT != address(0), "Invalid IP-NFT address");
        require(_reviewerRegistry != address(0), "Invalid reviewer registry address");
        _validateConfiguration(_proposalThreshold, _votingPeriod, _quorumVotes);

        governanceToken = DeSciToken(_governanceToken);
        treasury = IDeSciTreasury(_treasury);
        grantManager = IMilestoneGrant(_grantManager);
        researchIPNFT = IResearchIPNFT(_researchIPNFT);
        reviewerRegistry = IReviewerRegistry(_reviewerRegistry);
        proposalThreshold = _proposalThreshold;
        votingPeriod = _votingPeriod;
        quorumVotes = _quorumVotes;
    }

    // =====================================================
    // Proposal creation
    // =====================================================

    /**
     * @dev Propose funding a research project paid by milestones
     * @param description Description of the research project
     * @param researcher Researcher or lab that receives the grant
     * @param token Payment token (e.g. USDC)
     * @param amounts Amount of each milestone
     * @param documentHash Hash of the research plan / legal agreement (e.g. IPFS)
     * @return proposalId ID of the created proposal
     */
    function proposeFunding(
        string memory description,
        address researcher,
        address token,
        uint256[] calldata amounts,
        bytes32 documentHash
    ) external returns (uint256 proposalId) {
        require(researcher != address(0), "Invalid researcher address");
        require(token != address(0), "Invalid token address");
        require(documentHash != bytes32(0), "Invalid document hash");
        uint256 count = amounts.length;
        require(count > 0 && count <= MAX_MILESTONES, "Invalid milestone count");

        uint256 total;
        for (uint256 i = 0; i < count; i++) {
            require(amounts[i] > 0, "Milestone amount must be greater than 0");
            total += amounts[i];
        }
        require(treasury.getBalance(token) >= total, "Insufficient treasury funds");

        Proposal storage proposal;
        (proposalId, proposal) = _newProposal(ProposalType.Funding, description);
        proposal.target = researcher;
        proposal.token = token;
        proposal.amount = total;
        proposal.documentHash = documentHash;
        milestoneAmounts[proposalId] = amounts;

        emit FundingProposed(proposalId, researcher, token, total, count, documentHash);
    }

    /**
     * @dev Propose canceling an active grant (refunds unreleased funds to the treasury)
     * @param description Reason for the cancellation
     * @param grantId ID of the grant in MilestoneGrant
     * @return proposalId ID of the created proposal
     */
    function proposeCancelGrant(string memory description, uint256 grantId) external returns (uint256 proposalId) {
        require(grantManager.isGrantActive(grantId), "Grant is not active");

        Proposal storage proposal;
        (proposalId, proposal) = _newProposal(ProposalType.CancelGrant, description);
        proposal.grantId = grantId;
    }

    /**
     * @dev Propose adding or removing a scientific reviewer
     * @param description Reason for the change
     * @param reviewer Reviewer address
     * @param add True to add, false to remove
     * @return proposalId ID of the created proposal
     */
    function proposeReviewerChange(string memory description, address reviewer, bool add)
        external
        returns (uint256 proposalId)
    {
        require(reviewer != address(0), "Invalid reviewer address");
        if (add) {
            require(!reviewerRegistry.isReviewer(reviewer), "Already a reviewer");
        } else {
            require(reviewerRegistry.isReviewer(reviewer), "Not a reviewer");
        }

        Proposal storage proposal;
        (proposalId, proposal) = _newProposal(add ? ProposalType.AddReviewer : ProposalType.RemoveReviewer, description);
        proposal.target = reviewer;
    }

    // =====================================================
    // Voting and peer review
    // =====================================================

    /**
     * @dev Vote on a proposal with the voting power at the proposal snapshot
     * @param proposalId ID of the proposal
     * @param support True for yes, false for no
     */
    function vote(uint256 proposalId, bool support) external {
        Proposal storage proposal = proposals[proposalId];

        require(proposal.proposer != address(0), "Proposal does not exist");
        require(block.timestamp < proposal.endTime, "Voting ended");
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        require(!proposal.canceled, "Proposal is canceled");

        uint256 votes = governanceToken.getPastVotes(msg.sender, proposal.snapshot);
        require(votes > 0, "No voting power");

        hasVoted[proposalId][msg.sender] = true;
        votedFor[proposalId][msg.sender] = support;

        if (support) {
            proposal.forVotes += votes;
        } else {
            proposal.againstVotes += votes;
        }

        emit Voted(proposalId, msg.sender, support, votes);
    }

    /**
     * @dev Peer review a funding proposal (only registered reviewers without conflict of interest)
     * @param proposalId ID of the funding proposal
     * @param reportHash Hash of the review report (e.g. IPFS)
     * @param recommend True to recommend funding, false to advise against it
     */
    function reviewProposal(uint256 proposalId, bytes32 reportHash, bool recommend) external {
        Proposal storage proposal = proposals[proposalId];

        require(proposal.proposer != address(0), "Proposal does not exist");
        require(proposal.proposalType == ProposalType.Funding, "Only funding proposals are reviewed");
        require(block.timestamp < proposal.endTime, "Review period ended");
        require(!proposal.canceled, "Proposal is canceled");
        require(reviewerRegistry.isReviewer(msg.sender), "Not a reviewer");
        require(msg.sender != proposal.proposer && msg.sender != proposal.target, "Conflict of interest");
        require(!hasReviewed[proposalId][msg.sender], "Already reviewed");
        require(reportHash != bytes32(0), "Invalid report hash");

        hasReviewed[proposalId][msg.sender] = true;
        if (recommend) {
            proposal.positiveReviews++;
        } else {
            proposal.negativeReviews++;
        }
        reviewerRegistry.recordReview(msg.sender);

        emit ProposalReviewed(proposalId, msg.sender, reportHash, recommend);
    }

    // =====================================================
    // Execution and cancellation
    // =====================================================

    /**
     * @dev Execute a proposal that passed, within its execution window
     * @param proposalId ID of the proposal
     */
    function executeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];

        require(proposal.proposer != address(0), "Proposal does not exist");
        require(block.timestamp >= proposal.endTime, "Voting not ended");
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.canceled, "Proposal is canceled");
        require(_quorumReached(proposal), "Quorum not reached");
        require(_approvalReached(proposal), "Proposal not passed");
        require(_reviewsPassed(proposal), "Insufficient positive reviews");
        require(block.timestamp >= proposal.eta, "Execution delay not elapsed");
        require(block.timestamp < proposal.expiresAt, "Proposal expired");

        // Effects before interactions
        proposal.executed = true;

        if (proposal.proposalType == ProposalType.Funding) {
            _executeFunding(proposalId, proposal);
        } else if (proposal.proposalType == ProposalType.CancelGrant) {
            grantManager.cancelGrant(proposal.grantId);
        } else if (proposal.proposalType == ProposalType.AddReviewer) {
            reviewerRegistry.addReviewer(proposal.target);
        } else {
            reviewerRegistry.removeReviewer(proposal.target);
        }

        emit ProposalExecuted(proposalId);
    }

    /**
     * @dev Cancel a proposal (proposer, owner, or anyone if the proposer dropped below the threshold)
     * @param proposalId ID of the proposal
     */
    function cancelProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];

        require(proposal.proposer != address(0), "Proposal does not exist");
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.canceled, "Proposal already canceled");
        require(
            msg.sender == proposal.proposer || msg.sender == owner()
                || governanceToken.getVotes(proposal.proposer) < proposalThreshold,
            "Not authorized to cancel"
        );

        proposal.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    // =====================================================
    // Views
    // =====================================================

    /**
     * @dev Get the current state of a proposal
     * @param proposalId ID of the proposal
     * @return Current ProposalState
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.proposer != address(0), "Proposal does not exist");

        if (proposal.canceled) return ProposalState.Canceled;
        if (proposal.executed) return ProposalState.Executed;
        if (block.timestamp < proposal.endTime) return ProposalState.Active;
        if (!_quorumReached(proposal) || !_approvalReached(proposal) || !_reviewsPassed(proposal)) {
            return ProposalState.Defeated;
        }
        if (block.timestamp < proposal.eta) return ProposalState.Queued;
        if (block.timestamp >= proposal.expiresAt) return ProposalState.Expired;
        return ProposalState.Succeeded;
    }

    /**
     * @dev Get a proposal
     * @param proposalId ID of the proposal
     * @return Proposal data
     */
    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        require(proposals[proposalId].proposer != address(0), "Proposal does not exist");
        return proposals[proposalId];
    }

    /**
     * @dev Get the milestone amounts of a funding proposal
     * @param proposalId ID of the proposal
     * @return Milestone amounts
     */
    function getMilestones(uint256 proposalId) external view returns (uint256[] memory) {
        return milestoneAmounts[proposalId];
    }

    /**
     * @dev Check whether an address has voted on a proposal and how
     * @param proposalId ID of the proposal
     * @param voter Address to check
     * @return voted Whether the address has voted
     * @return support Whether it voted for (only meaningful if voted is true)
     */
    function getVoteInfo(uint256 proposalId, address voter) external view returns (bool voted, bool support) {
        return (hasVoted[proposalId][voter], votedFor[proposalId][voter]);
    }

    // =====================================================
    // Configuration (only owner)
    // =====================================================

    /**
     * @dev Update DAO configuration (only owner)
     * @param _proposalThreshold New proposal threshold
     * @param _votingPeriod New voting period
     * @param _quorumVotes New quorum votes
     */
    function updateConfiguration(uint256 _proposalThreshold, uint256 _votingPeriod, uint256 _quorumVotes)
        external
        onlyOwner
    {
        _validateConfiguration(_proposalThreshold, _votingPeriod, _quorumVotes);
        proposalThreshold = _proposalThreshold;
        votingPeriod = _votingPeriod;
        quorumVotes = _quorumVotes;
        emit ConfigurationUpdated(_proposalThreshold, _votingPeriod, _quorumVotes);
    }

    /**
     * @dev Update approval threshold, execution delay and grace period (only owner).
     *      Delay and grace period apply to proposals created afterwards.
     * @param _approvalThresholdBps New approval threshold in basis points
     * @param _executionDelay New execution delay in seconds
     * @param _gracePeriod New grace period in seconds
     */
    function updateExecutionRules(uint256 _approvalThresholdBps, uint256 _executionDelay, uint256 _gracePeriod)
        external
        onlyOwner
    {
        require(
            _approvalThresholdBps >= MIN_APPROVAL_BPS && _approvalThresholdBps <= MAX_APPROVAL_BPS,
            "Invalid approval threshold"
        );
        require(_executionDelay <= MAX_EXECUTION_DELAY, "Invalid execution delay");
        require(_gracePeriod >= MIN_GRACE_PERIOD && _gracePeriod <= MAX_GRACE_PERIOD, "Invalid grace period");

        approvalThresholdBps = _approvalThresholdBps;
        executionDelay = _executionDelay;
        gracePeriod = _gracePeriod;
        emit ExecutionRulesUpdated(_approvalThresholdBps, _executionDelay, _gracePeriod);
    }

    /**
     * @dev Update the minimum positive reviews required for funding proposals (only owner)
     * @param _minReviews New minimum (1 to MAX_MIN_REVIEWS)
     */
    function setMinReviews(uint256 _minReviews) external onlyOwner {
        require(_minReviews > 0 && _minReviews <= MAX_MIN_REVIEWS, "Invalid min reviews");
        minReviews = _minReviews;
        emit MinReviewsUpdated(_minReviews);
    }

    // =====================================================
    // Internal
    // =====================================================

    /// @dev Create a proposal with the common fields and rules
    function _newProposal(ProposalType proposalType, string memory description)
        internal
        returns (uint256 proposalId, Proposal storage proposal)
    {
        // Previous timepoint: already final, it cannot change anymore
        uint256 snapshot = governanceToken.clock() - 1;
        require(
            governanceToken.getPastVotes(msg.sender, snapshot) >= proposalThreshold,
            "Insufficient voting power to create proposal"
        );
        require(bytes(description).length > 0, "Description cannot be empty");

        // Only one active proposal per proposer
        uint256 latest = latestProposalIds[msg.sender];
        if (latest != 0) {
            require(state(latest - 1) != ProposalState.Active, "Proposer already has an active proposal");
        }

        proposalId = proposalCount++;
        proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.proposalType = proposalType;
        proposal.proposer = msg.sender;
        proposal.description = description;
        proposal.startTime = block.timestamp;
        proposal.endTime = block.timestamp + votingPeriod;
        proposal.snapshot = snapshot;
        proposal.eta = proposal.endTime + executionDelay;
        proposal.expiresAt = proposal.eta + gracePeriod;
        latestProposalIds[msg.sender] = proposalId + 1;

        emit ProposalCreated(proposalId, msg.sender, proposalType, description, proposal.startTime, proposal.endTime);
    }

    /// @dev Move the funds to MilestoneGrant, create the grant and mint the IP-NFT to the treasury
    function _executeFunding(uint256 proposalId, Proposal storage proposal) internal {
        treasury.approveProposal(proposalId);
        treasury.spendFunds(proposalId, address(grantManager), proposal.amount, proposal.token);

        uint256 grantId = grantManager.createGrant(
            proposalId, proposal.target, proposal.token, milestoneAmounts[proposalId], proposal.documentHash
        );
        uint256 ipTokenId = researchIPNFT.mint(address(treasury), proposalId, proposal.target, proposal.documentHash);

        grantOfProposal[proposalId] = grantId;
        ipTokenOfProposal[proposalId] = ipTokenId;
        emit ResearchFunded(proposalId, grantId, ipTokenId);
    }

    /// @dev Validate DAO configuration values
    function _validateConfiguration(uint256 _proposalThreshold, uint256 _votingPeriod, uint256 _quorumVotes)
        internal
        pure
    {
        require(_proposalThreshold > 0, "Invalid proposal threshold");
        require(_votingPeriod >= MIN_VOTING_PERIOD && _votingPeriod <= MAX_VOTING_PERIOD, "Invalid voting period");
        require(_quorumVotes > 0, "Invalid quorum");
    }

    /// @dev Total votes cast reach the quorum
    function _quorumReached(Proposal storage proposal) internal view returns (bool) {
        return proposal.forVotes + proposal.againstVotes >= quorumVotes;
    }

    /// @dev For votes exceed the approval threshold (5000 bps = forVotes > againstVotes)
    function _approvalReached(Proposal storage proposal) internal view returns (bool) {
        return proposal.forVotes * BPS > (proposal.forVotes + proposal.againstVotes) * approvalThresholdBps;
    }

    /// @dev Funding proposals need enough positive peer reviews; other types do not
    function _reviewsPassed(Proposal storage proposal) internal view returns (bool) {
        if (proposal.proposalType != ProposalType.Funding) return true;
        return proposal.positiveReviews >= minReviews && proposal.positiveReviews > proposal.negativeReviews;
    }
}
