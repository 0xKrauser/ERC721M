// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import { ICoreLockable } from "./ICoreLockable.sol";

abstract contract CoreLockable is ICoreLockable {
    mapping(uint256 tokenId_ => address locker_) public locked;

    function _lock(uint256 id_) internal virtual {
        if (locked[id_] != address(0)) revert AlreadyLocked();
        locked[id_] = msg.sender;
    }

    function _unlock(uint256 id_) internal virtual {
        if (locked[id_] != msg.sender) revert NotLocker();
        delete locked[id_];
    }
}
