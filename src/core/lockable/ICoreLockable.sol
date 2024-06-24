// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

/* is IERC721Lockable */ interface ICoreLockable {
    /**
     * @dev Emitted when `id` token is locked, and `unlocker` is stated as unlocking wallet.
     */
    event Lock(address indexed unlocker, uint256 indexed id);

    /**
     * @dev Emitted when `id` token is unlocked.
     */
    event Unlock(uint256 indexed id);

    error AlreadyLocked();

    error NotLocker();

    function transferFrom(address from_, address to_, uint256 tokenId_) external;

    function safeTransferFrom(address from_, address to_, uint256 tokenId_) external;
}
