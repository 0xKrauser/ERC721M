// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

// ICoreMetadata is imported for passing to child contracts
import { CoreMetadata, ICoreMetadata } from "./CoreMetadata.sol";

import { ERC721 } from "../../../lib/solady/src/tokens/ERC721.sol";
import { ICoreMetadata721 } from "./ICoreMetadata721.sol";

import { IERC165 } from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC165.sol";
import { IERC4906 } from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4906.sol";

abstract contract CoreMetadata721 is CoreMetadata, ERC721, ICoreMetadata721 {
    function name() public view virtual override returns (string memory name_) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory symbol_) {
        return _symbol;
    }

    /// @inheritdoc ICoreMetadata721
    function tokenURI(
        uint256 tokenId_
    ) public view virtual override(ICoreMetadata721, ERC721) returns (string memory tokenURI_) {
        return _tokenURI(tokenId_);
    }

    /**
     * @notice Sets the token URI for a specific token.
     * @param tokenId_ The ID of the token.
     * @param tokenURI_ The new token URI.
     */
    function _setTokenURI(uint256 tokenId_, string memory tokenURI_) internal virtual override {
        CoreMetadata._setTokenURI(tokenId_, tokenURI_);

        emit MetadataUpdate(tokenId_);
    }

    function _setBaseURI(string memory baseURI_, string memory fileExtension_, uint256 maxSupply_) internal virtual {
        CoreMetadata._setBaseURI(baseURI_, fileExtension_);

        emit BatchMetadataUpdate(0, maxSupply_);
    }

    function supportsInterface(bytes4 interfaceId_) public view virtual override returns (bool) {
        return
            interfaceId_ == 0x5b5e139f || // ERC721Metadata
            interfaceId_ == 0x49064906 || // IERC4906
            ERC721.supportsInterface(interfaceId_);
    }
}
