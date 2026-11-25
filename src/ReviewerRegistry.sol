// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ReviewerRegistry
 * @author Jose Imoberdorf
 * @dev Registry of scientific reviewers of the DeSci DAO.
 *
 *  - Registered reviewers evaluate funding proposals (DeSciDAO) and approve
 *    milestone deliverables (MilestoneGrant).
 *  - Each review increases the reviewer's reputation (reviewCount). Reputation is
 *    not a token, so it cannot be transferred or sold.
 *  - After deployment, ownership is transferred to the DAO, so reviewers are
 *    added and removed through governance proposals.
 */
contract ReviewerRegistry is Ownable {
    // Whether an address is a registered reviewer
    mapping(address => bool) public isReviewer;

    // Non-transferable reputation: number of reviews recorded
    mapping(address => uint256) public reviewCount;

    // Contracts allowed to record reviews (DeSciDAO and MilestoneGrant)
    mapping(address => bool) public isRecorder;

    // Number of registered reviewers
    uint256 public reviewerCount;

    // Events
    event ReviewerAdded(address indexed reviewer);
    event ReviewerRemoved(address indexed reviewer);
    event RecorderUpdated(address indexed recorder, bool allowed);
    event ReviewRecorded(address indexed reviewer, uint256 reviewCount);

    /**
     * @dev Constructor
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Register a reviewer (only owner, i.e. the DAO after setup)
     * @param reviewer Address of the reviewer
     */
    function addReviewer(address reviewer) external onlyOwner {
        require(reviewer != address(0), "Invalid reviewer address");
        require(!isReviewer[reviewer], "Already a reviewer");

        isReviewer[reviewer] = true;
        reviewerCount++;
        emit ReviewerAdded(reviewer);
    }

    /**
     * @dev Remove a reviewer (only owner). Their reputation is kept.
     * @param reviewer Address of the reviewer
     */
    function removeReviewer(address reviewer) external onlyOwner {
        require(isReviewer[reviewer], "Not a reviewer");

        isReviewer[reviewer] = false;
        reviewerCount--;
        emit ReviewerRemoved(reviewer);
    }

    /**
     * @dev Allow or disallow a contract to record reviews (only owner)
     * @param recorder Contract address
     * @param allowed Whether it can record reviews
     */
    function setRecorder(address recorder, bool allowed) external onlyOwner {
        require(recorder != address(0), "Invalid recorder address");

        isRecorder[recorder] = allowed;
        emit RecorderUpdated(recorder, allowed);
    }

    /**
     * @dev Record a review and increase the reviewer's reputation (only recorders)
     * @param reviewer Address of the reviewer
     */
    function recordReview(address reviewer) external {
        require(isRecorder[msg.sender], "Not authorized to record");
        require(isReviewer[reviewer], "Not a reviewer");

        reviewCount[reviewer]++;
        emit ReviewRecorded(reviewer, reviewCount[reviewer]);
    }
}
