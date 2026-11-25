// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "./DeSciBase.t.sol";

/**
 * @title ReviewerRegistryTest
 * @author Jose Imoberdorf
 * @dev Tests for ReviewerRegistry: reviewers, recorders and reputation.
 */
contract ReviewerRegistryTest is DeSciBase {
    // Test the setup registers reviewers and recorders and gives ownership to the DAO
    function testSetup() public view {
        assertTrue(registry.isReviewer(reviewer1));
        assertTrue(registry.isReviewer(reviewer2));
        assertEq(registry.reviewerCount(), 2);
        assertTrue(registry.isRecorder(address(dao)));
        assertTrue(registry.isRecorder(address(grants)));
        assertEq(registry.owner(), address(dao));
    }

    // Test the owner adding and removing a reviewer keeps their reputation
    function testAddAndRemoveReviewer() public {
        address newReviewer = address(0x8);
        vm.startPrank(address(dao));
        registry.addReviewer(newReviewer);
        assertEq(registry.reviewerCount(), 3);
        registry.recordReview(newReviewer);
        registry.removeReviewer(newReviewer);
        vm.stopPrank();

        assertFalse(registry.isReviewer(newReviewer));
        assertEq(registry.reviewerCount(), 2);
        assertEq(registry.reviewCount(newReviewer), 1);
    }

    // Test addReviewer and removeReviewer revert in every invalid case
    function testReviewerManagementReverts() public {
        vm.prank(owner); // ownership was transferred to the DAO
        vm.expectRevert(_notOwner(owner));
        registry.addReviewer(address(0x8));

        vm.startPrank(address(dao));
        vm.expectRevert("Invalid reviewer address");
        registry.addReviewer(address(0));
        vm.expectRevert("Already a reviewer");
        registry.addReviewer(reviewer1);
        vm.expectRevert("Not a reviewer");
        registry.removeReviewer(address(0x8));
        vm.stopPrank();
    }

    // Test the owner updating recorders
    function testSetRecorder() public {
        vm.startPrank(address(dao));
        registry.setRecorder(address(0x9), true);
        assertTrue(registry.isRecorder(address(0x9)));
        registry.setRecorder(address(0x9), false);
        assertFalse(registry.isRecorder(address(0x9)));
        vm.expectRevert("Invalid recorder address");
        registry.setRecorder(address(0), true);
        vm.stopPrank();
    }

    // Test recordReview reverts for non-recorders and non-reviewers
    function testRecordReviewReverts() public {
        vm.prank(alice);
        vm.expectRevert("Not authorized to record");
        registry.recordReview(reviewer1);

        vm.prank(address(dao));
        vm.expectRevert("Not a reviewer");
        registry.recordReview(alice);
    }
}
