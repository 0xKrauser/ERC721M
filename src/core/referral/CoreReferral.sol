// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {ICoreReferral} from "./ICoreReferral.sol";
import {TransferFailed} from "../ICore.sol";

import {FixedPointMathLib as FPML} from "../../../lib/solady/src/utils/FixedPointMathLib.sol";

abstract contract CoreReferral is ICoreReferral {
    /// @dev Denominator for basis points. Equivalent to 100% with 2 decimal places.
    uint16 internal constant _DENOMINATOR_BPS = 10_000;

    /**
     * @notice Percentage of the mint value that is paid to the referrer.
     * @dev Referral fee value in BPS.
     */
    uint16 public referralFee;

    function _handleReferral(address referral_, address recipient_) internal virtual {
        if (msg.value > 0 && referral_ != address(0)) {
            if (referral_ == msg.sender || referral_ == recipient_) revert SelfReferral();

            // If referral isn't address(0) and mint isn't free, process sending referral fee
            // Reentrancy is handled by applying ReentrancyGuard to referral mint function
            // [mint(address, uint256, address)]
            //@TODO stash and then withdraw might be better for gas?
            //@TODO referral discounts?
            uint256 referralAlloc = FPML.mulDivUp(referralFee, msg.value, _DENOMINATOR_BPS);

            (bool success,) = payable(referral_).call{value: referralAlloc}("");
            if (!success) revert TransferFailed();

            emit Referral(referral_, referralAlloc);
        }
    }

    function _setReferralFee(uint16 bps_) internal virtual {
        if (bps_ > _DENOMINATOR_BPS) revert MaxPercentage();
        referralFee = bps_;
        emit ReferralFeeUpdate(bps_);
    }
}
