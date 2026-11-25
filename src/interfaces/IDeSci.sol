// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/**
 * @title IDeSciTreasury
 * @author Jose Imoberdorf
 * @dev Treasury functions used by DeSciDAO.
 */
interface IDeSciTreasury {
    function approveProposal(uint256 proposalId) external;
    function spendFunds(uint256 proposalId, address recipient, uint256 amount, address token) external;
    function getBalance(address token) external view returns (uint256 balance);
}

/**
 * @title IMilestoneGrant
 * @author Jose Imoberdorf
 * @dev Grant manager functions used by DeSciDAO.
 */
interface IMilestoneGrant {
    function createGrant(
        uint256 proposalId,
        address researcher,
        address token,
        uint256[] calldata milestoneAmounts,
        bytes32 researchPlanHash
    ) external returns (uint256 grantId);
    function cancelGrant(uint256 grantId) external;
    function isGrantActive(uint256 grantId) external view returns (bool);
}

/**
 * @title IResearchIPNFT
 * @author Jose Imoberdorf
 * @dev IP-NFT functions used by DeSciDAO and LicenseRevenue.
 */
interface IResearchIPNFT {
    function mint(address to, uint256 proposalId, address researcher, bytes32 agreementHash)
        external
        returns (uint256 tokenId);
    function researcherOf(uint256 tokenId) external view returns (address);
}

/**
 * @title IReviewerRegistry
 * @author Jose Imoberdorf
 * @dev Reviewer registry functions used by DeSciDAO and MilestoneGrant.
 */
interface IReviewerRegistry {
    function isReviewer(address account) external view returns (bool);
    function addReviewer(address reviewer) external;
    function removeReviewer(address reviewer) external;
    function recordReview(address reviewer) external;
}
