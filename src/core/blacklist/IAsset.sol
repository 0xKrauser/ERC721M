// SPDX-FileCopyrightText: 2024 Zodomo.eth <zodomo@proton.me>
//
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.23;

interface IAsset {
    function balanceOf(address holder) external returns (uint256);
}
