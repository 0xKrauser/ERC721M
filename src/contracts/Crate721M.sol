/*
 * SPDX-License-Identifier: NOASSERTION
 *
 * SPDX-FileType: SOURCE
 *
 * SPDX-FileCopyrightText: 2024 Johannes Krauser III <krauser@co.xyz>, Zodomo <zodomo@proton.me>
 *
 * SPDX-FileContributor: Zodomo <zodomo@proton.me>
 * SPDX-FileContributor: Johannes Krauser III <krauser@co.xyz>
 */
pragma solidity 0.8.23;

import {IAlignmentVault} from "./interface/IAlignmentVault.sol";

import {ICrate721M} from "./interface/ICrate721M.sol";

import {ERC721Crate} from "@common-resources/crate/contracts/ERC721Crate.sol";

import {ERC20 as tERC20} from "@common-resources/crate/contracts/types/tERC20.sol";
import {FixedPointMathLib as FPML} from "solady/src/utils/FixedPointMathLib.sol";

import {LibClone} from "solady/src/utils/LibClone.sol";

/**
 * @title Crate721M
 * @author Zodomo.eth (Farcaster/Telegram/Discord/Github: @zodomo, X: @0xZodomo, Email: zodomo@proton.me)
 * @author Johannes Krauser III <krauser@co.xyz>
 * @notice ERC721 Crate with derivative capabilities
 */
contract Crate721M is ERC721Crate, ICrate721M {
    uint16 public minAllocation;
    uint16 public maxAllocation;

    address public alignmentVault;

    constructor() payable {
        _disableInitializers();
    }

    function initialize(
        string memory name_, // Collection name ("Mibera")
        string memory symbol_, // Collection symbol ("MIB")
        uint32 maxSupply_, // Max supply (~1.099T max)
        uint16 royalty_, // Percentage in basis points (420 == 4.20%)
        uint16 allocation_, // Minimum Percentage of mint funds sent to AlignmentVault in bps, min. of 5% (777 == 7.77%)
        address owner_, // Collection contract owner
        address alignmentVault_, // Address of the AlignmentVault contract
        uint256 price_ // Price (~1.2M ETH max)
    )
        external
        payable
        virtual
        initializer
    {
        _initialize(name_, symbol_, maxSupply_, royalty_, owner_, price_);
        if (allocation_ > _DENOMINATOR_BPS) revert AllocationOutOfBounds();
        minAllocation = allocation_;
        maxAllocation = allocation_;

        alignmentVault = alignmentVault_;

        emit AlignmentUpdate(allocation_, allocation_);
    }

    // >>>>>>>>>>>> [ INTERNAL FUNCTIONS ] <<<<<<<<<<<<

    // >>>>>>>>>>>> [ MINT LOGIC ] <<<<<<<<<<<<

    function _handlePayments(uint256 allocation_) internal virtual {
        uint256 value = msg.value;
        if (value > 0) {
            uint256 mintAlloc;
            if (alignmentVault != address(0) && allocation_ > 0) {
                mintAlloc = FPML.fullMulDivUp(allocation_, value, _DENOMINATOR_BPS);
                payable(alignmentVault).call{value: mintAlloc}("");
            }
        }
    }

    function _handleMint(address recipient_, uint256 amount_, address referral_) internal virtual override {
        _handlePayments(minAllocation);
        ERC721Crate._handleMint(recipient_, amount_, referral_);
    }

    function _handleMintWithList(
        bytes32[] calldata proof_,
        uint8 listId_,
        address recipient_,
        uint32 amount_,
        address referral_
    )
        internal
        virtual
        override
    {
        _handlePayments(minAllocation);
        ERC721Crate._handleMintWithList(proof_, listId_, recipient_, amount_, referral_);
    }

    // Standard mint function that supports batch minting and custom allocation
    function mint(address recipient_, uint256 amount_, uint16 allocation_) public payable virtual {
        if (allocation_ < minAllocation || allocation_ > maxAllocation) revert AllocationOutOfBounds();
        _handlePayments(allocation_);
        ERC721Crate._handleMint(recipient_, amount_, address(0));
    }

    // Standard batch mint with custom allocation support and referral fee support
    function mint(address recipient_, uint256 amount_, address referral_, uint16 allocation_) public payable virtual {
        if (allocation_ < minAllocation || allocation_ > maxAllocation) revert AllocationOutOfBounds();
        _handlePayments(allocation_);
        ERC721Crate._handleMint(recipient_, amount_, referral_);
    }

    /**
     * @inheritdoc ERC721Crate
     * @notice Override to account for allocation when setting a percentage going to the referral
     */
    function setReferralFee(uint16 bps_) external virtual override onlyOwner {
        if (bps_ > (_DENOMINATOR_BPS - maxAllocation)) revert MaxReferral();
        _setReferralFee(bps_);
    }

    function _setAllocation(uint16 min_, uint16 max_) internal virtual {
        if (
            (max_ < min_) // Ensure max is greater or equal than min
                || (min_ < minAllocation && _totalSupply != 0) // Ensure min is greater than current min
                || (max_ + referralFee > _DENOMINATOR_BPS) // Ensure max is less than total
        ) {
            revert AllocationOutOfBounds();
        }

        minAllocation = min_;

        maxAllocation = max_;

        emit AlignmentUpdate(minAllocation, max_);
    }

    function setAllocation(uint16 min_, uint16 max_) external virtual onlyOwner {
        _setAllocation(min_, max_);
    }

    // Withdraw non-allocated mint funds
    function withdraw(address recipient, uint256 amount) public virtual override nonReentrant {
        _withdraw(owner() == address(0) && alignmentVault != address(0) ? alignmentVault : recipient, amount);
    }

    // >>>>>>>>>>>> [ ASSET HANDLING ] <<<<<<<<<<<<

    // Internal handling for receive() and fallback() to reduce code length
    function _processPayment() internal virtual override {
        bool mintedOut = (_totalSupply + _reservedSupply) == maxSupply;
        if (mintedOut) {
            uint256 value = msg.value;
            if (value != 0 && alignmentVault != address(0)) {
                // Calculate allocation and split payment accordingly
                if (owner() != address(0)) value = FPML.fullMulDivUp(maxAllocation, value, _DENOMINATOR_BPS);
                payable(alignmentVault).call{value: value}("");
            }
            return;
        }

        if (paused()) revert EnforcedPause();

        mint(msg.sender, (msg.value / price));
    }

    function rescueERC20(address token_, address recipient_) public virtual override onlyOwner {
        if (token_ == IAlignmentVault(alignmentVault).vault()) recipient_ = alignmentVault;
        _sendERC20(token_, recipient_, tERC20.wrap(token_).balanceOf(address(this)));
    }

    /* maybe useless override since any nft that uses this contract uses onERC721Received by default */
    function rescueERC721(address token_, address recipient_, uint256 tokenId_) public virtual override onlyOwner {
        if (token_ == IAlignmentVault(alignmentVault).alignedNft()) recipient_ = alignmentVault;
        _sendERC721(token_, recipient_, tokenId_);
    }

    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes calldata
    )
        external
        virtual
        returns (bytes4 magicBytes)
    {
        address nft = IAlignmentVault(alignmentVault).alignedNft();
        if (msg.sender == nft) _sendERC721(nft, alignmentVault, _tokenId);
        else revert NotAligned();
        return Crate721M.onERC721Received.selector;
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
