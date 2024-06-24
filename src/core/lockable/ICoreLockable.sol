// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;
import { IERC721Lockable } from "../../../lib/erc721-lockable/contracts/IERC721Lockable.sol";

interface ICoreLockable is IERC721Lockable {
    error AlreadyLocked();

    error NotLocker();

    function transferFrom(address from_, address to_, uint256 tokenId_) external;

    function safeTransferFrom(address from_, address to_, uint256 tokenId_) external;
}
