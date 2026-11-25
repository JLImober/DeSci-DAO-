// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "./DeSciBase.t.sol";

/**
 * @title LicenseRevenueTest
 * @author Jose Imoberdorf
 * @dev Tests for LicenseRevenue: license payments and revenue split.
 */
contract LicenseRevenueTest is DeSciBase {
    uint256 public constant LICENSE_FEE = 5000 * 10 ** 6; // 5K USDC

    uint256 internal tokenId;

    // Fund a research project (mints IP-NFT 0) and give the licensee USDC
    function setUp() public override {
        super.setUp();
        (uint256 proposalId,) = _fundResearch();
        tokenId = dao.ipTokenOfProposal(proposalId);
        usdc.mint(licensee, 100000 * 10 ** 6);
        vm.prank(licensee);
        usdc.approve(address(license), type(uint256).max);
    }

    // Test the constructor configuration
    function testConstructor() public view {
        assertEq(address(license.researchIPNFT()), address(ipnft));
        assertEq(license.treasury(), address(treasury));
        assertEq(license.researcherShareBps(), RESEARCHER_SHARE_BPS);
    }

    // Test the constructor reverts with invalid parameters
    function testConstructorReverts() public {
        vm.expectRevert("Invalid IP-NFT address");
        new LicenseRevenue(address(0), address(treasury), 0);
        vm.expectRevert("Invalid treasury address");
        new LicenseRevenue(address(ipnft), address(0), 0);
        vm.expectRevert("Invalid researcher share");
        new LicenseRevenue(address(ipnft), address(treasury), 5001);
    }

    // Test a license payment is split between the researcher and the treasury
    function testPayLicenseSplitsRevenue() public {
        uint256 treasuryBefore = usdc.balanceOf(address(treasury));
        vm.prank(licensee);
        license.payLicense(tokenId, address(usdc), LICENSE_FEE);

        assertEq(usdc.balanceOf(researcher), 1000 * 10 ** 6); // 20%
        assertEq(usdc.balanceOf(address(treasury)), treasuryBefore + 4000 * 10 ** 6); // 80%
        assertEq(license.totalRevenue(tokenId, address(usdc)), LICENSE_FEE);
    }

    // Test a zero researcher share sends everything to the treasury
    function testPayLicenseZeroResearcherShare() public {
        vm.prank(owner);
        license.setResearcherShare(0);
        uint256 treasuryBefore = usdc.balanceOf(address(treasury));
        vm.prank(licensee);
        license.payLicense(tokenId, address(usdc), LICENSE_FEE);

        assertEq(usdc.balanceOf(researcher), 0);
        assertEq(usdc.balanceOf(address(treasury)), treasuryBefore + LICENSE_FEE);
    }

    // Test payLicense reverts with invalid parameters
    function testPayLicenseReverts() public {
        vm.startPrank(licensee);
        vm.expectRevert("Invalid token address");
        license.payLicense(tokenId, address(0), LICENSE_FEE);
        vm.expectRevert("Amount must be greater than 0");
        license.payLicense(tokenId, address(usdc), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 99));
        license.payLicense(99, address(usdc), LICENSE_FEE);
        vm.stopPrank();
    }

    // Test payLicense reverts when the token transfer fails
    function testPayLicenseRevertsTransferFailed() public {
        FalseToken falseToken = new FalseToken();
        vm.prank(licensee);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseToken)));
        license.payLicense(tokenId, address(falseToken), LICENSE_FEE);
    }

    // Test the owner updating the researcher share within bounds
    function testSetResearcherShare() public {
        vm.prank(owner);
        license.setResearcherShare(5000);
        assertEq(license.researcherShareBps(), 5000);

        vm.prank(owner);
        vm.expectRevert("Invalid researcher share");
        license.setResearcherShare(5001);

        vm.prank(alice);
        vm.expectRevert(_notOwner(alice));
        license.setResearcherShare(1000);
    }
}
