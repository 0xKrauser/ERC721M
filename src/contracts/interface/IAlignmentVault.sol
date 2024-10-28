/*
 * SPDX-License-Identifier: NOASSERTION
 *
 * SPDX-FileType: SOURCE
 *
 * SPDX-FileCopyrightText: 2024 Zodomo <zodomo@proton.me>
 * 
 * SPDX-FileContributor: Zodomo <zodomo@proton.me> 
 */
pragma solidity 0.8.23;

interface IAlignmentVault {
    function vault() external view returns (address);
    function alignedNft() external view returns (address);
}
