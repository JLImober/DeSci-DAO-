// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "./DeSciBase.t.sol";

/**
 * @title DeSciTreasuryTest
 * @author Jose Imoberdorf
 * @dev Tests for DeSciTreasury: donations, DAO spending, IP-NFT custody and
 *      emergency withdrawals.
 */
contract DeSciTreasuryTest is DeSciBase {
    RejectETH internal rejecter;
    FalseToken internal falseToken;

    // Deploy the failure mocks
    function setUp() public override {
        super.setUp();
        rejecter = new RejectETH();
        falseToken = new FalseToken();
        vm.deal(alice, 10 ether);
    }

    // Approve a proposal in the treasury as the DAO
    function _approve(uint256 proposalId) internal {
        vm.prank(address(dao));
        treasury.approveProposal(proposalId);
    }

    // =====================================================
    // setDAO and approveProposal
    // =====================================================

    // Test setDAO updates the DAO and reverts for invalid callers or values
    function testSetDAO() public {
        vm.prank(owner);
        treasury.setDAO(alice);
        assertEq(treasury.dao(), alice);

        vm.prank(owner);
        vm.expectRevert("Invalid DAO address");
        treasury.setDAO(address(0));

        vm.prank(alice);
        vm.expectRevert(_notOwner(alice));
        treasury.setDAO(alice);
    }

    // Test approveProposal and its revert cases
    function testApproveProposal() public {
        _approve(1);
        assertTrue(treasury.isProposalApproved(1));

        vm.prank(address(dao));
        vm.expectRevert("Proposal already approved");
        treasury.approveProposal(1);

        vm.prank(owner);
        vm.expectRevert("Only DAO can approve proposals");
        treasury.approveProposal(2);
    }

    // =====================================================
    // spendFunds
    // =====================================================

    // Test the DAO spending tokens and ETH
    function testSpendFundsTokenAndETH() public {
        _approve(1);
        vm.prank(address(dao));
        treasury.spendFunds(1, researcher, M1, address(usdc));
        assertEq(usdc.balanceOf(researcher), M1);
        assertTrue(treasury.isProposalExecuted(1));

        vm.deal(address(treasury), 2 ether);
        _approve(2);
        vm.prank(address(dao));
        treasury.spendFunds(2, researcher, 1 ether, address(0));
        assertEq(researcher.balance, 1 ether);
    }

    // Test spendFunds reverts on access, approval and parameter checks
    function testSpendFundsRevertsChecks() public {
        vm.prank(owner);
        vm.expectRevert("Only DAO can spend funds");
        treasury.spendFunds(1, researcher, M1, address(usdc));

        vm.startPrank(address(dao));
        vm.expectRevert("Proposal not approved");
        treasury.spendFunds(1, researcher, M1, address(usdc));
        treasury.approveProposal(1);
        vm.expectRevert("Invalid recipient");
        treasury.spendFunds(1, address(0), M1, address(usdc));
        vm.expectRevert("Amount must be greater than 0");
        treasury.spendFunds(1, researcher, 0, address(usdc));
        treasury.spendFunds(1, researcher, M1, address(usdc));
        vm.expectRevert("Proposal already executed");
        treasury.spendFunds(1, researcher, M1, address(usdc));
        vm.stopPrank();
    }

    // Test spendFunds reverts on insufficient balances and failed transfers
    function testSpendFundsRevertsTransfers() public {
        _approve(1);
        vm.startPrank(address(dao));
        vm.expectRevert("Insufficient ETH balance");
        treasury.spendFunds(1, researcher, 1 ether, address(0));
        vm.expectRevert("Insufficient token balance");
        treasury.spendFunds(1, researcher, TREASURY_USDC + 1, address(usdc));
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseToken)));
        treasury.spendFunds(1, researcher, 1, address(falseToken));
        vm.stopPrank();

        vm.deal(address(treasury), 1 ether);
        vm.prank(address(dao));
        vm.expectRevert("ETH transfer failed");
        treasury.spendFunds(1, address(rejecter), 1 ether, address(0));
    }

    // =====================================================
    // Donations and IP-NFT custody
    // =====================================================

    // Test donations in ETH, through receive and in tokens
    function testDonations() public {
        vm.startPrank(alice);
        treasury.donate{value: 1 ether}();
        (bool ok,) = address(treasury).call{value: 2 ether}("");
        assertTrue(ok);
        vm.stopPrank();
        assertEq(treasury.getBalance(address(0)), 3 ether);

        usdc.mint(alice, M1);
        vm.startPrank(alice);
        usdc.approve(address(treasury), M1);
        treasury.donateToken(address(usdc), M1);
        vm.stopPrank();
        assertEq(treasury.getBalance(address(usdc)), TREASURY_USDC + M1);
    }

    // Test donations revert with invalid values
    function testDonationsRevert() public {
        vm.startPrank(alice);
        vm.expectRevert("Must send ETH");
        treasury.donate{value: 0}();
        vm.expectRevert("Invalid token address");
        treasury.donateToken(address(0), 1);
        vm.expectRevert("Amount must be greater than 0");
        treasury.donateToken(address(usdc), 0);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseToken)));
        treasury.donateToken(address(falseToken), 1);
        vm.stopPrank();
    }

    // Test the treasury accepts IP-NFTs through safe transfers
    function testReceivesIPNFT() public {
        bytes4 selector = treasury.onERC721Received(address(0), address(0), 0, "");
        assertEq(selector, IERC721Receiver.onERC721Received.selector);

        vm.prank(address(dao));
        uint256 tokenId = ipnft.mint(address(treasury), 0, researcher, PLAN_HASH);
        assertEq(ipnft.ownerOf(tokenId), address(treasury));
    }

    // =====================================================
    // emergencyWithdraw
    // =====================================================

    // Test the owner withdrawing tokens and ETH in an emergency
    function testEmergencyWithdraw() public {
        vm.deal(address(treasury), 1 ether);
        vm.startPrank(owner);
        treasury.emergencyWithdraw(address(usdc), M1, owner);
        treasury.emergencyWithdraw(address(0), 1 ether, owner);
        vm.stopPrank();
        assertEq(usdc.balanceOf(owner), M1);
        assertEq(owner.balance, 1 ether);
    }

    // Test emergencyWithdraw reverts for non-owners and invalid values
    function testEmergencyWithdrawReverts() public {
        vm.prank(alice);
        vm.expectRevert(_notOwner(alice));
        treasury.emergencyWithdraw(address(usdc), 1, alice);

        vm.startPrank(owner);
        vm.expectRevert("Invalid recipient");
        treasury.emergencyWithdraw(address(usdc), 1, address(0));
        vm.expectRevert("Amount must be greater than 0");
        treasury.emergencyWithdraw(address(usdc), 0, owner);
        vm.stopPrank();
    }
}
