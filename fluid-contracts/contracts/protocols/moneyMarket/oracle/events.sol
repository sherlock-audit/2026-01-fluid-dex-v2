// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

abstract contract Events {
    /// @notice Emitted when a new oracle config is set for a token/emode/actionType/collateralType.
    /// @param token The token address
    /// @param eMode The eMode identifier. Note eMode 0 is used as default fallback pricing.
    /// @param isOperate 0 = liquidate rates; 1 = operate rates; 2 = both liquidate and operate
    /// @param isCollateral 0 = debt rates; 1 = collateral rates; 2 = both debt and collateral
    /// @param sourceType1 The source type for the first price source
    /// @param source1 The address of the first price source
    /// @param multiplier1 The decimal multiplier for the first price source
    /// @param sourceType2 The source type for the second price source
    /// @param source2 The address of the second price source
    /// @param multiplier2 The decimal multiplier for the second price source
    /// @param sourceType3 The source type for the third price source
    /// @param source3 The address of the third price source
    /// @param multiplier3 The decimal multiplier for the third price source
    event OracleConfigSet(
        address token,
        uint256 eMode,
        uint8 isOperate,
        uint8 isCollateral,
        uint8 sourceType1,
        address source1,
        int8 multiplier1,
        uint8 sourceType2,
        address source2,
        int8 multiplier2,
        uint8 sourceType3,
        address source3,
        int8 multiplier3
    );

    /// @notice Emitted when an oracle config is removed for a token/emode/isOperate/isCollateral combination.
    /// @param token The token address
    /// @param eMode The eMode identifier
    /// @param isOperate 0 = liquidate, 1 = operate
    /// @param isCollateral 0 = debt, 1 = collateral
    event OracleConfigRemoved(address token, uint256 eMode, uint8 isOperate, uint8 isCollateral);
}
