// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "./DeSciBase.t.sol";

/**
 * @title DeSciTokenTest
 * @author Jose Imoberdorf
 * @dev Tests for DeSciToken: delegation, voting power history, clock, mint and burn.
 */
contract DeSciTokenTest is DeSciBase {
    // Test the token metadata and initial distribution
    function testMetadataAndDistribution() public view {
        assertEq(token.name(), "DeSci Governance Token");
        assertEq(token.symbol(), "DSG");
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(alice), 50000 * 10 ** 18);
    }

    // Test delegating voting power without moving tokens
    function testDelegate() public {
        vm.prank(alice);
        token.delegate(bob);
        assertEq(token.delegates(alice), bob);
        assertEq(token.getVotes(alice), 0);
        assertEq(token.getVotes(bob), 80000 * 10 ** 18);
        assertEq(token.balanceOf(alice), 50000 * 10 ** 18);
    }

    // Test tokens give no voting power until delegated
    function testVotesInactiveWithoutDelegation() public {
        vm.prank(alice);
        assertTrue(token.transfer(researcher, 1000 * 10 ** 18));
        assertEq(token.getVotes(researcher), 0);
        assertEq(token.getVotingPower(alice), 49000 * 10 ** 18);
    }

    // Test getPastVotes keeps the history and rejects future lookups
    function testGetPastVotes() public {
        uint256 before = block.timestamp;
        vm.warp(before + 1);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10000 * 10 ** 18));
        vm.warp(before + 2);

        assertEq(token.getPastVotes(alice, before), 50000 * 10 ** 18);
        assertEq(token.getPastVotes(alice, before + 1), 40000 * 10 ** 18);

        uint48 now_ = uint48(block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(Votes.ERC5805FutureLookup.selector, uint256(now_), now_));
        token.getPastVotes(alice, now_);
    }

    // Test the token clock uses timestamps
    function testClock() public view {
        assertEq(token.clock(), uint48(block.timestamp));
        assertEq(token.CLOCK_MODE(), "mode=timestamp");
    }

    // Test minting and burning update balances and votes
    function testMintAndBurn() public {
        vm.prank(owner);
        token.mint(alice, 1000 * 10 ** 18);
        assertEq(token.getVotes(alice), 51000 * 10 ** 18);

        vm.prank(alice);
        token.burn(2000 * 10 ** 18);
        assertEq(token.getVotes(alice), 49000 * 10 ** 18);
    }

    // Test minting reverts for non-owners
    function testMintRevertsNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(_notOwner(alice));
        token.mint(alice, 1);
    }
}
