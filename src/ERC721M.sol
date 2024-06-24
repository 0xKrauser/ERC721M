// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

// >>>>>>>>>>>> [ IMPORTS ] <<<<<<<<<<<<

import { ERC721Core } from "./core/ERC721Core.sol";

import { NotZero, TransferFailed } from "./core/ICore.sol";
import { IERC721M } from "./core/IERC721M.sol";

import { FixedPointMathLib as FPML } from "../lib/solady/src/utils/FixedPointMathLib.sol";

import { IERC20 } from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

// import {console2} from "../lib/forge-std/src/Console2.sol";

// >>>>>>>>>>>> [ INTERFACES ] <<<<<<<<<<<<

interface IAlignmentVaultMinimal {
    function vault() external view returns (address);
    function alignedNft() external view returns (address);
}

interface IFactory {
    function deploy(address vaultOwner, address alignedNft, uint96 vaultId) external returns (address);
    function deployDeterministic(
        address vaultOwner,
        address alignedNft,
        uint96 vaultId,
        bytes32 salt
    ) external returns (address);
}

/**
 * @title ERC721M
 * @author Zodomo.eth (Farcaster/Telegram/Discord/Github: @zodomo, X: @0xZodomo, Email: zodomo@proton.me)
 * @notice A NFT template that can be configured to automatically send a portion of mint funds to an AlignmentVault
 * @custom:github https://github.com/Zodomo/ERC721M
 */
