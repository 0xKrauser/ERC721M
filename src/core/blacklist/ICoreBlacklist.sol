// SPDX-FileCopyrightText: 2024 Johannes Krauser III <detroitmetalcrypto@gmail.com>
//
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.23;

interface ICoreBlacklist {
    /**
     * @dev Emitted when the blacklist is updated.
     * @param blacklistedAssets The list of addresses marked for blacklist addition/removal.
     * @param status The status to which they have been updated.
     */
    event BlacklistUpdate(address[] indexed blacklistedAssets, bool indexed status);

    /// @dev Cannot execute an operation from a address than owns blacklisted assets.
    error Blacklisted();

    /**
     * @dev list of blacklisted assets, used to prevent mints to and from holders of prohibited assets
     * @return blacklist_ an array of blacklisted asset addresses.
     */
    function getBlacklist() external view returns (address[] memory blacklist_);

    /**
     * @notice Adds or removes assets to the blacklist.
     * @param assets_ The list of addresses to be blacklisted.
     * @param status_ The status to which they have been updated.
     */
    function setBlacklist(address[] calldata assets_, bool status_) external;
}
