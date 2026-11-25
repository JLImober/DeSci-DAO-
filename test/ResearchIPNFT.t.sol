// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "./DeSciBase.t.sol";

/**
 * @title ResearchIPNFTTest
 * @author Jose Imoberdorf
 * @dev Tests for ResearchIPNFT: minting, research IP data and metadata.
 */
contract ResearchIPNFTTest is DeSciBase {
    // Test the DAO minting an IP-NFT stores the research IP data
    function testMint() public {
        vm.prank(address(dao));
        uint256 tokenId = ipnft.mint(address(treasury), 3, researcher, PLAN_HASH);

        ResearchIPNFT.ResearchIP memory ip = ipnft.getResearchIP(tokenId);
        assertEq(tokenId, 0);
        assertEq(ipnft.totalMinted(), 1);
        assertEq(ipnft.ownerOf(tokenId), address(treasury));
        assertEq(ip.proposalId, 3);
        assertEq(ip.researcher, researcher);
        assertEq(ip.agreementHash, PLAN_HASH);
        assertEq(ip.createdAt, block.timestamp);
        assertEq(ipnft.researcherOf(tokenId), researcher);
    }

    // Test mint reverts for non-minters and invalid data
    function testMintReverts() public {
        vm.prank(alice);
        vm.expectRevert("Only minter");
        ipnft.mint(alice, 0, researcher, PLAN_HASH);

        vm.startPrank(address(dao));
        vm.expectRevert("Invalid researcher address");
        ipnft.mint(address(treasury), 0, address(0), PLAN_HASH);
        vm.expectRevert("Invalid agreement hash");
        ipnft.mint(address(treasury), 0, researcher, bytes32(0));
        vm.stopPrank();
    }

    // Test views revert for nonexistent tokens
    function testViewsRevertNonexistentToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 99));
        ipnft.getResearchIP(99);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 99));
        ipnft.researcherOf(99);
    }

    // Test the owner setting the minter and the base URI
    function testOwnerSettings() public {
        vm.startPrank(owner);
        ipnft.setMinter(alice);
        ipnft.setBaseURI("ipfs://desci/");
        vm.expectRevert("Invalid minter address");
        ipnft.setMinter(address(0));
        vm.stopPrank();
        assertEq(ipnft.minter(), alice);

        vm.prank(alice);
        uint256 tokenId = ipnft.mint(address(treasury), 0, researcher, PLAN_HASH);
        assertEq(ipnft.tokenURI(tokenId), "ipfs://desci/0");
    }

    // Test owner settings revert for non-owners
    function testOwnerSettingsRevertNotOwner() public {
        vm.startPrank(alice);
        vm.expectRevert(_notOwner(alice));
        ipnft.setMinter(alice);
        vm.expectRevert(_notOwner(alice));
        ipnft.setBaseURI("x");
        vm.stopPrank();
    }
}