contract ERC721M is ERC721Core, IERC721M {
    // >>>>>>>>>>>> [ STORAGE ] <<<<<<<<<<<<

    // Address of AlignmentVaultFactory, used when deploying AlignmentVault
    address public constant VAULT_FACTORY = 0x7c1A6B4B373E70730c52dfCB2e0A67E7591d4AAa;

    uint16 private constant MIN_ALLOCATION = 500;

    uint16 public minAllocation;
    uint16 public maxAllocation;

    address public alignmentVault;

    // >>>>>>>>>>>> [ CONSTRUCTION / INITIALIZATION ] <<<<<<<<<<<<

    // Constructor is kept empty in order to make the template compatible with ERC-1167 proxy factories
    constructor() payable {}

    // Initialize contract, should be called immediately after deployment, ideally by factory
    function initialize(
        string memory name_, // Collection name ("Milady")
        string memory symbol_, // Collection symbol ("MIL")
        uint32 _maxSupply, // Max supply (~1.099T max)
        uint16 _royalty, // Percentage in basis points (420 == 4.20%)
        uint16 _allocation, // Minimum Percentage of mint funds sent to AlignmentVault in bps, min. of 5% (777 == 7.77%)
        address _owner, // Collection contract owner
        address _alignedNft, // Address of NFT to configure AlignmentVault for, must have NFTX vault!
        uint256 _price, // Price (~1.2M ETH max)
        uint96 _vaultId, // NFTX Vault ID, please check!
        bytes32 _salt // AV Deployment salt
    ) external payable virtual initializer {
        // Confirm mint alignment allocation is within valid range
        //@TODO opinionated magic number, maybe move this to the factory
        if (_allocation < MIN_ALLOCATION || _allocation > _DENOMINATOR_BPS) revert AllocationOutOfBounds();
        minAllocation = _allocation;
        maxAllocation = _allocation;

        // Initialize ERC721Core
        _initialize(name_, symbol_, _maxSupply, _royalty, _owner, _price);

        // Deploy AlignmentVault
        address deployedAV;
        if (_salt == bytes32("")) deployedAV = IFactory(VAULT_FACTORY).deploy(_owner, _alignedNft, _vaultId);
        else deployedAV = IFactory(VAULT_FACTORY).deployDeterministic(_owner, _alignedNft, _vaultId, _salt);
        alignmentVault = deployedAV;
        // Send initialize payment (if any) to vault
        if (msg.value > 0) {
            (bool success, ) = payable(deployedAV).call{ value: msg.value }("");
            if (!success) revert TransferFailed();
        }
        emit AlignmentUpdate(_allocation, _allocation);
    }

    // >>>>>>>>>>>> [ INTERNAL FUNCTIONS ] <<<<<<<<<<<<

    // >>>>>>>>>>>> [ MINT LOGIC ] <<<<<<<<<<<<

    function _handleAllocation(uint256 allocation_) internal virtual {
        if (allocation_ < minAllocation || allocation_ > maxAllocation) revert AllocationOutOfBounds();

        uint256 mintAlloc = FPML.fullMulDivUp(allocation_, msg.value, _DENOMINATOR_BPS);

        if (msg.value > 0) {
            payable(alignmentVault).call{ value: mintAlloc }("");
        }
    }

    function _handleMint(address recipient_, uint256 amount_, address referral_) internal virtual override {
        _handleAllocation(minAllocation);
        ERC721Core._handleMint(recipient_, amount_, referral_);
    }

    function _handleMintWithList(
        bytes32[] calldata proof_,
        uint8 listId_,
        address recipient_,
        uint32 amount_,
        address referral_
    ) internal virtual override {
        _handleAllocation(minAllocation);
        ERC721Core._handleMintWithList(proof_, listId_, recipient_, amount_, referral_);
    }

    // Standard mint function that supports batch minting and custom allocation
    function mint(address recipient_, uint256 amount_, uint16 allocation_) public payable virtual {
        _handleAllocation(allocation_);
        ERC721Core._handleMint(recipient_, amount_, address(0));
    }

    // Standard batch mint with custom allocation support and referral fee support
    function mint(
        address recipient_,
        uint256 amount_,
        address referral_,
        uint16 allocation_
    ) public payable virtual nonReentrant {
        _handleAllocation(allocation_);
        ERC721Core._handleMint(recipient_, amount_, referral_);
    }

    // Standard batch mint with custom allocation support, list support and referral fee support
    // Remove for contract size?
    /*     
    function mint(
        bytes32[] calldata proof_,
        uint8 listId_,
        address recipient_,
        uint64 amount_,
        uint16 allocation_,
        address referral_
    ) public payable virtual nonReentrant {
        _handleAllocation(allocation_);
        ERC721Core._handleMintWithList(proof_, listId_, recipient_, amount_, referral_);
    } 
    */

    // >>>>>>>>>>>> [ PERMISSIONED / OWNER FUNCTIONS ] <<<<<<<<<<<<

    /**
     * @inheritdoc ERC721Core
     * @notice Override to account for allocation when setting a percentage going to the referral
     */
    function setReferralFee(uint16 bps_) external virtual override onlyOwner {
        if (bps_ > (_DENOMINATOR_BPS - maxAllocation)) revert MaxPercentage();
        _setReferralFee(bps_);
    }

    function setAllocation(uint16 min_, uint16 max_) external virtual onlyOwner {
        if (max_ < minAllocation || max_ + referralFee > _DENOMINATOR_BPS) revert AllocationOutOfBounds();

        if (min_ < minAllocation) {
            if (_totalSupply > maxSupply / 2) revert AllocationOutOfBounds();
            minAllocation = min_;
        }

        maxAllocation = max_;
        emit AlignmentUpdate(minAllocation, max_);
    }

    // Withdraw non-allocated mint funds
    function withdraw(address recipient, uint256 amount) public virtual override nonReentrant {
        super.withdraw(owner() == address(0) ? alignmentVault : recipient, amount);
    }

    // >>>>>>>>>>>> [ ASSET HANDLING ] <<<<<<<<<<<<

    // Internal handling for receive() and fallback() to reduce code length
    function _processPayment() internal override {
        if (!paused()) {
            mint(msg.sender, (msg.value / price));
        } else {
            // Calculate allocation and split paymeent accordingly
            uint256 mintAlloc = FPML.fullMulDivUp(minAllocation, msg.value, _DENOMINATOR_BPS);
            // Success when transferring to vault isn't checked because transfers to vault cant fail
            payable(alignmentVault).call{ value: mintAlloc }("");
            // Reentrancy risk is ignored here because if owner wants to withdraw that way that's their prerogative
            // But if transfer to owner fails for any reason, it will be sent to the vault
            (bool success, ) = payable(owner()).call{ value: msg.value - mintAlloc }("");
            if (!success) payable(alignmentVault).call{ value: msg.value - mintAlloc }("");
        }
    }

    // Rescue non-aligned tokens from contract, else send aligned tokens to vault
    function rescueERC20(address token_, address recipient_) public virtual override onlyOwner {
        if (token_ == IAlignmentVaultMinimal(alignmentVault).vault()) recipient_ = alignmentVault;
        _sendERC20(token_, recipient_, IERC20(token_).balanceOf(address(this)));
    }

    // Rescue non-aligned NFTs from contract, else send aligned NFTs to vault
    function rescueERC721(address token_, address recipient_, uint256 tokenId_) public virtual override onlyOwner {
        if (token_ == IAlignmentVaultMinimal(alignmentVault).alignedNft()) recipient_ = alignmentVault;
        _sendERC721(token_, recipient_, tokenId_);
    }

    // Forward aligned NFTs to vault, revert if sent other NFTs
    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external virtual returns (bytes4) {
        address nft = IAlignmentVaultMinimal(alignmentVault).alignedNft();
        if (msg.sender == nft) _sendERC721(nft, alignmentVault, tokenId);
        else revert NotAligned();
        return ERC721M.onERC721Received.selector;
    }

    // Forward calldata and payment to AlignmentVault. Used if ERC721M is AlignmentVault owner.
    // Calling this contract using the IAlignmentVaultMinimal interface will trigger this fallback.
    fallback() external payable virtual onlyOwner {
        assembly {
            // Store the target contract address from the storage variable
            let target := sload(alignmentVault.slot)
            // Store the calldata size in memory
            let calldataSize := calldatasize()
            // Copy the calldata to memory
            calldatacopy(0x0, 0x0, calldataSize)
            // Forward the calldata and msg.value to the target contract
            let result := call(gas(), target, callvalue(), 0x0, calldataSize, 0x0, 0x0)
            // Revert with the returned data if the call failed
            if iszero(result) {
                returndatacopy(0x0, 0x0, returndatasize())
                revert(0x0, returndatasize())
            }
            // Return the returned data if the call succeeded
            returndatacopy(0x0, 0x0, returndatasize())
            return(0x0, returndatasize())
        }
    }
}
