// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../other/commonImport.sol";

/// @title FluidDexV2D4ControllerModule
/// @notice Controller module for D4 (smart debt) DEX pools
/// @dev Allows pool controllers to configure dynamic fees and fee parameters
contract FluidDexV2D4ControllerModule is CommonImportD4Other {
    uint256 internal constant DEX_TYPE_WITH_VERSION = 40_000;

    /// @notice Initializes the D4 Controller Module
    /// @param liquidityAddress_ The FluidLiquidity contract address
    constructor(address liquidityAddress_) {
        THIS_CONTRACT = address(this);
        LIQUIDITY = IFluidLiquidity(liquidityAddress_);
    }

    /// @notice Toggles whether the pool fetches dynamic fees
    /// @param dexKey_ The DexKey identifying the pool (must be called by dexKey_.controller)
    /// @param newFetchDynamicFeeFlag_ True to enable dynamic fee fetching, false to disable
    function updateFetchDynamicFeeFlag(DexKey calldata dexKey_, bool newFetchDynamicFeeFlag_) external _onlyDelegateCall _onlyController(dexKey_.controller) {
        _updateFetchDynamicFeeFlag(dexKey_, newFetchDynamicFeeFlag_, DEX_TYPE_WITH_VERSION / DEX_TYPE_DIVISOR);
    }

    /// @notice Updates the LP fee using fee version 0 (static fee)
    /// @param dexKey_ The DexKey identifying the pool (must be called by dexKey_.controller)
    /// @param lpFee_ The new LP fee
    function updateFeeVersion0(DexKey calldata dexKey_, uint256 lpFee_) external _onlyDelegateCall _onlyController(dexKey_.controller) {
        _updateFeeVersion0(dexKey_, lpFee_, DEX_TYPE_WITH_VERSION / DEX_TYPE_DIVISOR);
    }

    /// @notice Updates the fee parameters using fee version 1 (dynamic fee)
    /// @param dexKey_ The DexKey identifying the pool (must be called by dexKey_.controller)
    /// @param maxDecayTime_ Maximum time for fee decay
    /// @param priceImpactToFeeDivisionFactor_ Factor for price impact to fee conversion
    /// @param minFee_ Minimum fee
    /// @param maxFee_ Maximum fee
    function updateFeeVersion1(
        DexKey calldata dexKey_, 
        uint256 maxDecayTime_, 
        uint256 priceImpactToFeeDivisionFactor_, 
        uint256 minFee_, 
        uint256 maxFee_
    ) external _onlyDelegateCall _onlyController(dexKey_.controller) {
        _updateFeeVersion1(dexKey_, maxDecayTime_, priceImpactToFeeDivisionFactor_, minFee_, maxFee_, DEX_TYPE_WITH_VERSION / DEX_TYPE_DIVISOR);
    }
}
