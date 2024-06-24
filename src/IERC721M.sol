// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {IERC721} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";
import {IERC721x} from "../lib/ERC721x/src/interfaces/IERC721x.sol";
import {IERC2981} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC2981.sol";

/**
 * @title IERC721M
 * @author Zodomo.eth (X: @0xZodomo, Telegram: @zodomo, Email: zodomo@proton.me)
 */
interface IERC721M is IERC721, IERC721x, IERC2981 {
    error Invalid();
    error MintCap();
    error URILocked();
    error NotAligned();
    error MintClosed();
    error Blacklisted();
    error TransferFailed();
    error NothingToClaim();
    error ExcessiveClaim();
    error RoyaltiesDisabled();
    error InsufficientPayment();

    // >>>>>>>>>>>> [ EVENTS ] <<<<<<<<<<<<

    event URILock();
    event MintOpen();
    event RoyaltyDisabled();
    event Withdraw(address indexed to, uint256 indexed amount);
    event PriceUpdate(uint80 indexed price);
    event SupplyUpdate(uint40 indexed supply);
    event AlignmentUpdate(uint16 indexed minAllocation, uint16 indexed maxAllocation);
    event BlacklistUpdate(address[] indexed blacklistedAssets, bool indexed status);
    event ReferralFeePaid(address indexed referral, uint256 indexed amount);
    event ReferralFeeUpdate(uint16 indexed referralFee);
    event BatchMetadataUpdate(uint256 indexed fromTokenId, uint256 indexed toTokenId);
    event ContractMetadataUpdate(string indexed uri);
    event RoyaltyUpdate(uint256 indexed tokenId, address indexed receiver, uint96 indexed royaltyFee);
    event CustomMinted(address indexed minter, uint8 indexed listId, uint40 indexed amount);
    event CustomMintDeleted(uint8 indexed listId);
    event CustomMintDisabled(uint8 indexed listId);
    event CustomMintRepriced(uint8 indexed listId, uint80 indexed price);
    event CustomMintReenabled(uint8 indexed listId, uint40 indexed claimable);
    event CustomMintConfigured(bytes32 indexed root, uint8 indexed listId, uint40 indexed amount);

    struct CustomMint {
        bytes32 root;
        uint40 issued;
        uint40 claimable;
        uint40 supply;
        uint80 price;
    }

    function name() external view returns (string memory); //
    function symbol() external view returns (string memory);
    //
    function baseURI() external view returns (string memory); //
    function contractURI() external view returns (string memory);
    //
    function tokenURI(uint256 tokenId) external view returns (string memory); //
    function maxSupply() external view returns (uint40);
    //
    function totalSupply() external view returns (uint256); //
    function price() external view returns (uint256);
    //
    function vaultFactory() external view returns (address); //
    function uriLocked() external view returns (bool);
    //
    function mintOpen() external view returns (bool); //
    function alignmentVault() external view returns (address);
    //
    function minAllocation() external view returns (uint16); //
    function maxAllocation() external view returns (uint16);
    //
    function referralFee() external view returns (uint16); //
    function getBlacklist() external view returns (address[] memory);
    //
    function getCustomMintListIds() external view returns (uint256[] memory); //
    function customMintData(uint8 listId) external view returns (CustomMint memory);
    //
    function customClaims(address user, uint8 listId) external view returns (uint256 claimed); //
    function setReferralFee(uint16 newReferralFee) external;
    function setBaseURI(string memory newBaseURI) external;
    function setPrice(uint256 newPrice) external;
    function setRoyalties(address recipient, uint96 royaltyFee) external;
    function setRoyaltiesForId(uint256 tokenId, address recipient, uint96 royaltyFee) external;
    function setBlacklist(address[] memory _blacklist) external;

    function setCustomMint(bytes32 root, uint8 listId, uint40 amount, uint40 claimable, uint80 newPrice) external;
    function disableCustomMint(uint8 listId) external;
    function reenableCustomMint(uint8 listId, uint40 claimable) external;
    function repriceCustomMint(uint8 listId, uint80 newPrice) external;
    function nukeCustomMint(uint8 listId) external;

    function disableRoyalties() external;
    function lockURI() external;
    function openMint() external;
    function increaseAlignment(uint16 newMinAllocation, uint16 newMaxAllocation) external;
    function decreaseSupply(uint40 newMaxSupply) external;
    function updateApprovedContracts(address[] calldata contracts, bool[] calldata values) external;

    function mint() external payable;
    function mint(uint256 amount) external payable;
    function mint(address recipient, uint256 amount) external payable;
    function mint(address recipient, uint256 amount, address referral) external payable;
    function mint(address recipient, uint256 amount, uint16 allocation) external payable;
    function mint(address recipient, uint256 amount, address referral, uint16 allocation) external payable;
    function customMint(
        bytes32[] calldata proof,
        uint8 listId,
        address recipient,
        uint40 amount,
        address referral
    ) external payable;

    function rescueERC20(address addr, address recipient) external;
    function rescueERC721(address addr, address recipient, uint256 tokenId) external;
    function withdrawFunds(address to, uint256 amount) external;
}
