// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockUSDC
 * @author Jose Imoberdorf
 * @dev Test stablecoin with 6 decimals, like USDC. Anyone can mint.
 *      Used to fund the treasury and pay grants and licenses without a real network.
 */
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {}

    // USDC uses 6 decimals
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    // Mint test tokens to any address
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title RejectETH
 * @author Jose Imoberdorf
 * @dev Contract without receive/fallback: rejects any ETH transfer.
 */
contract RejectETH {}

/**
 * @title FalseToken
 * @author Jose Imoberdorf
 * @dev Token that reports a balance but whose transfers return false.
 *      Used to test that SafeERC20 reverts on failed transfers.
 */
contract FalseToken {
    // Always reports the maximum balance
    function balanceOf(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    // Always fails by returning false
    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    // Always fails by returning false
    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}
