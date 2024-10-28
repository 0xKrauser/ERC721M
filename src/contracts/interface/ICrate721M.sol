/*
 * SPDX-License-Identifier: NOASSERTION
 *
 * SPDX-FileType: SOURCE
 *
 * SPDX-FileCopyrightText: 2024 Johannes Krauser III <krauser@co.xyz>
 * 
 * SPDX-FileContributor: Johannes Krauser III <krauser@co.xyz> 
 */
pragma solidity 0.8.23;

interface ICrate721M {
    // >>>>>>>>>>>> [ ERRORS ] <<<<<<<<<<<<
    error AllocationOutOfBounds();

    error AllocationOverflow();

    error NotAligned();

    // >>>>>>>>>>>> [ EVENTS ] <<<<<<<<<<<<

    event AlignmentUpdate(uint16 min_, uint16 max_);

    function initialize(
        string memory name_,
        string memory symbol_,
        uint32 maxSupply_,
        uint16 royalty_,
        uint16 allocation_,
        address owner_,
        address alignedNft_,
        uint256 price_,
        uint96 vaultId_,
        bytes32 salt_
    )
        external
        payable;
}
