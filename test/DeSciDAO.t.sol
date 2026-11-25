// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "./DeSciBase.t.sol";

/**
 * @title DeSciDAOTest
 * @author Jose Imoberdorf
 * @dev Tests for DeSciDAO: proposals, peer review, voting, execution, cancellation,
 *      states and configuration.
 */
contract DeSciDAOTest is DeSciBase {
    // =====================================================
    // Constructor
    // =====================================================

    // Test the constructor wires the contracts and configuration
    function testConstructorSetsConfiguration() public view {
        assertEq(address(dao.governanceToken()), address(token));
        assertEq(address(dao.treasury()), address(treasury));
        assertEq(address(dao.grantManager()), address(grants));
        assertEq(address(dao.researchIPNFT()), address(ipnft));
        assertEq(address(dao.reviewerRegistry()), address(registry));
        assertEq(dao.proposalThreshold(), PROPOSAL_THRESHOLD);
        assertEq(dao.votingPeriod(), VOTING_PERIOD);
        assertEq(dao.quorumVotes(), QUORUM_VOTES);
        assertEq(dao.minReviews(), 1);
        assertEq(dao.owner(), owner);
    }

    // Test the constructor reverts with zero contract addresses
    function testConstructorRevertsZeroAddresses() public {
        vm.expectRevert("Invalid token address");
        new DeSciDAO(address(0), address(treasury), address(grants), address(ipnft), address(registry), 1, 1 days, 1);
        vm.expectRevert("Invalid treasury address");
        new DeSciDAO(address(token), address(0), address(grants), address(ipnft), address(registry), 1, 1 days, 1);
        vm.expectRevert("Invalid grant manager address");
        new DeSciDAO(address(token), address(treasury), address(0), address(ipnft), address(registry), 1, 1 days, 1);
        vm.expectRevert("Invalid IP-NFT address");
        new DeSciDAO(address(token), address(treasury), address(grants), address(0), address(registry), 1, 1 days, 1);
        vm.expectRevert("Invalid reviewer registry address");
        new DeSciDAO(address(token), address(treasury), address(grants), address(ipnft), address(0), 1, 1 days, 1);
    }

    // Test the constructor reverts with an invalid configuration
    function testConstructorRevertsInvalidConfiguration() public {
        vm.expectRevert("Invalid proposal threshold");
        new DeSciDAO(
            address(token), address(treasury), address(grants), address(ipnft), address(registry), 0, 1 days, 1
        );
        vm.expectRevert("Invalid voting period");
        new DeSciDAO(
            address(token), address(treasury), address(grants), address(ipnft), address(registry), 1, 1 days - 1, 1
        );
        vm.expectRevert("Invalid voting period");
        new DeSciDAO(
            address(token), address(treasury), address(grants), address(ipnft), address(registry), 1, 30 days + 1, 1
        );
        vm.expectRevert("Invalid quorum");
        new DeSciDAO(
            address(token), address(treasury), address(grants), address(ipnft), address(registry), 1, 1 days, 0
        );
    }

    // =====================================================
    // proposeFunding
    // =====================================================

    // Test creating a funding proposal stores all its data
    function testProposeFunding() public {
        uint256 start = block.timestamp;
        uint256 proposalId = _proposeFunding();

        DeSciDAO.Proposal memory p = dao.getProposal(proposalId);
        assertEq(proposalId, 0);
        assertEq(uint256(p.proposalType), uint256(DeSciDAO.ProposalType.Funding));
        assertEq(p.proposer, alice);
        assertEq(p.target, researcher);
        assertEq(p.token, address(usdc));
        assertEq(p.amount, GRANT_TOTAL);
        assertEq(p.documentHash, PLAN_HASH);
        assertEq(p.startTime, start);
        assertEq(p.endTime, start + VOTING_PERIOD);
        assertEq(p.snapshot, start - 1);
        assertEq(p.eta, start + VOTING_PERIOD);
        assertEq(p.expiresAt, start + VOTING_PERIOD + 14 days);
        assertEq(dao.getMilestones(proposalId).length, 3);
        assertEq(dao.getMilestones(proposalId)[2], M3);
        assertEq(dao.latestProposalIds(alice), 1);
        assertEq(uint256(dao.state(proposalId)), uint256(DeSciDAO.ProposalState.Active));
    }

    // Test proposeFunding reverts with invalid parameters
    function testProposeFundingRevertsInvalidParameters() public {
        uint256[] memory amounts = _milestones();
        vm.startPrank(alice);
        vm.expectRevert("Invalid researcher address");
        dao.proposeFunding("X", address(0), address(usdc), amounts, PLAN_HASH);
        vm.expectRevert("Invalid token address");
        dao.proposeFunding("X", researcher, address(0), amounts, PLAN_HASH);
        vm.expectRevert("Invalid document hash");
        dao.proposeFunding("X", researcher, address(usdc), amounts, bytes32(0));
        vm.stopPrank();
    }

    // Test proposeFunding reverts with zero or too many milestones
    function testProposeFundingRevertsInvalidMilestoneCount() public {
        vm.startPrank(alice);
        vm.expectRevert("Invalid milestone count");
        dao.proposeFunding("X", researcher, address(usdc), new uint256[](0), PLAN_HASH);

        uint256[] memory tooMany = new uint256[](11);
        for (uint256 i = 0; i < 11; i++) {
            tooMany[i] = 1;
        }
        vm.expectRevert("Invalid milestone count");
        dao.proposeFunding("X", researcher, address(usdc), tooMany, PLAN_HASH);
        vm.stopPrank();
    }

    // Test proposeFunding reverts with a zero milestone amount
    function testProposeFundingRevertsZeroMilestone() public {
        uint256[] memory amounts = _milestones();
        amounts[1] = 0;
        vm.prank(alice);
        vm.expectRevert("Milestone amount must be greater than 0");
        dao.proposeFunding("X", researcher, address(usdc), amounts, PLAN_HASH);
    }

    // Test proposeFunding reverts when the treasury cannot cover the grant
    function testProposeFundingRevertsInsufficientTreasuryFunds() public {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = TREASURY_USDC + 1;
        vm.prank(alice);
        vm.expectRevert("Insufficient treasury funds");
        dao.proposeFunding("X", researcher, address(usdc), amounts, PLAN_HASH);
    }

    // Test creating a proposal reverts without enough voting power at the snapshot
    function testProposeRevertsInsufficientVotingPower() public {
        vm.prank(researcher); // no tokens
        vm.expectRevert("Insufficient voting power to create proposal");
        dao.proposeFunding("X", researcher, address(usdc), _milestones(), PLAN_HASH);
    }

    // Test creating a proposal reverts with an empty description
    function testProposeRevertsEmptyDescription() public {
        vm.prank(alice);
        vm.expectRevert("Description cannot be empty");
        dao.proposeFunding("", researcher, address(usdc), _milestones(), PLAN_HASH);
    }

    // Test a proposer cannot create a second proposal while one is active
    function testProposeRevertsWhileActive() public {
        _proposeFunding();
        vm.prank(alice);
        vm.expectRevert("Proposer already has an active proposal");
        dao.proposeFunding("Y", researcher, address(usdc), _milestones(), PLAN_HASH);
    }

    // Test a proposer can create a new proposal after voting ends
    function testProposeAllowedAfterVotingEnds() public {
        _proposeFunding();
        vm.warp(block.timestamp + VOTING_PERIOD);
        uint256 second = _proposeFunding();
        assertEq(second, 1);
        assertEq(dao.latestProposalIds(alice), 2);
    }

    // =====================================================
    // proposeCancelGrant and proposeReviewerChange
    // =====================================================

    // Test proposing to cancel an active grant
    function testProposeCancelGrant() public {
        (, uint256 grantId) = _fundResearch();
        vm.prank(bob);
        uint256 proposalId = dao.proposeCancelGrant("Project abandoned", grantId);

        DeSciDAO.Proposal memory p = dao.getProposal(proposalId);
        assertEq(uint256(p.proposalType), uint256(DeSciDAO.ProposalType.CancelGrant));
        assertEq(p.grantId, grantId);
    }

    // Test proposing to cancel an inactive grant reverts
    function testProposeCancelGrantRevertsInactiveGrant() public {
        vm.prank(alice);
        vm.expectRevert("Grant is not active");
        dao.proposeCancelGrant("No grant", 99);
    }

    // Test proposing to add and remove reviewers
    function testProposeReviewerChange() public {
        address newReviewer = address(0x8);
        vm.prank(alice);
        uint256 addId = dao.proposeReviewerChange("Add expert", newReviewer, true);
        vm.prank(bob);
        uint256 removeId = dao.proposeReviewerChange("Remove reviewer", reviewer2, false);

        assertEq(uint256(dao.getProposal(addId).proposalType), uint256(DeSciDAO.ProposalType.AddReviewer));
        assertEq(dao.getProposal(addId).target, newReviewer);
        assertEq(uint256(dao.getProposal(removeId).proposalType), uint256(DeSciDAO.ProposalType.RemoveReviewer));
    }

    // Test reviewer change proposals revert with invalid reviewers
    function testProposeReviewerChangeRevertsInvalid() public {
        vm.startPrank(alice);
        vm.expectRevert("Invalid reviewer address");
        dao.proposeReviewerChange("X", address(0), true);
        vm.expectRevert("Already a reviewer");
        dao.proposeReviewerChange("X", reviewer1, true);
        vm.expectRevert("Not a reviewer");
        dao.proposeReviewerChange("X", address(0x8), false);
        vm.stopPrank();
    }

    // =====================================================
    // vote
    // =====================================================

    // Test voting for and against a proposal
    function testVoteForAndAgainst() public {
        uint256 proposalId = _proposeFunding();
        vm.prank(alice);
        dao.vote(proposalId, true);
        vm.prank(bob);
        dao.vote(proposalId, false);

        DeSciDAO.Proposal memory p = dao.getProposal(proposalId);
        assertEq(p.forVotes, 50000 * 10 ** 18);
        assertEq(p.againstVotes, 30000 * 10 ** 18);
        (bool voted, bool support) = dao.getVoteInfo(proposalId, bob);
        assertTrue(voted);
        assertFalse(support);
    }

    // Test vote reverts in every invalid case
    function testVoteReverts() public {
        vm.expectRevert("Proposal does not exist");
        dao.vote(99, true);

        uint256 proposalId = _proposeFunding();
        vm.prank(researcher); // no tokens
        vm.expectRevert("No voting power");
        dao.vote(proposalId, true);

        _voteFor(proposalId);
        vm.prank(bob);
        vm.expectRevert("Already voted");
        dao.vote(proposalId, true);

        vm.warp(block.timestamp + VOTING_PERIOD);
        vm.prank(alice);
        vm.expectRevert("Voting ended");
        dao.vote(proposalId, true);
    }

    // Test voting on a canceled proposal reverts
    function testVoteRevertsCanceled() public {
        uint256 proposalId = _proposeFunding();
        vm.prank(alice);
        dao.cancelProposal(proposalId);
        vm.prank(bob);
        vm.expectRevert("Proposal is canceled");
        dao.vote(proposalId, true);
    }

    // Test the same tokens cannot vote twice after a transfer (snapshot voting)
    function testDoubleVoteWithTransferIsBlocked() public {
        address attackerWallet = address(0xB);
        uint256 proposalId = _proposeFunding();
        vm.prank(alice);
        dao.vote(proposalId, true);

        vm.prank(alice);
        assertTrue(token.transfer(attackerWallet, 50000 * 10 ** 18));
        vm.prank(attackerWallet);
        token.delegate(attackerWallet);

        vm.prank(attackerWallet);
        vm.expectRevert("No voting power");
        dao.vote(proposalId, true);
    }

    // =====================================================
    // reviewProposal
    // =====================================================

    // Test positive and negative peer reviews are counted and recorded
    function testReviewProposal() public {
        uint256 proposalId = _proposeFunding();
        _review(proposalId, reviewer1, true);
        _review(proposalId, reviewer2, false);

        DeSciDAO.Proposal memory p = dao.getProposal(proposalId);
        assertEq(p.positiveReviews, 1);
        assertEq(p.negativeReviews, 1);
        assertTrue(dao.hasReviewed(proposalId, reviewer1));
        assertEq(registry.reviewCount(reviewer1), 1);
        assertEq(registry.reviewCount(reviewer2), 1);
    }

    // Test reviewProposal reverts for nonexistent and non-funding proposals
    function testReviewRevertsProposalType() public {
        vm.prank(reviewer1);
        vm.expectRevert("Proposal does not exist");
        dao.reviewProposal(99, REPORT_HASH, true);

        vm.prank(alice);
        uint256 proposalId = dao.proposeReviewerChange("Add expert", address(0x8), true);
        vm.prank(reviewer1);
        vm.expectRevert("Only funding proposals are reviewed");
        dao.reviewProposal(proposalId, REPORT_HASH, true);
    }

    // Test reviewProposal reverts after voting ends or when canceled
    function testReviewRevertsTiming() public {
        uint256 proposalId = _proposeFunding();
        vm.prank(alice);
        dao.cancelProposal(proposalId);
        vm.prank(reviewer1);
        vm.expectRevert("Proposal is canceled");
        dao.reviewProposal(proposalId, REPORT_HASH, true);

        vm.warp(block.timestamp + VOTING_PERIOD);
        vm.prank(reviewer1);
        vm.expectRevert("Review period ended");
        dao.reviewProposal(proposalId, REPORT_HASH, true);
    }

    // Test reviewProposal reverts for non-reviewers and conflicts of interest
    function testReviewRevertsReviewer() public {
        uint256 proposalId = _proposeFunding();
        vm.prank(bob);
        vm.expectRevert("Not a reviewer");
        dao.reviewProposal(proposalId, REPORT_HASH, true);

        // The researcher becomes a reviewer but cannot review their own grant
        vm.prank(address(dao));
        registry.addReviewer(researcher);
        vm.prank(researcher);
        vm.expectRevert("Conflict of interest");
        dao.reviewProposal(proposalId, REPORT_HASH, true);
    }

    // Test reviewProposal reverts when reviewing twice or without a report
    function testReviewRevertsDuplicateAndEmptyReport() public {
        uint256 proposalId = _proposeFunding();
        vm.prank(reviewer1);
        vm.expectRevert("Invalid report hash");
        dao.reviewProposal(proposalId, bytes32(0), true);

        _review(proposalId, reviewer1, true);
        vm.prank(reviewer1);
        vm.expectRevert("Already reviewed");
        dao.reviewProposal(proposalId, REPORT_HASH, true);
    }

    // =====================================================
    // executeProposal
    // =====================================================

    // Test executing a funding proposal moves funds, creates the grant and mints the IP-NFT
    function testExecuteFunding() public {
        (uint256 proposalId, uint256 grantId) = _fundResearch();

        assertEq(uint256(dao.state(proposalId)), uint256(DeSciDAO.ProposalState.Executed));
        assertEq(usdc.balanceOf(address(treasury)), TREASURY_USDC - GRANT_TOTAL);
        assertEq(usdc.balanceOf(address(grants)), GRANT_TOTAL);
        assertTrue(treasury.isProposalExecuted(proposalId));

        MilestoneGrant.Grant memory g = grants.getGrant(grantId);
        assertEq(g.proposalId, proposalId);
        assertEq(g.researcher, researcher);
        assertEq(g.totalAmount, GRANT_TOTAL);
        assertEq(g.milestoneCount, 3);

        uint256 ipTokenId = dao.ipTokenOfProposal(proposalId);
        assertEq(ipnft.ownerOf(ipTokenId), address(treasury));
        assertEq(ipnft.researcherOf(ipTokenId), researcher);
    }

    // Test executing a cancel grant proposal refunds the treasury
    function testExecuteCancelGrant() public {
        (, uint256 grantId) = _fundResearch();
        vm.prank(bob);
        uint256 proposalId = dao.proposeCancelGrant("Project abandoned", grantId);
        vm.prank(alice);
        dao.vote(proposalId, true);
        vm.warp(block.timestamp + VOTING_PERIOD);
        dao.executeProposal(proposalId);

        assertFalse(grants.isGrantActive(grantId));
        assertEq(usdc.balanceOf(address(treasury)), TREASURY_USDC);
    }

    // Test executing reviewer proposals adds and removes reviewers
    function testExecuteReviewerChanges() public {
        address newReviewer = address(0x8);
        vm.prank(alice);
        uint256 addId = dao.proposeReviewerChange("Add expert", newReviewer, true);
        vm.prank(bob);
        uint256 removeId = dao.proposeReviewerChange("Remove reviewer", reviewer2, false);
        vm.prank(owner);
        dao.vote(addId, true);
        vm.prank(owner);
        dao.vote(removeId, true);
        vm.warp(block.timestamp + VOTING_PERIOD);

        dao.executeProposal(addId);
        dao.executeProposal(removeId);
        assertTrue(registry.isReviewer(newReviewer));
        assertFalse(registry.isReviewer(reviewer2));
    }

    // Test executeProposal reverts before the end, when executed twice and when canceled
    function testExecuteRevertsLifecycle() public {
        vm.expectRevert("Proposal does not exist");
        dao.executeProposal(99);

        uint256 proposalId = _proposeFunding();
        vm.expectRevert("Voting not ended");
        dao.executeProposal(proposalId);

        vm.prank(alice);
        dao.cancelProposal(proposalId);
        vm.warp(block.timestamp + VOTING_PERIOD);
        vm.expectRevert("Proposal is canceled");
        dao.executeProposal(proposalId);

        (uint256 funded,) = _fundResearch();
        vm.expectRevert("Proposal already executed");
        dao.executeProposal(funded);
    }

    // Test executeProposal reverts without quorum or approval
    function testExecuteRevertsVotes() public {
        uint256 proposalId = _proposeFunding(); // nobody votes
        _review(proposalId, reviewer1, true);
        vm.warp(block.timestamp + VOTING_PERIOD);
        vm.expectRevert("Quorum not reached");
        dao.executeProposal(proposalId);

        uint256 second = _proposeFunding();
        _review(second, reviewer1, true);
        vm.prank(alice);
        dao.vote(second, false); // 50K against
        _voteFor(second); // 30K for
        vm.warp(block.timestamp + VOTING_PERIOD);
        vm.expectRevert("Proposal not passed");
        dao.executeProposal(second);
    }

    // Test funding proposals need enough positive peer reviews
    function testExecuteRevertsInsufficientReviews() public {
        uint256 proposalId = _proposeFunding(); // no reviews
        _voteFor(proposalId);
        vm.warp(block.timestamp + VOTING_PERIOD);
        assertEq(uint256(dao.state(proposalId)), uint256(DeSciDAO.ProposalState.Defeated));
        vm.expectRevert("Insufficient positive reviews");
        dao.executeProposal(proposalId);
    }

    // Test a tie between positive and negative reviews defeats the proposal
    function testExecuteRevertsReviewTie() public {
        uint256 proposalId = _proposeFunding();
        _review(proposalId, reviewer1, true);
        _review(proposalId, reviewer2, false);
        _voteFor(proposalId);
        vm.warp(block.timestamp + VOTING_PERIOD);
        vm.expectRevert("Insufficient positive reviews");
        dao.executeProposal(proposalId);
    }

    // Test executeProposal respects the execution delay and the grace period
    function testExecuteRevertsExecutionWindow() public {
        vm.prank(owner);
        dao.updateExecutionRules(5000, 2 days, 7 days);
        uint256 proposalId = _proposeFunding();
        _review(proposalId, reviewer1, true);
        _voteFor(proposalId);
        vm.warp(block.timestamp + VOTING_PERIOD);

        assertEq(uint256(dao.state(proposalId)), uint256(DeSciDAO.ProposalState.Queued));
        vm.expectRevert("Execution delay not elapsed");
        dao.executeProposal(proposalId);

        vm.warp(dao.getProposal(proposalId).expiresAt);
        assertEq(uint256(dao.state(proposalId)), uint256(DeSciDAO.ProposalState.Expired));
        vm.expectRevert("Proposal expired");
        dao.executeProposal(proposalId);
    }

    // =====================================================
    // cancelProposal
    // =====================================================

    // Test the proposer and the owner can cancel proposals
    function testCancelByProposerAndOwner() public {
        uint256 proposalId = _proposeFunding();
        vm.prank(alice);
        dao.cancelProposal(proposalId);
        assertEq(uint256(dao.state(proposalId)), uint256(DeSciDAO.ProposalState.Canceled));

        vm.prank(bob);
        uint256 second = dao.proposeReviewerChange("Add expert", address(0x8), true);
        vm.prank(owner);
        dao.cancelProposal(second);
        assertTrue(dao.getProposal(second).canceled);
    }

    // Test anyone can cancel when the proposer drops below the threshold
    function testCancelWhenProposerBelowThreshold() public {
        uint256 proposalId = _proposeFunding();
        vm.prank(alice);
        token.delegate(bob); // alice keeps her tokens but has no votes

        vm.prank(researcher);
        dao.cancelProposal(proposalId);
        assertTrue(dao.getProposal(proposalId).canceled);
    }

    // Test cancelProposal reverts in every invalid case
    function testCancelReverts() public {
        vm.expectRevert("Proposal does not exist");
        dao.cancelProposal(99);

        uint256 proposalId = _proposeFunding();
        vm.prank(bob);
        vm.expectRevert("Not authorized to cancel");
        dao.cancelProposal(proposalId);

        vm.prank(alice);
        dao.cancelProposal(proposalId);
        vm.prank(alice);
        vm.expectRevert("Proposal already canceled");
        dao.cancelProposal(proposalId);

        (uint256 funded,) = _fundResearch();
        vm.prank(owner);
        vm.expectRevert("Proposal already executed");
        dao.cancelProposal(funded);
    }

    // =====================================================
    // Views
    // =====================================================

    // Test state and getProposal revert for nonexistent proposals
    function testViewsRevertProposalDoesNotExist() public {
        vm.expectRevert("Proposal does not exist");
        dao.state(99);
        vm.expectRevert("Proposal does not exist");
        dao.getProposal(99);
    }

    // Test state is Succeeded when the proposal can be executed
    function testStateSucceeded() public {
        uint256 proposalId = _proposeFunding();
        _review(proposalId, reviewer1, true);
        _voteFor(proposalId);
        vm.warp(block.timestamp + VOTING_PERIOD);
        assertEq(uint256(dao.state(proposalId)), uint256(DeSciDAO.ProposalState.Succeeded));
    }

    // Test state is Defeated without quorum
    function testStateDefeatedWithoutQuorum() public {
        uint256 proposalId = _proposeFunding();
        vm.warp(block.timestamp + VOTING_PERIOD);
        assertEq(uint256(dao.state(proposalId)), uint256(DeSciDAO.ProposalState.Defeated));
    }

    // =====================================================
    // Configuration
    // =====================================================

    // Test the owner updating the configuration
    function testUpdateConfiguration() public {
        vm.prank(owner);
        dao.updateConfiguration(2000 * 10 ** 18, 5 days, 20000 * 10 ** 18);
        assertEq(dao.proposalThreshold(), 2000 * 10 ** 18);
        assertEq(dao.votingPeriod(), 5 days);
        assertEq(dao.quorumVotes(), 20000 * 10 ** 18);
    }

    // Test updateConfiguration reverts for non-owners and invalid values
    function testUpdateConfigurationReverts() public {
        vm.prank(alice);
        vm.expectRevert(_notOwner(alice));
        dao.updateConfiguration(1, 1 days, 1);

        vm.prank(owner);
        vm.expectRevert("Invalid voting period");
        dao.updateConfiguration(1, 31 days, 1);
    }

    // Test the owner updating the execution rules
    function testUpdateExecutionRules() public {
        vm.prank(owner);
        dao.updateExecutionRules(6000, 2 days, 30 days);
        assertEq(dao.approvalThresholdBps(), 6000);
        assertEq(dao.executionDelay(), 2 days);
        assertEq(dao.gracePeriod(), 30 days);
    }

    // Test updateExecutionRules reverts with values out of bounds
    function testUpdateExecutionRulesReverts() public {
        vm.startPrank(owner);
        vm.expectRevert("Invalid approval threshold");
        dao.updateExecutionRules(4999, 0, 14 days);
        vm.expectRevert("Invalid approval threshold");
        dao.updateExecutionRules(9001, 0, 14 days);
        vm.expectRevert("Invalid execution delay");
        dao.updateExecutionRules(5000, 30 days + 1, 14 days);
        vm.expectRevert("Invalid grace period");
        dao.updateExecutionRules(5000, 0, 1 days - 1);
        vm.expectRevert("Invalid grace period");
        dao.updateExecutionRules(5000, 0, 90 days + 1);
        vm.stopPrank();
    }

    // Test a higher approval threshold defeats a simple majority
    function testHigherApprovalThreshold() public {
        vm.prank(owner);
        dao.updateExecutionRules(7000, 0, 14 days); // 70% required
        uint256 proposalId = _proposeFunding();
        _review(proposalId, reviewer1, true);
        vm.prank(alice);
        dao.vote(proposalId, true); // 50K for
        vm.prank(bob);
        dao.vote(proposalId, false); // 30K against (62.5% for)
        vm.warp(block.timestamp + VOTING_PERIOD);
        assertEq(uint256(dao.state(proposalId)), uint256(DeSciDAO.ProposalState.Defeated));
    }

    // Test the owner updating the minimum reviews
    function testSetMinReviews() public {
        vm.prank(owner);
        dao.setMinReviews(2);
        assertEq(dao.minReviews(), 2);

        uint256 proposalId = _proposeFunding();
        _review(proposalId, reviewer1, true); // only 1 of 2 required reviews
        _voteFor(proposalId);
        vm.warp(block.timestamp + VOTING_PERIOD);
        vm.expectRevert("Insufficient positive reviews");
        dao.executeProposal(proposalId);
    }

    // Test setMinReviews reverts for non-owners and values out of bounds
    function testSetMinReviewsReverts() public {
        vm.prank(alice);
        vm.expectRevert(_notOwner(alice));
        dao.setMinReviews(2);

        vm.startPrank(owner);
        vm.expectRevert("Invalid min reviews");
        dao.setMinReviews(0);
        vm.expectRevert("Invalid min reviews");
        dao.setMinReviews(6);
        vm.stopPrank();
    }
}
