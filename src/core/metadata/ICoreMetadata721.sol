// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

interface ICoreMetadata721 {
    /// @dev This event emits when the metadata of a token is updated.
    /// So that the third-party platforms such as NFT market could
    /// timely update the images and related attributes of the NFT.
    event MetadataUpdate(uint256 tokenId_);

    /// @dev This event emits when the metadata of a range of tokens is updated.
    /// So that the third-party platforms such as NFT market could
    /// timely update the images and related attributes of the NFTs.
    event BatchMetadataUpdate(uint256 fromTokenId_, uint256 toTokenId_);

    /**
     * @notice Sets the token URI for a specific token.
     * @param tokenId_ The ID of the token.
     * @param tokenURI_ The new token URI.
     */
    function setTokenURI(uint256 tokenId_, string memory tokenURI_) external;

    /**
     * @notice Returns the URI for the given token ID.
     * @dev if the token has a non-empty, manually set URI, it will be returned as is,
     * otherwise it will return the concatenation of the baseURI, the token ID and, optionally,  the file extension.
     * @param tokenId_ the ID of the token to query.
     * @return tokenURI_ a string representing the token URI.
     */
    function tokenURI(uint256 tokenId_) external view returns (string memory tokenURI_);
}
