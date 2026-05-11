// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./helpers.sol";

abstract contract CommonAdminModuleInternals is CommonHelpers {
    function _updateProtocolFee(DexKey memory dexKey_, bool swap0To1_, uint256 protocolFee_, uint256 dexType_) internal {
        bytes32 dexId_ = _getValidDex(dexKey_, dexType_);

        if (protocolFee_ > X12) {
            revert FluidDexV2D3D4Error(ErrorTypes.AdminModule__ProtocolFeeInvalid);
        }

        if (swap0To1_) _dexVariables2[dexType_][dexId_] = _dexVariables2[dexType_][dexId_] & ~(X12 << DSL.BITS_DEX_V2_VARIABLES2_PROTOCOL_FEE_0_TO_1) |
            (protocolFee_ << DSL.BITS_DEX_V2_VARIABLES2_PROTOCOL_FEE_0_TO_1);
        else _dexVariables2[dexType_][dexId_] = _dexVariables2[dexType_][dexId_] & ~(X12 << DSL.BITS_DEX_V2_VARIABLES2_PROTOCOL_FEE_1_TO_0) |
            (protocolFee_ << DSL.BITS_DEX_V2_VARIABLES2_PROTOCOL_FEE_1_TO_0);

        emit LogUpdateProtocolFee(dexType_, dexId_, protocolFee_);
    }

    function _updateProtocolCutFee(DexKey memory dexKey_, uint256 protocolCutFee_, uint256 dexType_) internal {
        bytes32 dexId_ = _getValidDex(dexKey_, dexType_);

        /// @dev Auth passes protocolCutFee_ in 6 decimals, and we convert it to an integer (1 = 1% cut) here

        // Human input error. should send 0 for wanting 0, not 0 because of precision reduction.
        if (protocolCutFee_ != 0 && protocolCutFee_ < FOUR_DECIMALS) {
            revert FluidDexV2D3D4Error(ErrorTypes.AdminModule__ProtocolCutFeeTooLow);
        }

        protocolCutFee_ = protocolCutFee_ / FOUR_DECIMALS;

        if (protocolCutFee_ > X6) {
            revert FluidDexV2D3D4Error(ErrorTypes.AdminModule__ProtocolCutFeeInvalid);
        }

        _dexVariables2[dexType_][dexId_] = _dexVariables2[dexType_][dexId_] & ~(X6 << DSL.BITS_DEX_V2_VARIABLES2_PROTOCOL_CUT_FEE) |
            (protocolCutFee_ << DSL.BITS_DEX_V2_VARIABLES2_PROTOCOL_CUT_FEE);

        emit LogUpdateProtocolCutFee(dexType_, dexId_, protocolCutFee_);
    }

    function _stopPerPoolAccounting(DexKey memory dexKey_, uint256 dexType_) internal {
        bytes32 dexId_ = _getValidDex(dexKey_, dexType_);

        delete _tokenReserves[dexType_][dexId_];
        _dexVariables2[dexType_][dexId_] |= X1 << DSL.BITS_DEX_V2_VARIABLES2_POOL_ACCOUNTING_FLAG;

        emit LogStopPerPoolAccounting(dexType_, dexId_);
    }

    function _updateUserWhitelist(address user_, bool isWhitelisted_, uint256 dexType_) internal {
        _whitelistedUsers[dexType_][user_] = isWhitelisted_ ? 1 : 0;

        emit LogUpdateUserWhitelist(dexType_, user_, isWhitelisted_);
    }
}
