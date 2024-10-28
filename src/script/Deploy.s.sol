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

import "forge-std/src/Script.sol";

import {Crate721M} from "../contracts/Crate721M.sol";
import {SimpleFactory} from "../contracts/SimpleFactory.sol";
import {MintList} from "@common-resources/crate/contracts/extensions/lists/IMintlistExt.sol";

contract FactoryTest is Script {
    SimpleFactory factory;

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address alignedNft = 0xeA9aF8dBDdE2A8d3515C3B4E446eCd41afEdB1C6;
        address masterCopy = address(new Crate721M());
        factory = new SimpleFactory(alignedNft, masterCopy);

        address payable collection1 =
            payable(factory.createCollection("name", "symbol", 100, 500, 1000, 0.001 ether, 21, bytes32(0), bytes32(0)));

        Crate721M collection = Crate721M(collection1);
        collection.unpause();

        collection.setReferralFee(500);

        MintList memory mintList = MintList({
            root: bytes32(0),
            maxSupply: 20,
            price: 0.00001 ether,
            unit: 1,
            start: 0,
            end: 0,
            userSupply: 5,
            reserved: false,
            paused: false
        });

        collection.setList(
            mintList.price,
            0,
            mintList.root,
            mintList.userSupply,
            mintList.maxSupply,
            mintList.start,
            mintList.end,
            mintList.unit,
            mintList.reserved,
            mintList.paused
        );

        collection.mint{value: 0.002 ether}(2);

        bytes32[] memory proof = new bytes32[](0);

        collection.mint{value: 0.00001 ether}(proof, 1, address(this), 1, address(0));
    }
}
