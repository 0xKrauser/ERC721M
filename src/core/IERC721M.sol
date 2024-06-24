// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

interface IERC721M {
    // >>>>>>>>>>>> [ ERRORS ] <<<<<<<<<<<<

    // >>>>>>>>>>>> [ EVENTS ] <<<<<<<<<<<<

    event AlignmentUpdate(uint256 indexed minAllocation, uint256 indexed maxAllocation);

    error AllocationOutOfBounds();

    error NotAligned();

    error CannotLowerAllocationAfterMint();

    error AllocationOverflow();
}
