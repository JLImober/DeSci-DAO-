// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "./DeSciBase.t.sol";

/**
 * @title MilestoneGrantTest
 * @author Jose Imoberdorf
 * @dev Tests for MilestoneGrant: grant creation, milestone submission, reviewer
 *      approval, payment release and cancellation.
 */
contract MilestoneGrantTest is DeSciBase {
    // Researcher submits the deliverable of the current milestone
    function _submit(uint256 grantId) internal {
        vm.prank(researcher);
        grants.submitMilestone(grantId, DELIVERABLE_HASH);
    }

    // A reviewer approves the current milestone
    function _approve(uint256 grantId, address reviewer) internal {
        vm.prank(reviewer);
        grants.approveMilestone(grantId);
    }

    // Fund the grant contract directly and create a grant as the DAO
    function _createDirectGrant(uint256[] memory amounts) internal returns (uint256 grantId) {
        uint256 total;
        for (uint256 i = 0; i < amounts.length; i++) {
            total += amounts[i];
        }
        usdc.mint(address(grants), total);
        vm.prank(address(dao));
        grantId = grants.createGrant(7, researcher, address(usdc), amounts, PLAN_HASH);
    }

    // =====================================================
    // Configuration
    // =====================================================

    // Test the constructor and default configuration
    function testConstructorAndDefaults() public view {
        assertEq(grants.treasury(), address(treasury));
        assertEq(address(grants.reviewerRegistry()), address(registry));
        assertEq(grants.dao(), address(dao));
        assertEq(grants.requiredApprovals(), 1);
    }

    // Test the constructor reverts with zero addresses
    function testConstructorRevertsZeroAddresses() public {
        vm.expectRevert("Invalid treasury address");
        new MilestoneGrant(address(0), address(registry));
        vm.expectRevert("Invalid reviewer registry address");
        new MilestoneGrant(address(treasury), address(0));
    }

    // Test setDAO reverts for non-owners and the zero address
    function testSetDAOReverts() public {
        vm.prank(alice);
        vm.expectRevert(_notOwner(alice));
        grants.setDAO(alice);
        vm.prank(owner);
        vm.expectRevert("Invalid DAO address");
        grants.setDAO(address(0));
    }

    // Test the owner updating the required approvals within bounds
    function testSetRequiredApprovals() public {
        vm.startPrank(owner);
        grants.setRequiredApprovals(2);
        assertEq(grants.requiredApprovals(), 2);
        vm.expectRevert("Invalid required approvals");
        grants.setRequiredApprovals(0);
        vm.expectRevert("Invalid required approvals");
        grants.setRequiredApprovals(6);
        vm.stopPrank();
    }

    // =====================================================
    // createGrant
    // =====================================================

    // Test createGrant locks the funds and stores the grant
    function testCreateGrant() public {
        uint256 grantId = _createDirectGrant(_milestones());
        MilestoneGrant.Grant memory g = grants.getGrant(grantId);
        assertEq(g.proposalId, 7);
        assertEq(g.totalAmount, GRANT_TOTAL);
        assertEq(g.researchPlanHash, PLAN_HASH);
        assertEq(grants.lockedFunds(address(usdc)), GRANT_TOTAL);
        assertEq(grants.getMilestone(grantId, 1).amount, M2);
        assertTrue(grants.isGrantActive(grantId));
    }

    // Test createGrant reverts when not called by the DAO or with invalid data
    function testCreateGrantRevertsInvalid() public {
        uint256[] memory amounts = _milestones();
        vm.expectRevert("Only DAO");
        grants.createGrant(0, researcher, address(usdc), amounts, PLAN_HASH);

        vm.startPrank(address(dao));
        vm.expectRevert("Invalid researcher address");
        grants.createGrant(0, address(0), address(usdc), amounts, PLAN_HASH);
        vm.expectRevert("Invalid token address");
        grants.createGrant(0, researcher, address(0), amounts, PLAN_HASH);
        vm.expectRevert("Invalid milestone count");
        grants.createGrant(0, researcher, address(usdc), new uint256[](0), PLAN_HASH);
        vm.expectRevert("Invalid milestone count");
        grants.createGrant(0, researcher, address(usdc), new uint256[](11), PLAN_HASH);
        amounts[0] = 0;
        vm.expectRevert("Milestone amount must be greater than 0");
        grants.createGrant(0, researcher, address(usdc), amounts, PLAN_HASH);
        vm.stopPrank();
    }

    // Test createGrant reverts when the funds are not in the contract
    function testCreateGrantRevertsNotFunded() public {
        vm.prank(address(dao));
        vm.expectRevert("Grant not funded");
        grants.createGrant(0, researcher, address(usdc), _milestones(), PLAN_HASH);
    }

    // =====================================================
    // submitMilestone and approveMilestone
    // =====================================================

    // Test the full milestone flow pays every milestone in order
    function testMilestonesReleasedInOrder() public {
        (, uint256 grantId) = _fundResearch();

        _submit(grantId);
        assertEq(uint256(grants.getMilestone(grantId, 0).status), uint256(MilestoneGrant.MilestoneStatus.Submitted));
        _approve(grantId, reviewer1);
        assertEq(usdc.balanceOf(researcher), M1);
        assertEq(uint256(grants.getMilestone(grantId, 0).status), uint256(MilestoneGrant.MilestoneStatus.Released));

        _submit(grantId);
        _approve(grantId, reviewer2);
        _submit(grantId);
        _approve(grantId, reviewer1);

        MilestoneGrant.Grant memory g = grants.getGrant(grantId);
        assertEq(usdc.balanceOf(researcher), GRANT_TOTAL);
        assertEq(g.releasedAmount, GRANT_TOTAL);
        assertEq(g.nextMilestone, 3);
        assertEq(grants.lockedFunds(address(usdc)), 0);
        assertFalse(grants.isGrantActive(grantId));
        assertEq(registry.reviewCount(reviewer1), 3); // 1 proposal review + 2 milestone approvals
    }

    // Test a milestone needs the required number of approvals
    function testMilestoneNeedsRequiredApprovals() public {
        vm.prank(owner);
        grants.setRequiredApprovals(2);
        (, uint256 grantId) = _fundResearch();

        _submit(grantId);
        _approve(grantId, reviewer1);
        assertEq(usdc.balanceOf(researcher), 0); // 1 of 2 approvals
        assertEq(grants.getMilestone(grantId, 0).approvals, 1);
        _approve(grantId, reviewer2);
        assertEq(usdc.balanceOf(researcher), M1);
    }

    // Test submitMilestone reverts in every invalid case
    function testSubmitMilestoneReverts() public {
        vm.expectRevert("Grant does not exist");
        grants.submitMilestone(99, DELIVERABLE_HASH);

        uint256[] memory one = new uint256[](1);
        one[0] = M1;
        uint256 grantId = _createDirectGrant(one);

        vm.prank(alice);
        vm.expectRevert("Only researcher");
        grants.submitMilestone(grantId, DELIVERABLE_HASH);

        vm.prank(researcher);
        vm.expectRevert("Invalid deliverable hash");
        grants.submitMilestone(grantId, bytes32(0));

        _submit(grantId);
        vm.prank(researcher);
        vm.expectRevert("Milestone already submitted");
        grants.submitMilestone(grantId, DELIVERABLE_HASH);

        _approve(grantId, reviewer1);
        vm.prank(researcher);
        vm.expectRevert("All milestones released");
        grants.submitMilestone(grantId, DELIVERABLE_HASH);
    }

    // Test submitMilestone reverts on a canceled grant
    function testSubmitMilestoneRevertsCanceled() public {
        uint256 grantId = _createDirectGrant(_milestones());
        vm.prank(address(dao));
        grants.cancelGrant(grantId);
        vm.prank(researcher);
        vm.expectRevert("Grant is canceled");
        grants.submitMilestone(grantId, DELIVERABLE_HASH);
    }

    // Test approveMilestone reverts in every invalid case
    function testApproveMilestoneReverts() public {
        vm.expectRevert("Grant does not exist");
        grants.approveMilestone(99);

        uint256[] memory one = new uint256[](1);
        one[0] = M1;
        uint256 grantId = _createDirectGrant(one);

        vm.prank(alice);
        vm.expectRevert("Not a reviewer");
        grants.approveMilestone(grantId);

        vm.prank(address(dao));
        registry.addReviewer(researcher);
        vm.prank(researcher);
        vm.expectRevert("Researcher cannot approve");
        grants.approveMilestone(grantId);

        vm.prank(reviewer1);
        vm.expectRevert("Milestone not submitted");
        grants.approveMilestone(grantId);

        vm.prank(owner);
        grants.setRequiredApprovals(2);
        _submit(grantId);
        _approve(grantId, reviewer1);
        vm.prank(reviewer1);
        vm.expectRevert("Already approved");
        grants.approveMilestone(grantId);

        _approve(grantId, reviewer2); // releases the only milestone
        vm.prank(reviewer1);
        vm.expectRevert("All milestones released");
        grants.approveMilestone(grantId);
    }

    // Test approveMilestone reverts on a canceled grant
    function testApproveMilestoneRevertsCanceled() public {
        uint256 grantId = _createDirectGrant(_milestones());
        _submit(grantId);
        vm.prank(address(dao));
        grants.cancelGrant(grantId);
        vm.prank(reviewer1);
        vm.expectRevert("Grant is canceled");
        grants.approveMilestone(grantId);
    }

    // =====================================================
    // cancelGrant and views
    // =====================================================

    // Test canceling a grant refunds only the unreleased funds
    function testCancelGrantRefundsUnreleased() public {
        (, uint256 grantId) = _fundResearch();
        _submit(grantId);
        _approve(grantId, reviewer1); // M1 released

        vm.prank(address(dao));
        grants.cancelGrant(grantId);

        assertTrue(grants.getGrant(grantId).canceled);
        assertEq(usdc.balanceOf(address(treasury)), TREASURY_USDC - M1);
        assertEq(grants.lockedFunds(address(usdc)), 0);
    }

    // Test cancelGrant reverts in every invalid case
    function testCancelGrantReverts() public {
        vm.expectRevert("Only DAO");
        grants.cancelGrant(0);

        vm.startPrank(address(dao));
        vm.expectRevert("Grant does not exist");
        grants.cancelGrant(99);
        vm.stopPrank();

        uint256[] memory one = new uint256[](1);
        one[0] = M1;
        uint256 grantId = _createDirectGrant(one);
        uint256 second = _createDirectGrant(one);
        _submit(grantId);
        _approve(grantId, reviewer1); // grant completed

        vm.startPrank(address(dao));
        vm.expectRevert("Grant already completed");
        grants.cancelGrant(grantId);
        grants.cancelGrant(second);
        vm.expectRevert("Grant already canceled");
        grants.cancelGrant(second);
        vm.stopPrank();
    }

    // Test getGrant and getMilestone revert for missing data
    function testViewsRevertMissing() public {
        vm.expectRevert("Grant does not exist");
        grants.getGrant(99);
        vm.expectRevert("Milestone does not exist");
        grants.getMilestone(99, 0);
        assertFalse(grants.isGrantActive(99));
    }
}
