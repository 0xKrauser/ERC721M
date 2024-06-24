// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {ICoreRoyalty, IERC165} from "./ICoreRoyalty.sol";
import {NotZero} from "../ICore.sol";

import {ERC2981} from "../../../lib/solady/src/tokens/ERC2981.sol";

abstract contract CoreRoyalty is ICoreRoyalty, ERC2981 {
    //@TODO opinionated? might consider to move it in factory
    /// @dev Maximum royalty fee in basis points.
    uint16 internal constant _MAX_ROYALTY_BPS = 1000;

    function _requireRoyaltiesEnabled() internal view {
        // Revert if royalties are disabled
        (address receiver,) = royaltyInfo(0, 0);
        if (receiver == address(0)) revert DisabledRoyalties();
    }

    function _setRoyalties(address recipient_, uint96 bps_) internal virtual {
        if (bps_ > _MAX_ROYALTY_BPS) revert MaxRoyalties();

        // Royalty recipient of nonexistent tokenId 0 is used as royalty status indicator, address(0) == disabled
        _setTokenRoyalty(0, recipient_, bps_);
        _setDefaultRoyalty(recipient_, bps_);

        emit RoyaltiesUpdate(0, recipient_, bps_);
    }

    function _setTokenRoyalties(uint256 tokenId_, address recipient_, uint96 bps_) internal virtual {
        if (bps_ > _MAX_ROYALTY_BPS) revert MaxRoyalties();

        // Revert if resetting tokenId 0 as it is utilized for royalty enablement status
        if (tokenId_ == 0) revert NotZero();

        // Reset token royalty if fee is 0, else set it
        if (bps_ == 0) _resetTokenRoyalty(tokenId_);
        else _setTokenRoyalty(tokenId_, recipient_, bps_);

        emit RoyaltiesUpdate(tokenId_, recipient_, bps_);
    }

    function _disableRoyalties() internal virtual {
        _requireRoyaltiesEnabled();

        _deleteDefaultRoyalty();
        _resetTokenRoyalty(0);

        emit RoyaltiesDisabled();
    }

    function supportsInterface(bytes4 interfaceId_) public view virtual override(ERC2981, IERC165) returns (bool) {
        return ERC2981.supportsInterface(interfaceId_) || interfaceId_ == type(IERC165).interfaceId;
    }
}
