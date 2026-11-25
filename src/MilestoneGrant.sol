// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IDeSci.sol";

/**
 * @title MilestoneGrant
 * @author Jose Imoberdorf
 * @dev Escrow that pays research grants by milestones.
 *
 *  - The DAO moves the grant funds from the treasury to this contract and creates the grant.
 *  - The researcher submits each milestone deliverable (hash of the report or data).
 *  - Registered reviewers approve it; after `requiredApprovals` approvals the
 *    milestone amount is released to the researcher.
 *  - Milestones are paid in order. The DAO can cancel a grant: the unreleased
 *    funds go back to the treasury.
 */
contract MilestoneGrant is Ownable {
    using SafeERC20 for IERC20;

    enum MilestoneStatus {
        Pending, // Waiting for the deliverable
        Submitted, // Deliverable submitted, waiting for reviewer approvals
        Released // Approved and paid
    }

    struct Milestone {
        uint256 amount;
        bytes32 deliverableHash;
        MilestoneStatus status;
        uint256 approvals;
    }

    struct Grant {
        uint256 proposalId; // DAO proposal that funded the grant
        address researcher; // Receiver of the milestone payments
        address token; // Payment token (e.g. USDC)
        uint256 totalAmount; // Sum of all milestones
        uint256 releasedAmount; // Amount already paid
        uint256 milestoneCount; // Number of milestones
        uint256 nextMilestone; // Index of the milestone in progress
        bool canceled; // Canceled by the DAO
        bytes32 researchPlanHash; // Hash of the approved research plan
    }

    // Limits
    uint256 public constant MAX_MILESTONES = 10;
    uint256 public constant MAX_REQUIRED_APPROVALS = 5;

    // Connected contracts
    address public dao;
    address public immutable treasury;
    IReviewerRegistry public immutable reviewerRegistry;

    // Reviewer approvals needed to release a milestone
    uint256 public requiredApprovals = 1;

    // Number of grants created (also the next grant ID)
    uint256 public grantCount;

    // Funds committed to active grants, per token
    mapping(address => uint256) public lockedFunds;

    mapping(uint256 => Grant) private grants;
    mapping(uint256 => mapping(uint256 => Milestone)) private milestones;
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public hasApproved;

    // Events
    event DAOSet(address indexed dao);
    event RequiredApprovalsUpdated(uint256 requiredApprovals);
    event GrantCreated(
        uint256 indexed grantId,
        uint256 indexed proposalId,
        address indexed researcher,
        address token,
        uint256 totalAmount,
        uint256 milestoneCount
    );
    event MilestoneSubmitted(uint256 indexed grantId, uint256 indexed milestoneIndex, bytes32 deliverableHash);
    event MilestoneApproved(uint256 indexed grantId, uint256 indexed milestoneIndex, address indexed reviewer);
    event MilestoneReleased(uint256 indexed grantId, uint256 indexed milestoneIndex, uint256 amount);
    event GrantCanceled(uint256 indexed grantId, uint256 refundedAmount);

    /**
     * @dev Constructor
     * @param _treasury Treasury that receives refunds of canceled grants
     * @param _reviewerRegistry Registry of reviewers allowed to approve milestones
     */
    constructor(address _treasury, address _reviewerRegistry) Ownable(msg.sender) {
        require(_treasury != address(0), "Invalid treasury address");
        require(_reviewerRegistry != address(0), "Invalid reviewer registry address");
        treasury = _treasury;
        reviewerRegistry = IReviewerRegistry(_reviewerRegistry);
    }

    /**
     * @dev Set the DAO allowed to create and cancel grants (only owner)
     * @param _dao DAO address
     */
    function setDAO(address _dao) external onlyOwner {
        require(_dao != address(0), "Invalid DAO address");
        dao = _dao;
        emit DAOSet(_dao);
    }

    /**
     * @dev Set the number of reviewer approvals needed per milestone (only owner)
     * @param _requiredApprovals Number of approvals (1 to MAX_REQUIRED_APPROVALS)
     */
    function setRequiredApprovals(uint256 _requiredApprovals) external onlyOwner {
        require(_requiredApprovals > 0 && _requiredApprovals <= MAX_REQUIRED_APPROVALS, "Invalid required approvals");
        requiredApprovals = _requiredApprovals;
        emit RequiredApprovalsUpdated(_requiredApprovals);
    }

    /**
     * @dev Create a grant (only DAO). The funds must already be in this contract.
     * @param proposalId DAO proposal that funded the grant
     * @param researcher Receiver of the milestone payments
     * @param token Payment token
     * @param milestoneAmounts Amount of each milestone
     * @param researchPlanHash Hash of the approved research plan
     * @return grantId ID of the new grant
     */
    function createGrant(
        uint256 proposalId,
        address researcher,
        address token,
        uint256[] calldata milestoneAmounts,
        bytes32 researchPlanHash
    ) external returns (uint256 grantId) {
        require(msg.sender == dao, "Only DAO");
        require(researcher != address(0), "Invalid researcher address");
        require(token != address(0), "Invalid token address");
        uint256 count = milestoneAmounts.length;
        require(count > 0 && count <= MAX_MILESTONES, "Invalid milestone count");

        grantId = grantCount++;
        uint256 total;
        for (uint256 i = 0; i < count; i++) {
            require(milestoneAmounts[i] > 0, "Milestone amount must be greater than 0");
            milestones[grantId][i].amount = milestoneAmounts[i];
            total += milestoneAmounts[i];
        }
        require(IERC20(token).balanceOf(address(this)) >= lockedFunds[token] + total, "Grant not funded");
        lockedFunds[token] += total;

        Grant storage grant = grants[grantId];
        grant.proposalId = proposalId;
        grant.researcher = researcher;
        grant.token = token;
        grant.totalAmount = total;
        grant.milestoneCount = count;
        grant.researchPlanHash = researchPlanHash;

        emit GrantCreated(grantId, proposalId, researcher, token, total, count);
    }

    /**
     * @dev Submit the deliverable of the current milestone (only researcher)
     * @param grantId ID of the grant
     * @param deliverableHash Hash of the report, data or results
     */
    function submitMilestone(uint256 grantId, bytes32 deliverableHash) external {
        Grant storage grant = grants[grantId];
        require(grant.researcher != address(0), "Grant does not exist");
        require(msg.sender == grant.researcher, "Only researcher");
        require(!grant.canceled, "Grant is canceled");
        require(grant.nextMilestone < grant.milestoneCount, "All milestones released");
        require(deliverableHash != bytes32(0), "Invalid deliverable hash");

        uint256 index = grant.nextMilestone;
        Milestone storage milestone = milestones[grantId][index];
        require(milestone.status == MilestoneStatus.Pending, "Milestone already submitted");

        milestone.deliverableHash = deliverableHash;
        milestone.status = MilestoneStatus.Submitted;
        emit MilestoneSubmitted(grantId, index, deliverableHash);
    }

    /**
     * @dev Approve the submitted milestone (only registered reviewers, not the researcher).
     *      Releases the payment once `requiredApprovals` is reached.
     * @param grantId ID of the grant
     */
    function approveMilestone(uint256 grantId) external {
        Grant storage grant = grants[grantId];
        require(grant.researcher != address(0), "Grant does not exist");
        require(!grant.canceled, "Grant is canceled");
        require(reviewerRegistry.isReviewer(msg.sender), "Not a reviewer");
        require(msg.sender != grant.researcher, "Researcher cannot approve");
        require(grant.nextMilestone < grant.milestoneCount, "All milestones released");

        uint256 index = grant.nextMilestone;
        Milestone storage milestone = milestones[grantId][index];
        require(milestone.status == MilestoneStatus.Submitted, "Milestone not submitted");
        require(!hasApproved[grantId][index][msg.sender], "Already approved");

        hasApproved[grantId][index][msg.sender] = true;
        milestone.approvals++;
        reviewerRegistry.recordReview(msg.sender);
        emit MilestoneApproved(grantId, index, msg.sender);

        if (milestone.approvals >= requiredApprovals) {
            milestone.status = MilestoneStatus.Released;
            grant.releasedAmount += milestone.amount;
            grant.nextMilestone++;
            lockedFunds[grant.token] -= milestone.amount;

            IERC20(grant.token).safeTransfer(grant.researcher, milestone.amount);
            emit MilestoneReleased(grantId, index, milestone.amount);
        }
    }

    /**
     * @dev Cancel a grant and refund the unreleased funds to the treasury (only DAO)
     * @param grantId ID of the grant
     */
    function cancelGrant(uint256 grantId) external {
        require(msg.sender == dao, "Only DAO");
        Grant storage grant = grants[grantId];
        require(grant.researcher != address(0), "Grant does not exist");
        require(!grant.canceled, "Grant already canceled");
        require(grant.nextMilestone < grant.milestoneCount, "Grant already completed");

        grant.canceled = true;
        uint256 refund = grant.totalAmount - grant.releasedAmount;
        lockedFunds[grant.token] -= refund;

        IERC20(grant.token).safeTransfer(treasury, refund);
        emit GrantCanceled(grantId, refund);
    }

    /**
     * @dev Whether a grant exists, is not canceled and still has milestones to pay
     * @param grantId ID of the grant
     * @return Whether the grant is active
     */
    function isGrantActive(uint256 grantId) external view returns (bool) {
        Grant storage grant = grants[grantId];
        return grant.researcher != address(0) && !grant.canceled && grant.nextMilestone < grant.milestoneCount;
    }

    /**
     * @dev Get a grant
     * @param grantId ID of the grant
     * @return Grant data
     */
    function getGrant(uint256 grantId) external view returns (Grant memory) {
        require(grants[grantId].researcher != address(0), "Grant does not exist");
        return grants[grantId];
    }

    /**
     * @dev Get a milestone of a grant
     * @param grantId ID of the grant
     * @param index Milestone index
     * @return Milestone data
     */
    function getMilestone(uint256 grantId, uint256 index) external view returns (Milestone memory) {
        require(index < grants[grantId].milestoneCount, "Milestone does not exist");
        return milestones[grantId][index];
    }
}
