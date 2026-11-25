// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "./DeSciBase.t.sol";

/**
 * @title DeSciIntegrationTest
 * @author Jose Imoberdorf
 * @dev End-to-end test of the DeSci lifecycle: donation, proposal, peer review,
 *      vote, funding, milestone payments, IP-NFT custody and license revenue.
 */
contract DeSciIntegrationTest is DeSciBase {
    // Test the full research lifecycle across all contracts
    function testFullResearchLifecycle() public {
        // 1. A donor adds 50K USDC to the treasury
        address donor = address(0xD);
        usdc.mint(donor, 50000 * 10 ** 6);
        vm.startPrank(donor);
        usdc.approve(address(treasury), 50000 * 10 ** 6);
        treasury.donateToken(address(usdc), 50000 * 10 ** 6);
        vm.stopPrank();
        assertEq(treasury.getBalance(address(usdc)), 150000 * 10 ** 6);

        // 2. alice proposes a 60K USDC research grant in 3 milestones
        uint256 proposalId = _proposeFunding();

        // 3. Two reviewers recommend it and the community votes
        _review(proposalId, reviewer1, true);
        _review(proposalId, reviewer2, true);
        vm.prank(alice);
        dao.vote(proposalId, true);
        _voteFor(proposalId);

        // 4. After the voting period, anyone executes it
        vm.warp(block.timestamp + VOTING_PERIOD);
        dao.executeProposal(proposalId);
        uint256 grantId = dao.grantOfProposal(proposalId);
        uint256 ipTokenId = dao.ipTokenOfProposal(proposalId);
        assertEq(usdc.balanceOf(address(grants)), GRANT_TOTAL);
        assertEq(ipnft.ownerOf(ipTokenId), address(treasury));

        // 5. The lab delivers each milestone and reviewers approve it
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(researcher);
            grants.submitMilestone(grantId, keccak256(abi.encode("deliverable", i)));
            vm.prank(i % 2 == 0 ? reviewer1 : reviewer2);
            grants.approveMilestone(grantId);
        }
        assertEq(usdc.balanceOf(researcher), GRANT_TOTAL);
        assertFalse(grants.isGrantActive(grantId));

        // 6. A company licenses the research result: 20% to the lab, 80% to the treasury
        uint256 fee = 10000 * 10 ** 6;
        usdc.mint(licensee, fee);
        vm.startPrank(licensee);
        usdc.approve(address(license), fee);
        license.payLicense(ipTokenId, address(usdc), fee);
        vm.stopPrank();

        assertEq(usdc.balanceOf(researcher), GRANT_TOTAL + 2000 * 10 ** 6);
        assertEq(treasury.getBalance(address(usdc)), 150000 * 10 ** 6 - GRANT_TOTAL + 8000 * 10 ** 6);

        // 7. Reviewers earned non-transferable reputation
        assertEq(registry.reviewCount(reviewer1), 3); // 1 proposal review + 2 milestones
        assertEq(registry.reviewCount(reviewer2), 2); // 1 proposal review + 1 milestone
    }
}
