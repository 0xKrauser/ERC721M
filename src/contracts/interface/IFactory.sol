/*
 * SPDX-License-Identifier: NOASSERTION
 *
 * SPDX-FileType: SOURCE
 *
 * SPDX-FileCopyrightText: 2024 Zodomo <zodomo@proton.me>
 * 
 * SPDX-FileContributor: Zodomo <zodomo@proton.me> 
 */
pragma solidity 0.8.26;

interface IFactory {
    function deploy(address vaultOwner, address alignedNft, uint96 vaultId) external returns (address);
    function deployDeterministic(
        address vaultOwner,
        address alignedNft,
        uint96 vaultId,
        bytes32 salt
    )
        external
        returns (address);
}
