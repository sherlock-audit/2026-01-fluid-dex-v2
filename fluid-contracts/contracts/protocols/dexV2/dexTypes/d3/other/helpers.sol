// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import "./variables.sol";
import { LiquiditySlotsLink as LSL } from "../../../../../libraries/liquiditySlotsLink.sol";

abstract contract Helpers is Variables {
    modifier _onlyDelegateCall() {
        if (address(this) == THIS_CONTRACT) revert FluidDexV2D3D4Error(ErrorTypes.Helpers__OnlyDelegateCallAllowed);
        _;
    }

    function _calculateVars(
        address token0_,
        address token1_,
        uint256 dexVariables2_
    ) internal view returns (CalculatedVars memory calculatedVars_) {
        // temp_ => token 0 decimals
        uint256 temp_ = (dexVariables2_ >> DSL.BITS_DEX_V2_VARIABLES2_TOKEN_0_DECIMALS) & X4;
        if (temp_ == 15) temp_ = 18;

        (calculatedVars_.token0NumeratorPrecision, calculatedVars_.token0DenominatorPrecision) = 
            _calculateNumeratorAndDenominatorPrecisions(temp_);

        // temp_ => token 1 decimals
        temp_ = (dexVariables2_ >> DSL.BITS_DEX_V2_VARIABLES2_TOKEN_1_DECIMALS) & X4;
        if (temp_ == 15) temp_ = 18;

        (calculatedVars_.token1NumeratorPrecision, calculatedVars_.token1DenominatorPrecision) = 
            _calculateNumeratorAndDenominatorPrecisions(temp_);

        // temp_ => token 0 exchange price storage slot data
        temp_ = LIQUIDITY.readFromStorage(LSL.calculateMappingStorageSlot(LSL.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT, token0_));
        if (temp_ == 0) {
            calculatedVars_.token0SupplyExchangePrice = LC.EXCHANGE_PRICES_PRECISION;
        } else {
            (calculatedVars_.token0SupplyExchangePrice, ) = LC.calcExchangePrices(temp_);
        }

        // temp_ => token 1 exchange price storage slot data
        temp_ = LIQUIDITY.readFromStorage(LSL.calculateMappingStorageSlot(LSL.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT, token1_));
        if (temp_ == 0) {
            calculatedVars_.token1SupplyExchangePrice = LC.EXCHANGE_PRICES_PRECISION;
        } else {
            (calculatedVars_.token1SupplyExchangePrice, ) = LC.calcExchangePrices(temp_);
        }
    }
}
