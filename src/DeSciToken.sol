// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title DeSciToken
 * @author Jose Imoberdorf
 * @dev Governance token of the DeSci DAO, based on OpenZeppelin ERC20Votes
 *      (adapted from DAOGovernanceToken).
 *
 *  - Voting power checkpoints: every transfer, mint and burn records the voting
 *    power history, readable with getPastVotes(account, timepoint).
 *  - Timestamp clock: checkpoints use block.timestamp, the same time scale as the DAO.
 *  - Native delegation: delegate(address) moves voting power without moving tokens.
 *    Holders must delegate (to themselves or others) to activate their votes.
 */
contract DeSciToken is ERC20, ERC20Votes, Ownable {
    /**
     * @dev Constructor that gives msg.sender all of initial tokens
     * @param name Token name
     * @param symbol Token symbol
     * @param initialSupply Initial token supply
     */
    constructor(string memory name, string memory symbol, uint256 initialSupply)
        ERC20(name, symbol)
        EIP712(name, "1")
        Ownable(msg.sender)
    {
        _mint(msg.sender, initialSupply);
    }

    /**
     * @dev Use timestamps instead of block numbers for checkpoints
     * @return Current timepoint
     */
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /**
     * @dev Clock mode description (ERC-6372)
     * @return Clock mode
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    /**
     * @dev Get the current voting power of an address (delegated votes included)
     * @param account Address to check voting power for
     * @return Current voting power
     */
    function getVotingPower(address account) external view returns (uint256) {
        return getVotes(account);
    }

    /**
     * @dev Mint new tokens, e.g. to reward researchers and reviewers (only owner)
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Burn tokens from caller
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /**
     * @dev Record voting power checkpoints on every balance change
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }
}
