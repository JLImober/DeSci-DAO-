// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title ResearchIPNFT
 * @author Jose Imoberdorf
 * @dev IP-NFT of the DeSci DAO: one ERC721 token per funded research project.
 *
 *  - Minted by the DAO when a funding proposal is executed, and held by the treasury.
 *  - Points to the legal agreement that grants the IP rights (agreementHash, e.g. an
 *    IPFS hash). The token alone does not grant rights: the off-chain agreement does.
 *  - Stores the researcher, used by LicenseRevenue to share license income.
 */
contract ResearchIPNFT is ERC721, Ownable {
    // Research IP data of each token
    struct ResearchIP {
        uint256 proposalId; // DAO proposal that funded the research
        address researcher; // Researcher or lab that receives the grant
        bytes32 agreementHash; // Hash of the off-chain legal agreement / research plan
        uint256 createdAt; // Mint timestamp
    }

    // Contract allowed to mint (the DAO)
    address public minter;

    // Number of tokens minted (also the next token ID)
    uint256 public totalMinted;

    // Base URI for token metadata
    string private baseTokenURI;

    // Research IP data by token ID
    mapping(uint256 => ResearchIP) private researchIPs;

    // Events
    event MinterUpdated(address indexed minter);
    event BaseURIUpdated(string baseURI);
    event ResearchIPMinted(
        uint256 indexed tokenId, uint256 indexed proposalId, address indexed researcher, bytes32 agreementHash
    );

    /**
     * @dev Constructor
     * @param name Collection name
     * @param symbol Collection symbol
     */
    constructor(string memory name, string memory symbol) ERC721(name, symbol) Ownable(msg.sender) {}

    /**
     * @dev Set the contract allowed to mint (only owner)
     * @param _minter Minter address (the DAO)
     */
    function setMinter(address _minter) external onlyOwner {
        require(_minter != address(0), "Invalid minter address");
        minter = _minter;
        emit MinterUpdated(_minter);
    }

    /**
     * @dev Set the base URI for token metadata (only owner)
     * @param baseURI New base URI
     */
    function setBaseURI(string calldata baseURI) external onlyOwner {
        baseTokenURI = baseURI;
        emit BaseURIUpdated(baseURI);
    }

    /**
     * @dev Mint a Research IP-NFT (only minter)
     * @param to Token owner (the treasury)
     * @param proposalId DAO proposal that funded the research
     * @param researcher Researcher or lab
     * @param agreementHash Hash of the legal agreement / research plan
     * @return tokenId ID of the new token
     */
    function mint(address to, uint256 proposalId, address researcher, bytes32 agreementHash)
        external
        returns (uint256 tokenId)
    {
        require(msg.sender == minter, "Only minter");
        require(researcher != address(0), "Invalid researcher address");
        require(agreementHash != bytes32(0), "Invalid agreement hash");

        tokenId = totalMinted++;
        researchIPs[tokenId] = ResearchIP(proposalId, researcher, agreementHash, block.timestamp);
        _safeMint(to, tokenId);

        emit ResearchIPMinted(tokenId, proposalId, researcher, agreementHash);
    }

    /**
     * @dev Get the research IP data of a token
     * @param tokenId Token ID
     * @return Research IP data
     */
    function getResearchIP(uint256 tokenId) external view returns (ResearchIP memory) {
        _requireOwned(tokenId);
        return researchIPs[tokenId];
    }

    /**
     * @dev Get the researcher of a token
     * @param tokenId Token ID
     * @return Researcher address
     */
    function researcherOf(uint256 tokenId) external view returns (address) {
        _requireOwned(tokenId);
        return researchIPs[tokenId].researcher;
    }

    /// @dev Base URI used by tokenURI
    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }
}
