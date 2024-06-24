// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {CoreMetadata} from "./CoreMetadata.sol";

import {ICoreMetadata1155} from "./ICoreMetadata1155.sol";

abstract contract CoreMetadata1155 is CoreMetadata, ICoreMetadata1155 {
    /**
     * @inheritdoc ICoreMetadata1155
     */
    function uri(uint256 tokenId_) external view virtual returns (string memory tokenURI_) {
        return _tokenURI(tokenId_);
    }
}
