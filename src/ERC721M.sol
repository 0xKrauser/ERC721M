// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

// >>>>>>>>>>>> [ IMPORTS ] <<<<<<<<<<<<

import {ERC721Core} from "./ERC721Core.sol";
import {FixedPointMathLib as FPML} from "../lib/solady/src/utils/FixedPointMathLib.sol";

import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC721} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";

// >>>>>>>>>>>> [ INTERFACES ] <<<<<<<<<<<<

interface IAlignmentVaultMinimal {
    function vault() external view returns (address);
    function alignedNft() external view returns (address);
}

interface IFactory {
    function deploy(address vaultOwner, address alignedNft, uint96 vaultId) external returns (address);
    function deployDeterministic(address vaultOwner, address alignedNft, uint96 vaultId, bytes32 salt) external returns (address);
}

/**
 * @title ERC721M
 * @author Zodomo.eth (Farcaster/Telegram/Discord/Github: @zodomo, X: @0xZodomo, Email: zodomo@proton.me)
 * @notice A NFT template that can be configured to automatically send a portion of mint funds to an AlignmentVault
 * @custom:github https://github.com/Zodomo/ERC721M
 */
contract ERC721M is ERC721Core {

    // >>>>>>>>>>>> [ ERRORS ] <<<<<<<<<<<<

    error NotAligned();

    // >>>>>>>>>>>> [ EVENTS ] <<<<<<<<<<<<

    event AlignmentUpdate(uint16 indexed minAllocation, uint16 indexed maxAllocation);

    // >>>>>>>>>>>> [ STORAGE ] <<<<<<<<<<<<

    // Address of AlignmentVaultFactory, used when deploying AlignmentVault
    address public constant vaultFactory = 0x7c1A6B4B373E70730c52dfCB2e0A67E7591d4AAa;
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
        uint40 _maxSupply, // Max supply (~1.099T max)
        uint16 _royalty, // Percentage in basis points (420 == 4.20%)
        uint16 _allocation, // Minimum Percentage of mint funds to AlignmentVault in basis points, minimum of 5% (777 == 7.77%)
        address _owner, // Collection contract owner
        address _alignedNft, // Address of NFT to configure AlignmentVault for, must have NFTX vault!
        uint80 _price, // Price (~1.2M ETH max)
        uint96 _vaultId, // NFTX Vault ID, please check!
        bytes32 _salt // AV Deployment salt
    ) external payable virtual initializer {
        // Confirm mint alignment allocation is within valid range
        //@TODO opinionated magic number, maybe move this to the factory
        if (_allocation < 500) revert NotAligned(); // Require allocation be >= 5%
        if (_allocation > _DENOMINATOR_BPS) revert Invalid(); // Require allocation and royalty be <= 100%
        minAllocation = _allocation;
        maxAllocation = _allocation;

        // Initialize ERC721Core
        _initialize(name_, symbol_, _maxSupply, _royalty, _owner, _price);
        
        // Deploy AlignmentVault
        address deployedAV;
        if (_salt == bytes32("")) deployedAV = IFactory(vaultFactory).deploy(_owner, _alignedNft, _vaultId);
        else deployedAV = IFactory(vaultFactory).deployDeterministic(_owner, _alignedNft, _vaultId, _salt);
        alignmentVault = deployedAV;
        // Send initialize payment (if any) to vault
        if (msg.value > 0) {
            (bool success,) = payable(deployedAV).call{ value: msg.value }("");
            if (!success) revert TransferFailed();
        }
        emit AlignmentUpdate(_allocation, _allocation);
    }

    // >>>>>>>>>>>> [ INTERNAL FUNCTIONS ] <<<<<<<<<<<<

    // >>>>>>>>>>>> [ MINT LOGIC ] <<<<<<<<<<<<

    function _mint(address recipient, uint256 amount, address referral) internal override {
        _mint(recipient, amount, referral, minAllocation);
    }

    // Solady ERC721 _mint override to implement mint funds alignment and blacklist
    function _mint(address recipient, uint256 amount, address referral, uint16 allocation) internal {
        // Prevent bad inputs
        if (recipient == address(0) || amount == 0) revert Invalid();
        // Ensure minter and recipient don't hold blacklisted assets
        _enforceBlacklist(msg.sender, recipient);
        
        //@TODO maybe we can do this before everything else and then call super._mint

        // Ensure allocation set by the user is in the range between minAllocation and maxAllocation

        if(allocation < minAllocation || allocation > maxAllocation) revert Invalid();
        // Calculate allocation
        uint256 mintAlloc = FPML.fullMulDivUp(allocation, msg.value, _DENOMINATOR_BPS);

        if (msg.value > 0) {
            // Send aligned amount to AlignmentVault (success is intentionally not read to save gas as it cannot fail)
            payable(alignmentVault).call{value: mintAlloc}("");
            // If referral isn't address(0), process sending referral fee
            // Reentrancy is handled by applying ReentrancyGuard to referral mint function [mint(address, uint256, address)]
            if (referral != address(0) && referral != msg.sender) {
                uint256 referralAlloc = FPML.mulDivUp(referralFee, msg.value, _DENOMINATOR_BPS);
                (bool success, ) = payable(referral).call{value: referralAlloc}("");
                if (!success) revert TransferFailed();
                emit ReferralFeePaid(referral, referralAlloc);
            }
        }

        // Process ERC721 mints
        // totalSupply is read once externally from loop to reduce SLOADs to save gas
        uint256 supply = _totalSupply;
        for (uint256 i; i < amount;) {
            _mint(recipient, ++supply);
            unchecked {
                ++i;
            }
        }
        unchecked {
            _totalSupply += uint40(amount);
        }
    }

    // Standard mint function that supports batch minting and custom allocation
    function mint(address recipient, uint256 amount, uint16 allocation) public payable virtual mintable(amount) {
        if (!mintOpen) revert MintClosed();
        if (msg.value < (price * amount)) revert InsufficientPayment();
        _mint(recipient, amount, address(0), allocation);
    }

    // Standard batch mint with custom allocation support and referral fee support
    function mint(address recipient, uint256 amount, address referral, uint16 allocation) public payable virtual mintable(amount) nonReentrant {
        if (!mintOpen) revert MintClosed();
        if (referral == msg.sender) revert Invalid();
        if (msg.value < (price * amount)) revert InsufficientPayment();
        _mint(recipient, amount, referral, allocation);
    }

    // >>>>>>>>>>>> [ PERMISSIONED / OWNER FUNCTIONS ] <<<<<<<<<<<<

    function setReferralFee(uint16 newReferralFee) external virtual override onlyOwner {
        if (newReferralFee > (_DENOMINATOR_BPS - maxAllocation)) revert Invalid();
        referralFee = newReferralFee;
        emit ReferralFeeUpdate(newReferralFee);
    }

    // Increase mint alignment allocation
    // NOTE: There will be no function to decrease this value. This operation is one-way only.
    function increaseAlignment(uint16 newMinAllocation, uint16 newMaxAllocation) external virtual onlyOwner {
        uint16 _minAllocation = minAllocation;
        if (newMaxAllocation < _minAllocation) revert Invalid();
        // Prevent oversetting alignment (keeping maxAllocation in mind)
        if (newMaxAllocation + referralFee > _DENOMINATOR_BPS) revert Invalid();
        // Prevent alignment deception (changing it last mint) by locking minAllocation in at 50% minted
        if (totalSupply() < maxSupply / 2) {
            if (newMinAllocation < _minAllocation || newMinAllocation > newMaxAllocation) revert Invalid();
            minAllocation = newMinAllocation;
        } else newMinAllocation = _minAllocation;
        maxAllocation = newMaxAllocation;
        emit AlignmentUpdate(newMinAllocation, newMaxAllocation);
    }

    // Withdraw non-allocated mint funds
    function withdrawFunds(address recipient, uint256 amount) external virtual override nonReentrant {
        // Cache owner address to save gas
        address owner = owner();
        uint256 balance = address(this).balance;
        if (recipient == address(0)) revert Invalid();
        // If contract is owned and caller isn't them, revert.
        if (owner != address(0) && owner != msg.sender) revert Unauthorized();
        // If contract is renounced, convert recipient to vault and withdraw all funds to it
        if (owner == address(0)) {
            recipient = alignmentVault;
            amount = balance;
        }
        // Instead of reverting for overage, simply overwrite amount with balance
        if (amount > balance) amount = balance;

        // Process withdrawal
        (bool success,) = payable(recipient).call{ value: amount }("");
        if (!success) revert TransferFailed();
        emit Withdraw(recipient, amount);
    }

    // >>>>>>>>>>>> [ ASSET HANDLING ] <<<<<<<<<<<<

    // Internal handling for receive() and fallback() to reduce code length
    function _processPayment() internal override {
        if (mintOpen) mint(msg.sender, (msg.value / price));
        else {
        // Calculate allocation and split paymeent accordingly
        uint256 mintAlloc = FPML.fullMulDivUp(minAllocation, msg.value, _DENOMINATOR_BPS);
        // Success when transferring to vault isn't checked because transfers to vault cant fail
        payable(alignmentVault).call{ value: mintAlloc }("");
        // Reentrancy risk is ignored here because if owner wants to withdraw that way that's their prerogative
        // But if transfer to owner fails for any reason, it will be sent to the vault
        (bool success,) = payable(owner()).call{ value: msg.value - mintAlloc }("");
        if (!success) payable(alignmentVault).call{ value: msg.value - mintAlloc }("");
        }
    }

    // Rescue non-aligned tokens from contract, else send aligned tokens to vault
    function rescueERC20(address addr, address recipient) external virtual override onlyOwner {
        uint256 balance = IERC20(addr).balanceOf(address(this));
        if (addr == IAlignmentVaultMinimal(alignmentVault).vault()) {
            IERC20(addr).transfer(alignmentVault, balance);
        } else {
            IERC20(addr).transfer(recipient, balance);
        }
    }

    // Rescue non-aligned NFTs from contract, else send aligned NFTs to vault
    function rescueERC721(address addr, address recipient, uint256 tokenId) external virtual override onlyOwner {
        if (addr == IAlignmentVaultMinimal(alignmentVault).alignedNft()) {
            IERC721(addr).safeTransferFrom(address(this), alignmentVault, tokenId);
        } else {
            IERC721(addr).transferFrom(address(this), recipient, tokenId);
        }
    }

    // Forward aligned NFTs to vault, revert if sent other NFTs
    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external virtual returns (bytes4) {
        address nft = IAlignmentVaultMinimal(alignmentVault).alignedNft();
        if (msg.sender == nft) IERC721(nft).safeTransferFrom(address(this), alignmentVault, tokenId);
        else revert NotAligned();
        return ERC721M.onERC721Received.selector;
    }

    // Process all received ETH payments
    receive() external payable virtual override {
        _processPayment();
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