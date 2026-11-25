// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IDeSci.sol";

/**
 * @title LicenseRevenue
 * @author Jose Imoberdorf
 * @dev Collects license payments for Research IP-NFTs and splits them.
 *
 *  - A licensee (company, startup) pays for the use of a research result.
 *  - A share goes to the researcher of the IP-NFT (researcherShareBps) and the rest
 *    to the treasury, which funds new research.
 */
contract LicenseRevenue is Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10000;
    uint256 public constant MAX_RESEARCHER_SHARE_BPS = 5000; // 50%

    // Connected contracts
    IResearchIPNFT public immutable researchIPNFT;
    address public immutable treasury;

    // Researcher share of each payment, in basis points
    uint256 public researcherShareBps;

    // Total license revenue by IP-NFT and token
    mapping(uint256 => mapping(address => uint256)) public totalRevenue;

    // Events
    event LicensePaid(
        uint256 indexed tokenId,
        address indexed licensee,
        address indexed token,
        uint256 amount,
        uint256 researcherAmount,
        uint256 treasuryAmount
    );
    event ResearcherShareUpdated(uint256 researcherShareBps);

    /**
     * @dev Constructor
     * @param _researchIPNFT Research IP-NFT contract
     * @param _treasury Treasury that receives the DAO share
     * @param _researcherShareBps Researcher share in basis points (max 5000)
     */
    constructor(address _researchIPNFT, address _treasury, uint256 _researcherShareBps) Ownable(msg.sender) {
        require(_researchIPNFT != address(0), "Invalid IP-NFT address");
        require(_treasury != address(0), "Invalid treasury address");
        require(_researcherShareBps <= MAX_RESEARCHER_SHARE_BPS, "Invalid researcher share");
        researchIPNFT = IResearchIPNFT(_researchIPNFT);
        treasury = _treasury;
        researcherShareBps = _researcherShareBps;
    }

    /**
     * @dev Pay a license for an IP-NFT (requires a prior approve of `amount`)
     * @param tokenId Research IP-NFT ID
     * @param token Payment token
     * @param amount Amount to pay
     */
    function payLicense(uint256 tokenId, address token, uint256 amount) external {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than 0");
        address researcher = researchIPNFT.researcherOf(tokenId); // reverts if the token does not exist

        uint256 researcherAmount = (amount * researcherShareBps) / BPS;
        uint256 treasuryAmount = amount - researcherAmount;
        totalRevenue[tokenId][token] += amount;

        if (researcherAmount > 0) {
            IERC20(token).safeTransferFrom(msg.sender, researcher, researcherAmount);
        }
        IERC20(token).safeTransferFrom(msg.sender, treasury, treasuryAmount);

        emit LicensePaid(tokenId, msg.sender, token, amount, researcherAmount, treasuryAmount);
    }

    /**
     * @dev Update the researcher share (only owner)
     * @param _researcherShareBps New share in basis points (max 5000)
     */
    function setResearcherShare(uint256 _researcherShareBps) external onlyOwner {
        require(_researcherShareBps <= MAX_RESEARCHER_SHARE_BPS, "Invalid researcher share");
        researcherShareBps = _researcherShareBps;
        emit ResearcherShareUpdated(_researcherShareBps);
    }
}
