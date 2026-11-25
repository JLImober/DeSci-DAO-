// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../src/DeSciToken.sol";
import "../src/DeSciTreasury.sol";
import "../src/DeSciDAO.sol";
import "../src/MilestoneGrant.sol";
import "../src/ReviewerRegistry.sol";
import "../src/ResearchIPNFT.sol";
import "../src/LicenseRevenue.sol";
import "./mocks/Mocks.sol";

/**
 * @title DeSciBase
 * @author Jose Imoberdorf
 * @dev Shared setup for all DeSci tests: deploys and wires every contract on the
 *      local Foundry EVM (no real network) with a MockUSDC stablecoin.
 */
abstract contract DeSciBase is Test {
    // Contracts
    DeSciToken public token;
    DeSciTreasury public treasury;
    DeSciDAO public dao;
    MilestoneGrant public grants;
    ReviewerRegistry public registry;
    ResearchIPNFT public ipnft;
    LicenseRevenue public license;
    MockUSDC public usdc;

    // Test addresses
    address public owner = address(0x1);
    address public alice = address(0x2); // proposer, 50K DSG
    address public bob = address(0x3); // voter, 30K DSG
    address public researcher = address(0x4); // lab receiving the grant
    address public reviewer1 = address(0x5);
    address public reviewer2 = address(0x6);
    address public licensee = address(0x7); // company paying licenses

    // Governance parameters
    uint256 public constant INITIAL_SUPPLY = 1000000 * 10 ** 18; // 1M DSG
    uint256 public constant PROPOSAL_THRESHOLD = 1000 * 10 ** 18; // 1K DSG
    uint256 public constant VOTING_PERIOD = 10 days;
    uint256 public constant QUORUM_VOTES = 10000 * 10 ** 18; // 10K DSG
    uint256 public constant RESEARCHER_SHARE_BPS = 2000; // 20% of license revenue

    // Treasury funds and grant
    uint256 public constant TREASURY_USDC = 100000 * 10 ** 6; // 100K USDC
    uint256 public constant M1 = 10000 * 10 ** 6; // milestone 1: 10K USDC
    uint256 public constant M2 = 20000 * 10 ** 6; // milestone 2: 20K USDC
    uint256 public constant M3 = 30000 * 10 ** 6; // milestone 3: 30K USDC
    uint256 public constant GRANT_TOTAL = M1 + M2 + M3; // 60K USDC

    bytes32 public constant PLAN_HASH = keccak256("ipfs://research-plan");
    bytes32 public constant REPORT_HASH = keccak256("ipfs://review-report");
    bytes32 public constant DELIVERABLE_HASH = keccak256("ipfs://milestone-deliverable");

    // Deploy and wire all contracts, distribute tokens and activate votes
    function setUp() public virtual {
        usdc = new MockUSDC();

        vm.startPrank(owner);
        token = new DeSciToken("DeSci Governance Token", "DSG", INITIAL_SUPPLY);
        treasury = new DeSciTreasury(address(0));
        registry = new ReviewerRegistry();
        grants = new MilestoneGrant(address(treasury), address(registry));
        ipnft = new ResearchIPNFT("DeSci Research IP", "DSIP");
        dao = new DeSciDAO(
            address(token),
            address(treasury),
            address(grants),
            address(ipnft),
            address(registry),
            PROPOSAL_THRESHOLD,
            VOTING_PERIOD,
            QUORUM_VOTES
        );
        license = new LicenseRevenue(address(ipnft), address(treasury), RESEARCHER_SHARE_BPS);

        // Wire contracts to the DAO
        treasury.setDAO(address(dao));
        grants.setDAO(address(dao));
        ipnft.setMinter(address(dao));
        registry.setRecorder(address(dao), true);
        registry.setRecorder(address(grants), true);
        registry.addReviewer(reviewer1);
        registry.addReviewer(reviewer2);
        registry.transferOwnership(address(dao)); // reviewers are now managed by governance

        // Distribute governance tokens and activate the owner's votes
        assertTrue(token.transfer(alice, 50000 * 10 ** 18));
        assertTrue(token.transfer(bob, 30000 * 10 ** 18));
        token.delegate(owner);
        vm.stopPrank();

        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);

        // Fund the treasury with stablecoins
        usdc.mint(address(treasury), TREASURY_USDC);

        // Move time forward so the votes are before the first proposal snapshot
        vm.warp(block.timestamp + 1);
    }

    // ---------- helpers ----------

    // Standard milestone plan: 10K + 20K + 30K USDC
    function _milestones() internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](3);
        amounts[0] = M1;
        amounts[1] = M2;
        amounts[2] = M3;
    }

    // alice proposes funding the standard research project
    function _proposeFunding() internal returns (uint256 proposalId) {
        vm.prank(alice);
        proposalId = dao.proposeFunding("Validate compound X", researcher, address(usdc), _milestones(), PLAN_HASH);
    }

    // A reviewer reviews a funding proposal
    function _review(uint256 proposalId, address reviewer, bool recommend) internal {
        vm.prank(reviewer);
        dao.reviewProposal(proposalId, REPORT_HASH, recommend);
    }

    // bob votes in favor (30K >= quorum)
    function _voteFor(uint256 proposalId) internal {
        vm.prank(bob);
        dao.vote(proposalId, true);
    }

    // Propose, review, vote, wait and execute the standard funding proposal
    function _fundResearch() internal returns (uint256 proposalId, uint256 grantId) {
        proposalId = _proposeFunding();
        _review(proposalId, reviewer1, true);
        _voteFor(proposalId);
        vm.warp(block.timestamp + VOTING_PERIOD);
        dao.executeProposal(proposalId);
        grantId = dao.grantOfProposal(proposalId);
    }

    // Build the Ownable revert data for an unauthorized account
    function _notOwner(address account) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, account);
    }
}
