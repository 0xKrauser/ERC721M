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

import {LibClone} from "solady/src/utils/LibClone.sol";

/**
 * @title SimpleFactory
 * @notice Simple factory contract for creating Crate721M contracts
 */
contract SimpleFactory {
    error NotAligned();

    event Crate721MDeployed(address indexed contract_, address indexed creator_);

    address public immutable alignedNft;
    address public immutable masterCopy;

    constructor(address alignedNft_, address masterCopy_) {
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
        returns (address collection_)
    {
        if (allocation_ < 1000) revert NotAligned();

        address creator = msg.sender;
        collection_ = LibClone.predictDeterministicAddress(masterCopy, salt_, address(this));
        emit Crate721MDeployed(collection_, creator);
        ICrate721M crate721M = ICrate721M(LibClone.cloneDeterministic(masterCopy, salt_));
        if (address(crate721M) != collection_) revert();

        crate721M.initialize(
            name_, symbol_, maxSupply_, royalty_, allocation_, creator, alignedNft, price_, vaultId_, vaultSalt_
        );
    }
}
