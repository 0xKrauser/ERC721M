// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {IAsset} from "../blacklist/IAsset.sol";
import {ICoreBlacklist} from "../blacklist/ICoreBlacklist.sol";

import {EnumerableSetLib} from "../../../lib/solady/src/utils/EnumerableSetLib.sol";

/**
 * @title CoreBlacklist
 * @author 0xKrauser (Discord/Github/X: @0xKrauser, Email: detroitmetalcrypto@gmail.com)
 * @notice Core Module for managing a blacklist of assets and permission their owners.
 * @custom:github https://github.com/Zodomo/ERC721M
 */
abstract contract CoreBlacklist is ICoreBlacklist {
    using EnumerableSetLib for EnumerableSetLib.AddressSet;

    /// @dev Enumerable set of blacklisted asset addresses.
    EnumerableSetLib.AddressSet internal _blacklist;

    /// @inheritdoc ICoreBlacklist
    function getBlacklist() external view virtual returns (address[] memory blacklist_) {
        return _blacklist.values();
    }

    // @TODO: shouldn't blacklisted also be enforced on transfer?

    /**
     * @notice Adds or removes assets to the blacklist.
     * @param assets_ The list of addresses to be blacklisted.
     * @param status_ The status to which they have been updated.
     */
    function _setBlacklist(address[] calldata assets_, bool status_) internal virtual {
        for (uint256 i; i < assets_.length; ++i) {
            if (status_) _blacklist.add(assets_[i]);
            else _blacklist.remove(assets_[i]);
        }
        emit BlacklistUpdate(assets_, status_);
    }

    /**
     * @dev Blacklist function to prevent mints to and from holders of prohibited assets,
     * applied both on minter and recipient
     * @param recipient_ The address of the recipient.
     */
    function _enforceBlacklist(address recipient_) internal virtual {
        address[] memory blacklist = _blacklist.values();
        uint256 count;
        for (uint256 i = 1; i < blacklist.length;) {
            unchecked {
                count += IAsset(blacklist[i]).balanceOf(msg.sender);
                count += IAsset(blacklist[i]).balanceOf(recipient_);
                if (count > 0) revert Blacklisted();
                ++i;
            }
        }
    }
}
