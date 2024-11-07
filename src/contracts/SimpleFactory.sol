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

import {ICrate721M} from "./interface/ICrate721M.sol";
import {IFactory} from "./interface/IFactory.sol";
import {TransferFailed} from "@common-resources/crate/contracts/ICore.sol";

import {Ownable} from "solady/src/auth/Ownable.sol";
import {LibClone} from "solady/src/utils/LibClone.sol";

import {IERC1155} from "@openzeppelin/contracts/interfaces/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";

/**
 * @title SimpleFactory
 * @notice Simple factory contract for creating Crate721M contracts
 */
contract SimpleFactory is Ownable {
    error NotAligned();

    event Crate721MDeployed(address indexed contract_, address indexed creator_);

    address public immutable alignedNft;
    address public immutable masterCopy;

    address public constant VAULT_FACTORY = 0xD1ac539e856F8C86c7bf2217eC4b70D0D1c0D82C;

    constructor(address creator_, address alignedNft_, address masterCopy_) {
        _initializeOwner(creator_);
        alignedNft = alignedNft_;
        masterCopy = masterCopy_;
    }

    function createCollection(
        string memory name_,
        string memory symbol_,
        uint32 maxSupply_,
        uint16 royalty_,
        uint16 allocation_,
        uint256 price_,
        uint96 vaultId_,
        bytes32 salt_,
        bytes32 vaultSalt_
    )
        external
        payable
        returns (address collection_)
    {
        if (allocation_ < 1000) revert NotAligned();

        collection_ = LibClone.predictDeterministicAddress(masterCopy, salt_, address(this));
        emit Crate721MDeployed(collection_, msg.sender);
        ICrate721M crate721M = ICrate721M(LibClone.cloneDeterministic(masterCopy, salt_));
        if (address(crate721M) != collection_) revert();

        // Deploy AlignmentVault
        address deployedAV;
        if (salt_ == bytes32("")) deployedAV = IFactory(VAULT_FACTORY).deploy(msg.sender, alignedNft, vaultId_);
        else deployedAV = IFactory(VAULT_FACTORY).deployDeterministic(msg.sender, alignedNft, vaultId_, vaultSalt_);

        crate721M.initialize(name_, symbol_, maxSupply_, royalty_, allocation_, msg.sender, deployedAV, price_);

        // Send initialize payment (if any) to vault
        if (msg.value > 0) {
            (bool success,) = payable(deployedAV).call{value: msg.value}("");
            if (!success) revert TransferFailed();
        }
    }

    /**
     * @notice Used to withdraw any ETH sent to the factory
     */
    function withdrawEth(address recipient) external payable onlyOwner {
        if (recipient == address(0) || recipient == address(0xdead)) revert TransferFailed();
        (bool success,) = payable(recipient).call{value: address(this).balance}("");
        if (!success) revert TransferFailed();
    }

    /**
     * @notice Used to withdraw any ERC20 tokens sent to the factory
     */
    function withdrawERC20(address token, address recipient) external payable onlyOwner {
        if (recipient == address(0) || recipient == address(0xdead)) revert TransferFailed();
        IERC20(token).transfer(recipient, IERC20(token).balanceOf(address(this)));
    }

    /**
     * @notice Used to withdraw any ERC721 tokens sent to the factory
     */
    function withdrawERC721(address token, uint256 tokenId, address recipient) external payable onlyOwner {
        if (recipient == address(0) || recipient == address(0xdead)) revert TransferFailed();
        IERC721(token).transferFrom(address(this), recipient, tokenId);
    }

    /**
     * @notice Used to withdraw any ERC1155 tokens sent to the factory
     */
    function withdrawERC1155(
        address token,
        uint256 tokenId,
        uint256 amount,
        address recipient
    )
        external
        payable
        onlyOwner
    {
        if (recipient == address(0) || recipient == address(0xdead)) revert TransferFailed();
        IERC1155(token).safeTransferFrom(address(this), recipient, tokenId, amount, "");
    }

    /**
     * @notice Used to batch withdraw any ERC1155 tokens sent to the factory
     */
    function withdrawERC1155Batch(
        address token,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        address recipient
    )
        external
        payable
        onlyOwner
    {
        if (recipient == address(0) || recipient == address(0xdead)) revert TransferFailed();
        IERC1155(token).safeBatchTransferFrom(address(this), recipient, tokenIds, amounts, "");
    }
}
