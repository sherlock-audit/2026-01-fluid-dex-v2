// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./adminModuleInternals.sol";
import { PoolLock as PL } from "../../../../../libraries/dexV2PoolLock.sol";

abstract contract CommonControllerModuleInternals is CommonAdminModuleInternals {
    function _updateFetchDynamicFeeFlag(DexKey memory dexKey_, bool newFetchDynamicFeeFlag_, uint256 dexType_) internal {
        bytes32 dexId_ = _getValidDex(dexKey_, dexType_);
        PL.lock(dexId_);

        // You cant change fetch dynamic fee flag if its not a dynamic fee pool
        if (dexKey_.fee != DYNAMIC_FEE_FLAG) {
            revert FluidDexV2D3D4Error(ErrorTypes.ControllerModule__NotDynamicFeePool);
        }

        _dexVariables2[dexType_][dexId_] = _dexVariables2[dexType_][dexId_] & ~(X1 << DSL.BITS_DEX_V2_VARIABLES2_FETCH_DYNAMIC_FEE_FLAG) |
            (uint256(newFetchDynamicFeeFlag_ ? 1 : 0) << DSL.BITS_DEX_V2_VARIABLES2_FETCH_DYNAMIC_FEE_FLAG);

        emit LogUpdateFetchDynamicFeeFlag(dexType_, dexId_, newFetchDynamicFeeFlag_);

        PL.unlock(dexId_);
    }

    function _updateFeeVersion0(DexKey memory dexKey_, uint256 lpFee_, uint256 dexType_) internal {
        bytes32 dexId_ = _getValidDex(dexKey_, dexType_);
        PL.lock(dexId_);

        // You cant change fee version if its not a dynamic fee pool
        if (dexKey_.fee != DYNAMIC_FEE_FLAG) {
            revert FluidDexV2D3D4Error(ErrorTypes.ControllerModule__NotDynamicFeePool);
        }

        if (lpFee_ > X16) {
            revert FluidDexV2D3D4Error(ErrorTypes.ControllerModule__LpFeeInvalid);
        }

        // We clear entire 104 bits used for fee related things if not already
        _dexVariables2[dexType_][dexId_] = _dexVariables2[dexType_][dexId_] & ~(X104 << DSL.BITS_DEX_V2_VARIABLES2_FEE_VERSION) |
            (uint256(0) << DSL.BITS_DEX_V2_VARIABLES2_FEE_VERSION) | // Setting fee version to 0
            (lpFee_ << DSL.BITS_DEX_V2_VARIABLES2_LP_FEE);
        
        emit LogUpdateFeeVersion0(dexType_, dexId_, lpFee_);

        PL.unlock(dexId_);
    }

    function _updateFeeVersion1(
        DexKey memory dexKey_,
        uint256 maxDecayTime_, 
        uint256 priceImpactToFeeDivisionFactor_, 
        uint256 minFee_, 
        uint256 maxFee_, 
        uint256 dexType_
    ) internal {
        bytes32 dexId_ = _getValidDex(dexKey_, dexType_);
        PL.lock(dexId_);

        // You cant change fee version if its not a dynamic fee pool
        if (dexKey_.fee != DYNAMIC_FEE_FLAG) {
            revert FluidDexV2D3D4Error(ErrorTypes.ControllerModule__NotDynamicFeePool);
        }

        if (maxDecayTime_ > X12) {
            revert FluidDexV2D3D4Error(ErrorTypes.ControllerModule__MaxDecayTimeInvalid);
        }
        if (priceImpactToFeeDivisionFactor_ > X8) {
            revert FluidDexV2D3D4Error(ErrorTypes.ControllerModule__PriceImpactDivisionFactorInvalid);
        }
        if (minFee_ > X16) {
            revert FluidDexV2D3D4Error(ErrorTypes.ControllerModule__MinFeeInvalid);
        }
        if (maxFee_ > X16) {
            revert FluidDexV2D3D4Error(ErrorTypes.ControllerModule__MaxFeeInvalid);
        }
        if (minFee_ >= maxFee_) {
            revert FluidDexV2D3D4Error(ErrorTypes.ControllerModule__MinFeeGteMaxFee);
        }

        // We clear entire 104 bits used for fee related things if not already
        _dexVariables2[dexType_][dexId_] = _dexVariables2[dexType_][dexId_] & ~(X104 << DSL.BITS_DEX_V2_VARIABLES2_FEE_VERSION) |
            (uint256(1) << DSL.BITS_DEX_V2_VARIABLES2_FEE_VERSION) | // Setting fee version to 1
            (maxDecayTime_ << DSL.BITS_DEX_V2_VARIABLES2_MAX_DECAY_TIME) |
            (priceImpactToFeeDivisionFactor_ << DSL.BITS_DEX_V2_VARIABLES2_PRICE_IMPACT_TO_FEE_DIVISION_FACTOR) |
            (minFee_ << DSL.BITS_DEX_V2_VARIABLES2_MIN_FEE) |
            (maxFee_ << DSL.BITS_DEX_V2_VARIABLES2_MAX_FEE) |
            ((block.timestamp & X15) << DSL.BITS_DEX_V2_VARIABLES2_LAST_UPDATE_TIMESTAMP); // Setting last update timestamp to current timestamp (We only store the least significant 15 bits of the timestamp)

        emit LogUpdateFeeVersion1(dexType_, dexId_, maxDecayTime_, priceImpactToFeeDivisionFactor_, minFee_, maxFee_);

        PL.unlock(dexId_);
    }
}
