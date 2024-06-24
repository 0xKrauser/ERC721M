// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {IERC165} from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC165.sol";

interface ICoreRoyalty is IERC165 {
    /**
     * @dev Emitted when the royalty fee for a specific token is updated.
     * @param tokenId_ The ID of the token for which the royalty fee is updated.
     * @param receiver_ The address of the receiver of the royalty fee.
     * @param bps_ The updated royalty fee, represented as a 96-bit fixed-point number.
     */
    event RoyaltiesUpdate(uint256 indexed tokenId_, address indexed receiver_, uint96 indexed bps_);

    /**
     * @dev Emitted when the royalty feature is disabled by setting address(0) as receiver.
     * @custom:unique
     */
    event RoyaltiesDisabled();

    /// @dev Cannot set royalties when they have previously been disabled.
    error DisabledRoyalties();

    /// @dev Cannot set royalties above the maximum value.
    error MaxRoyalties();

    /**
     * @dev Sets the default royalty receiver and fee for the contract.
     * @param recipient_ The address of the recipient_.
     * @param bps_ The royalty fee, represented as a 96-bit fixed-point number.
     */
    function setRoyalties(address recipient_, uint96 bps_) external;

    /**
     * @dev Sets the royalty receiver and fee for a specific token ID.
     * @param tokenId_ The ID of the token.
     * @param recipient_ The address of the recipient.
     * @param bps_ The royalty fee, represented as a 96-bit fixed-point number.
     */
    function setTokenRoyalties(uint256 tokenId_, address recipient_, uint96 bps_) external;

    /**
     * @notice Disables royalties for the contract.
     * @dev Irreversibly disable royalties by resetting tokenId 0 royalty to (address(0), 0)
     * and deleting default royalty info
     */
    function disableRoyalties() external;
}
