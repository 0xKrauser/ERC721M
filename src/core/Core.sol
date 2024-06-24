// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import { Ownable } from "../../lib/solady/src/auth/Ownable.sol";
import { Pausable } from "../../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "../../lib/solady/src/utils/ReentrancyGuard.sol";

import { ICore, NotZero, TransferFailed } from "./ICore.sol";
import { MintList } from "./lists/ICoreList.sol";

import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { IERC721 } from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";

abstract contract Core is ICore, Ownable, Pausable, ReentrancyGuard {
    /// @dev Price of minting a single unit.
    uint256 public price;
    // <256> {{

    /// @dev Maximum supply of tokens that can be minted.
    uint32 public maxSupply;

    /// @dev Total supply of tokens minted.
    uint32 internal _totalSupply;

    /// @dev The number of tokens that can be minted by a single user.
    uint32 public userSupply;

    /// @dev The number of tokens that are minted per each mint of 1.
    uint24 public unit;

    /// @notice timestamp for the start of the minting process
    uint32 public start;

    /// @notice timestamp for the end of the minting process
    uint32 public end;
    // }} <256>

    mapping(address wallet_ => uint256 claimed) internal _claimed;

    /**
     * @dev Checks if mint execution respects the minting period and supply.
     * @param amount_ The amount to be minted.
     * @return tokenAmount_ The amount of tokens to minted.
     */
    function _canMint(uint256 amount_) internal view virtual returns (uint256 tokenAmount_) {
        _requireNotPaused();

        if (msg.value < (price * amount_)) revert InsufficientPayment();

        tokenAmount_ = amount_ * unit;

        if (_totalSupply + tokenAmount_ > maxSupply) revert MaxSupply();
        if (_claimed[msg.sender] + tokenAmount_ > userSupply) revert ClaimSupply();

        if ((start != 0 && block.timestamp < start) || (end != 0 && block.timestamp > end)) revert TimeOutOfBounds();
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function claimedOf(address wallet_) external view returns (uint256) {
        return _claimed[wallet_];
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Sets the price for minting a single token.
     * @param newPrice The new price.
     */
    function setPrice(uint72 newPrice) external virtual onlyOwner {
        price = newPrice;
        emit PriceUpdate(newPrice);
    }

    function setMintPeriod(uint32 start_, uint32 end_) external onlyOwner {
        if (end_ != 0 && start_ > end_) revert TimestampEnd();
        if (start == 0 && start != start_) _unpause(); // Open minting if it wasn't already
        start = start_;
        end = end_;

        emit MintPeriodUpdate(start_, end_);
    }

    function setClaimableUserSupply(uint32 claimable_) external virtual onlyOwner {
        if (claimable_ == 0) revert NotZero();
        userSupply = claimable_;
        emit UserClaimableUpdate(claimable_);
    }

    function setUnit(uint24 unit_) external virtual onlyOwner {
        if (unit_ == 0) revert NotZero();
        unit = unit_;
        emit UnitUpdate(unit_);
    }

    /**
     * @notice Sets the maximum supply of tokens that can be minted.
     * @param maxSupply_ The new maximum supply.
     * If maxSupply_ is less than the current supply, the function will revert.
     * If minting has already started and maxSupply_ is greater than current maxSupply, the function will revert.
     */
    function setSupply(uint32 maxSupply_) external virtual onlyOwner {
        if (maxSupply_ < _totalSupply) revert UnderSupply();
        _setMaxSupply(maxSupply_);
    }

    function _setMaxSupply(uint32 maxSupply_) internal {
        if (maxSupply_ > maxSupply && _totalSupply != 0) revert MaxSupply();

        maxSupply = maxSupply_;
        emit SupplyUpdate(maxSupply_);
    }

    /**
     * @notice Withdraws funds from the contract.
     * @param recipient_ The address to which the funds are withdrawn.
     * @param amount_ The amount of funds withdrawn.
     */
    function withdraw(address recipient_, uint256 amount_) public virtual nonReentrant {
        if (recipient_ == address(0)) revert NotZero();

        // Cache owner address to save gas
        address owner = owner();
        bool forfeit = owner == address(0);

        // If contract is owned and caller isn't them, revert.
        if (!forfeit && owner != msg.sender) revert Unauthorized();

        uint256 balance = address(this).balance;
        // Instead of reverting for overage, simply overwrite amount with balance
        if (amount_ > balance || forfeit) amount_ = balance;

        // Process withdrawal
        (bool success, ) = payable(recipient_).call{ value: amount_ }("");
        if (!success) revert TransferFailed();

        emit Withdraw(recipient_, amount_);
    }

    function _sendERC20(address token_, address recipient_, uint256 amount_) internal virtual {
        IERC20(token_).transfer(recipient_, amount_);
    }

    /**
     * @dev function to retrieve erc20 from the contract
     * @param token_ The address of the ERC20 token.
     * @param recipient_ The address to which the tokens are transferred.
     */
    function rescueERC20(address token_, address recipient_) public virtual onlyOwner {
        uint256 balance = IERC20(token_).balanceOf(address(this));
        _sendERC20(token_, recipient_, balance);
    }

    function _sendERC721(address token_, address recipient_, uint256 tokenId_) internal virtual {
        IERC721(token_).transferFrom(address(this), recipient_, tokenId_);
    }

    /**
     * @notice Rescue ERC721 tokens from the contract.
     * @param token_ The address of the ERC721 to retrieve.
     * @param recipient_ The address to which the token is transferred.
     * @param tokenId_ The ID of the token to be transferred.
     */
    function rescueERC721(address token_, address recipient_, uint256 tokenId_) public virtual onlyOwner {
        _sendERC721(token_, recipient_, tokenId_);
    }

    ///@dev Internal handling of ether acquired through received().
    function _processPayment() internal virtual {
        if (msg.sender == address(0) || msg.value == 0) revert NotZero();
        (bool success, ) = payable(owner()).call{ value: msg.value }("");
        if (!success) revert TransferFailed();
    }

    /// @dev Fallback function to accept ether.
    receive() external payable virtual {
        _processPayment();
    }
}
