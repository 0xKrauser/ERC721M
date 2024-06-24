// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

interface ICoreMetadata1155 {
    /**
     * @dev Returns the URI for the given token ID.
     * @param tokenId_ The token ID to query.
     */
    function uri(uint256 tokenId_) external view returns (string memory tokenURI_);

    /**
     * @dev Sets `tokenURI` as the tokenURI of `tokenId`.
     * @param tokenId_ The token id to set the URI for.
     * @param tokenURI_ The URI to assign.
     */
    function setURI(uint256 tokenId_, string calldata tokenURI_) external;
}
