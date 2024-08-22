/*
 * SPDX-License-Identifier: AGPL-3.0
 *
 * SPDX-FileType: SOURCE
 *
 * SPDX-FileCopyrightText: 2024 Johannes Krauser III <krauser@co.xyz>, Zodomo <zodomo@proton.me>
 *
 * SPDX-FileContributor: Zodomo <zodomo@proton.me>
 * SPDX-FileContributor: Johannes Krauser III <detroitmetalcrypto@gmail.com>
 */
pragma solidity ^0.8.23;

import "forge-std/src/Test.sol";

contract TestWithHelpers is Test {
    function _bytesToAddress(bytes32 fuzzedBytes) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(fuzzedBytes)))));
    }
}
