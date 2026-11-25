// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title DeSciTreasury
 * @author Jose Imoberdorf
 * @dev Treasury of the DeSci DAO (adapted from DAOTreasury).
 *
 *  - Holds donations in ETH and ERC20 tokens (stablecoins such as USDC).
 *  - Only the DAO can approve and spend funds, which go to the MilestoneGrant escrow.
 *  - Holds the Research IP-NFTs of funded projects (ERC721 receiver).
 *  - Uses SafeERC20, so tokens that do not return a bool (e.g. USDT) are supported.
 */
contract DeSciTreasury is Ownable, IERC721Receiver {
    using SafeERC20 for IERC20;

    // DAO contract allowed to approve and spend funds
    address public dao;

    // Mapping to track approved spending proposals
    mapping(uint256 => bool) public approvedProposals;

    // Mapping to track executed spending proposals
    mapping(uint256 => bool) public executedProposals;

    // Events
    event ProposalApproved(uint256 indexed proposalId);
    event FundsSpent(uint256 indexed proposalId, address indexed recipient, uint256 amount, address token);
    event DonationReceived(address indexed donor, address indexed token, uint256 amount);
    event DAOSet(address indexed dao);
    event EmergencyWithdrawal(address indexed token, uint256 amount, address indexed recipient);

    /**
     * @dev Constructor
     * @param _dao Address of the DAO contract (can be address(0) and set later)
     */
    constructor(address _dao) Ownable(msg.sender) {
        dao = _dao;
    }

    /**
     * @dev Set the DAO contract address (only owner)
     * @param _dao New DAO contract address
     */
    function setDAO(address _dao) external onlyOwner {
        require(_dao != address(0), "Invalid DAO address");
        dao = _dao;
        emit DAOSet(_dao);
    }

    /**
     * @dev Approve a proposal for spending (only DAO)
     * @param proposalId ID of the proposal to approve
     */
    function approveProposal(uint256 proposalId) external {
        require(msg.sender == dao, "Only DAO can approve proposals");
        require(!approvedProposals[proposalId], "Proposal already approved");

        approvedProposals[proposalId] = true;
        emit ProposalApproved(proposalId);
    }

    /**
     * @dev Spend funds based on an approved proposal (only DAO)
     * @param proposalId ID of the approved proposal
     * @param recipient Address to send funds to
     * @param amount Amount to send
     * @param token Token address (address(0) for ETH)
     */
    function spendFunds(uint256 proposalId, address recipient, uint256 amount, address token) external {
        require(msg.sender == dao, "Only DAO can spend funds");
        require(approvedProposals[proposalId], "Proposal not approved");
        require(!executedProposals[proposalId], "Proposal already executed");
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be greater than 0");

        executedProposals[proposalId] = true;
        _transferOut(token, amount, recipient);

        emit FundsSpent(proposalId, recipient, amount, token);
    }

    /**
     * @dev Donate ETH to the treasury
     */
    function donate() external payable {
        require(msg.value > 0, "Must send ETH");
        emit DonationReceived(msg.sender, address(0), msg.value);
    }

    /**
     * @dev Donate ERC20 tokens to the treasury (requires a prior approve)
     * @param token Token address
     * @param amount Amount to donate
     */
    function donateToken(address token, uint256 amount) external {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than 0");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit DonationReceived(msg.sender, token, amount);
    }

    /**
     * @dev Get treasury balance for a specific token
     * @param token Token address (address(0) for ETH)
     * @return balance Current balance
     */
    function getBalance(address token) external view returns (uint256 balance) {
        if (token == address(0)) {
            return address(this).balance;
        }
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @dev Check if a proposal is approved
     * @param proposalId ID of the proposal
     * @return approved Whether the proposal is approved
     */
    function isProposalApproved(uint256 proposalId) external view returns (bool approved) {
        return approvedProposals[proposalId];
    }

    /**
     * @dev Check if a proposal has been executed
     * @param proposalId ID of the proposal
     * @return executed Whether the proposal has been executed
     */
    function isProposalExecuted(uint256 proposalId) external view returns (bool executed) {
        return executedProposals[proposalId];
    }

    /**
     * @dev Emergency withdrawal (only owner)
     * @param token Token address (address(0) for ETH)
     * @param amount Amount to withdraw
     * @param recipient Address to send funds to
     */
    function emergencyWithdraw(address token, uint256 amount, address recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be greater than 0");

        _transferOut(token, amount, recipient);
        emit EmergencyWithdrawal(token, amount, recipient);
    }

    /**
     * @dev Accept Research IP-NFTs and any other ERC721
     * @return Selector confirming the transfer
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    // Allow the contract to receive ETH donations
    receive() external payable {
        emit DonationReceived(msg.sender, address(0), msg.value);
    }

    /// @dev Send ETH or ERC20 tokens from the treasury
    function _transferOut(address token, uint256 amount, address recipient) internal {
        if (token == address(0)) {
            require(address(this).balance >= amount, "Insufficient ETH balance");
            (bool success,) = recipient.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            require(IERC20(token).balanceOf(address(this)) >= amount, "Insufficient token balance");
            IERC20(token).safeTransfer(recipient, amount);
        }
    }
}
