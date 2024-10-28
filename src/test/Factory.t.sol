/*
 * SPDX-License-Identifier: AGPL-3.0
 *
 * SPDX-FileType: SOURCE
 *
 * SPDX-FileCopyrightText: 2024 Johannes Krauser III <krauser@co.xyz>, Zodomo <zodomo@proton.me>
 *
 * SPDX-FileContributor: Zodomo <zodomo@proton.me>
 * SPDX-FileContributor: Johannes Krauser III <krauser@co.xyz>
 */
pragma solidity ^0.8.23;

import "./_Test.sol";

import {Crate721M} from "../contracts/Crate721M.sol";
import {SimpleFactory} from "../contracts/SimpleFactory.sol";

contract FactoryTest is TestWithHelpers {
    SimpleFactory factory;

    function setUp() public {
        vm.createSelectFork("sepolia");

        address alignedNft = 0xeA9aF8dBDdE2A8d3515C3B4E446eCd41afEdB1C6;
        address masterCopy = address(new Crate721M());
        factory = new SimpleFactory(alignedNft, masterCopy);
    }

    function testDouble() public {
        address collection1 =
            factory.createCollection("name", "symbol", 100, 500, 1000, 100, 21, bytes32(0), bytes32(0));

        vm.expectRevert();
        address collection2 =
            factory.createCollection("name", "symbol", 100, 500, 1000, 100, 21, bytes32(0), bytes32(0));
    }
}
