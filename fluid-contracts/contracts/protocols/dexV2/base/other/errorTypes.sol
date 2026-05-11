// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./events.sol";

library ErrorTypes {
    /***********************************|
    |          Admin Module             | 
    |__________________________________*/

    /// @notice thrown when msg.sender is not auth or governance
    uint256 internal constant DexV2AdminModule__Unauthorized = 200001;

    /// @notice thrown when new implementation is not a contract
    uint256 internal constant DexV2AdminModule__NewImplementationNotAContract = 200002;

    /// @notice thrown when new implementation doesn't support proxiableUUID
    uint256 internal constant DexV2AdminModule__UnsupportedProxiableUUID = 200003;

    /// @notice thrown when new implementation is not UUPS compatible
    uint256 internal constant DexV2AdminModule__NotUUPSCompatible = 200004;

    /// @notice thrown when upgrade call to new implementation fails
    uint256 internal constant DexV2AdminModule__UpgradeCallFailed = 200005;

    /// @notice thrown when trying to set an implementation that is already set
    uint256 internal constant DexV2AdminModule__ImplementationAlreadySet = 200006;

    /// @notice thrown when implementation has different dex type than expected
    uint256 internal constant DexV2AdminModule__ImplementationDexTypeMismatch = 200007;

    /// @notice thrown when implementation has different liquidity address than expected
    uint256 internal constant DexV2AdminModule__ImplementationLiquidityMismatch = 200008;

    /// @notice thrown when msg.value is sent for non-native token operation
    uint256 internal constant DexV2AdminModule__MsgValueForNonNativeToken = 200009;

    /// @notice thrown when msg.value doesn't match the required amount
    uint256 internal constant DexV2AdminModule__MsgValueMismatch = 200010;

    /***********************************|
    |            Main Module            | 
    |__________________________________*/

    /// @notice thrown when invalid dex type or implementation ID is provided
    uint256 internal constant DexV2Main__InvalidDexTypeOrImplementationId = 201001;

    /// @notice thrown when all operate amounts (supply, borrow, store) are zero
    uint256 internal constant DexV2Main__OperateAmountsZero = 201002;

    /// @notice thrown when operate amount is out of int128 bounds
    uint256 internal constant DexV2Main__OperateAmountOutOfBounds = 201003;

    /// @notice thrown when msg.value is sent for non-native token operation
    uint256 internal constant DexV2Main__MsgValueForNonNativeToken = 201004;

    /// @notice thrown when msg.value doesn't match the required amount
    uint256 internal constant DexV2Main__MsgValueMismatch = 201005;

    /// @notice thrown when balance check after callback fails
    uint256 internal constant DexV2Main__BalanceCheckFailed = 201006;

    /// @notice thrown when admin implementation is not set
    uint256 internal constant DexV2Main__AdminImplementationNotSet = 201007;

    /// @notice thrown when liquidityCallback is not called by Liquidity contract
    uint256 internal constant DexV2Main__UnauthorizedLiquidityCallback = 201008;

    /// @notice thrown when dex identifier doesn't match expected value
    uint256 internal constant DexV2Main__InvalidDexIdentifier = 201009;

    /// @notice thrown when amount to send is less than required amount in callback
    uint256 internal constant DexV2Main__AmountToSendInsufficient = 201010;

    /// @notice thrown when native token tries to use callback instead of msg.value
    uint256 internal constant DexV2Main__NativeTokenRequiresMsgValue = 201011;

    /// @notice thrown when action identifier doesn't match any known action
    uint256 internal constant DexV2Main__InvalidActionIdentifier = 201012;

    /***********************************|
    |           Helpers Module          | 
    |__________________________________*/

    /// @notice thrown when operation is not active
    uint256 internal constant DexV2Helpers__OperationNotActive = 202001;

    /// @notice thrown when stored token amount becomes negative
    uint256 internal constant DexV2Helpers__StoredTokenAmountNegative = 202002;

    /// @notice thrown when msg.value doesn't match required amount for native token
    uint256 internal constant DexV2Helpers__MsgValueMismatch = 202003;

    /// @notice thrown when invalid parameters are provided
    uint256 internal constant DexV2Helpers__InvalidParams = 202004;
}
