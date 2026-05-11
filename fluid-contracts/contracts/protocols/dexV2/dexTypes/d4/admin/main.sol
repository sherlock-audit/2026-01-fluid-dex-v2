// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../other/commonImport.sol";

/// @title ImplementationEssentials
/// @dev Base contract providing DEX type identification for D4 (smart debt)
abstract contract ImplementationEssentials is CommonImportD4Other {

    uint256 internal constant DEX_TYPE_WITH_VERSION = 40_000;
    
    /// @notice Returns the DEX type and Liquidity address for deployment validation
    /// @return DEX type (4 for D4) and Liquidity contract address
    function getDexTypeAndLiquidityAddr() external view returns (uint256, address) {
        return (DEX_TYPE_WITH_VERSION / DEX_TYPE_DIVISOR, address(LIQUIDITY));
    }
}

/// @title FluidDexV2D4AdminModule
/// @notice Admin module for D4 (smart debt) DEX pools
/// @dev Handles protocol fees, user whitelisting, and pool accounting configuration
contract FluidDexV2D4AdminModule is ImplementationEssentials {
    /// @notice Initializes the D4 Admin Module
    /// @param liquidityAddress_ The FluidLiquidity contract address
    constructor(address liquidityAddress_) {
        THIS_CONTRACT = address(this);
        LIQUIDITY = IFluidLiquidity(liquidityAddress_);
    }

    /// @notice Updates the protocol fee for a specific swap direction in a pool
    /// @param dexKey_ The DexKey identifying the pool
    /// @param swap0To1_ True for token0->token1 swaps, false for token1->token0
    /// @param protocolFee_ The new protocol fee (in basis points)
    function updateProtocolFee(DexKey calldata dexKey_, bool swap0To1_, uint256 protocolFee_) external _onlyDelegateCall {
        _updateProtocolFee(dexKey_, swap0To1_, protocolFee_, DEX_TYPE_WITH_VERSION / DEX_TYPE_DIVISOR);
    }

    /// @notice Updates the protocol cut fee for a pool
    /// @param dexKey_ The DexKey identifying the pool
    /// @param protocolCutFee_ The new protocol cut fee percentage
    function updateProtocolCutFee(DexKey calldata dexKey_, uint256 protocolCutFee_) external _onlyDelegateCall {
        _updateProtocolCutFee(dexKey_, protocolCutFee_, DEX_TYPE_WITH_VERSION / DEX_TYPE_DIVISOR);
    }
    
    /// @notice Updates whitelist status for a user
    /// @param user_ The user address to update
    /// @param isWhitelisted_ True to whitelist, false to remove from whitelist
    function updateUserWhitelist(address user_, bool isWhitelisted_) external _onlyDelegateCall {
        _updateUserWhitelist(user_, isWhitelisted_, DEX_TYPE_WITH_VERSION / DEX_TYPE_DIVISOR);
    }

    /// @notice Stops per-pool accounting for a specific pool
    /// @param dexKey_ The DexKey identifying the pool
    function stopPerPoolAccounting(DexKey calldata dexKey_) external _onlyDelegateCall {
        _stopPerPoolAccounting(dexKey_, DEX_TYPE_WITH_VERSION / DEX_TYPE_DIVISOR);
    }
}
