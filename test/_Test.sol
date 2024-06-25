// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;
import "../lib/forge-std/src/Test.sol";

contract TestWithHelpers is Test {
    function _bytesToAddress(bytes32 fuzzedBytes) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(fuzzedBytes)))));
    }
}
