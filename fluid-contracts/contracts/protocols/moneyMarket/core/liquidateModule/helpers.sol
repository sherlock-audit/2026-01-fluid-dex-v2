// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./events.sol";

abstract contract Helpers is CommonImport {
    function _useFeeStoredForLiquidation(
        uint256 feeAmountToken0_,
        uint256 feeAmountToken1_,
        uint256 withdrawValue_,
        uint256 token0Price_,
        uint256 token1Price_,
        uint256 token0LiquidationPenalty_,
        uint256 token1LiquidationPenalty_
    ) internal pure returns (uint256 feeCollectionAmountToken0_, uint256 feeCollectionAmountToken1_) {
        if (feeAmountToken0_ > 0) {
            // Scaling up the withdraw value by the token0 liquidation penalty
            // rounded down so protocol is on the winning side
            withdrawValue_ = ((withdrawValue_ * (THREE_DECIMALS + token0LiquidationPenalty_)) - 1) / THREE_DECIMALS;
            if (withdrawValue_ > 0) withdrawValue_ -= 1;

            uint256 feeValue_ = (((feeAmountToken0_ * token0Price_) + 1) / EIGHTEEN_DECIMALS) + 1; // rounded up so protocol is on the winning side

            if (feeValue_ < withdrawValue_) {
                // Full fee amount 0 will be collected
                feeCollectionAmountToken0_ = feeAmountToken0_;
                withdrawValue_ -= feeValue_;

                // This withdraw value was scaled up by liquidation penalty, hence now the remaining portion needs to be scaled down
                // rounded down so protocol is on the winning side
                withdrawValue_ = ((withdrawValue_ * THREE_DECIMALS) - 1) / (THREE_DECIMALS + token0LiquidationPenalty_);
                if (withdrawValue_ > 0) withdrawValue_ -= 1;
            } else {
                // rounded down so protocol is on the winning side
                if (withdrawValue_ > 0) {
                    feeCollectionAmountToken0_ = ((withdrawValue_ * EIGHTEEN_DECIMALS) - 1) / token0Price_;
                    if (feeCollectionAmountToken0_ > 0) feeCollectionAmountToken0_ -= 1;
                }

                // added this check for safety
                if (feeCollectionAmountToken0_ > feeAmountToken0_) {
                    feeCollectionAmountToken0_ = feeAmountToken0_;
                }

                withdrawValue_ = 0;
            }
        }

        // NOTE: We will process further withdrawal using fee stored only if the withdraw value is greater than $0.01 i.e. 1 cent
        if (withdrawValue_ > 1e16 && feeAmountToken1_ > 0) {
            // Scaling up the withdraw value by the token1 liquidation penalty
            // rounded down so protocol is on the winning side
            withdrawValue_ = ((withdrawValue_ * (THREE_DECIMALS + token1LiquidationPenalty_)) - 1) / THREE_DECIMALS;
            if (withdrawValue_ > 0) withdrawValue_ -= 1;

            uint256 feeValue_ = (((feeAmountToken1_ * token1Price_) + 1) / EIGHTEEN_DECIMALS) + 1; // rounded up so protocol is on the winning side

            if (feeValue_ < withdrawValue_) {
                // Reverting here because the the fee wont be able to cover the withdraw value
                revert FluidMoneyMarketError(ErrorTypes.LiquidateModule__InvalidParams);
            } else {
                // rounded down so protocol is on the winning side
                feeCollectionAmountToken1_ = ((withdrawValue_ * EIGHTEEN_DECIMALS) - 1) / token1Price_;
                if (feeCollectionAmountToken1_ > 0) feeCollectionAmountToken1_ -= 1;

                // added this check for safety
                if (feeCollectionAmountToken1_ > feeAmountToken1_) {
                    feeCollectionAmountToken1_ = feeAmountToken1_;
                }

                withdrawValue_ = 0;
            }
        }

        if (withdrawValue_ > 1e16) {
            revert FluidMoneyMarketError(ErrorTypes.LiquidateModule__InvalidParams);
        }
    }
}