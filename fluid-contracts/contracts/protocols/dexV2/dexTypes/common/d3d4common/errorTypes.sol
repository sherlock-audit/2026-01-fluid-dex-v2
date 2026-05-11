// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./events.sol";

library ErrorTypes {
    /***********************************|
    |        User Module Errors         | 
    |__________________________________*/

    /// @notice thrown when dex is not initialized
    uint256 internal constant UserModule__DexNotInitialized = 210001;

    /// @notice thrown when amounts are less than minimum
    uint256 internal constant UserModule__AmountsLessThanMinimum = 210002;

    /// @notice thrown when user is not whitelisted
    uint256 internal constant UserModule__UserNotWhitelisted = 210003;

    /// @notice thrown when tick range is invalid
    uint256 internal constant UserModule__InvalidTickRange = 210004;

    /// @notice thrown when liquidity exceeds max liquidity per tick
    uint256 internal constant UserModule__MaxLiquidityPerTickExceeded = 210005;

    /// @notice thrown when active liquidity exceeds max liquidity
    uint256 internal constant UserModule__ActiveLiquidityOverflow = 210006;

    /// @notice thrown when liquidity decrease exceeds active liquidity
    uint256 internal constant UserModule__LiquidityDecreaseExceedsActive = 210007;

    /// @notice thrown when tick spacing is invalid
    uint256 internal constant UserModule__InvalidTickSpacing = 210008;

    /// @notice thrown when token0 is greater than or equal to token1
    uint256 internal constant UserModule__InvalidTokenOrder = 210009;

    /// @notice thrown when sqrt price is out of bounds
    uint256 internal constant UserModule__SqrtPriceOutOfBounds = 210010;

    /// @notice thrown when dex is already initialized
    uint256 internal constant UserModule__DexAlreadyInitialized = 210011;
    
    /// @notice thrown when token decimals is invalid
    uint256 internal constant UserModule__InvalidTokenDecimals = 210012;

    /// @notice thrown when token reserves overflow
    uint256 internal constant UserModule__TokenReservesOverflow = 210013;

    /// @notice thrown when amount rounds to zero after conversion
    uint256 internal constant UserModule__AmountRoundsToZero = 210014;

    /***********************************|
    |        Swap Module Errors         | 
    |__________________________________*/

    /// @notice thrown when dex is not initialized
    uint256 internal constant SwapModule__DexNotInitialized = 211001;

    /// @notice thrown when amount out is less than minimum
    uint256 internal constant SwapModule__AmountOutLessThanMin = 211002;

    /// @notice thrown when amount in exceeds maximum
    uint256 internal constant SwapModule__AmountInMoreThanMax = 211003;

    /// @notice thrown when next tick is out of bounds
    uint256 internal constant SwapModule__NextTickOutOfBounds = 211004;

    /// @notice thrown when step amount out exceeds maximum
    uint256 internal constant SwapModule__StepAmountOutOverflow = 211005;

    /// @notice thrown when step amount in exceeds maximum
    uint256 internal constant SwapModule__StepAmountInOverflow = 211006;

    /// @notice thrown when active liquidity becomes negative
    uint256 internal constant SwapModule__ActiveLiquidityUnderflow = 211007;

    /// @notice thrown when price impact exceeds 100%
    uint256 internal constant SwapModule__PriceImpactTooHigh = 211008;

    /// @notice thrown when dex variables don't change during swap
    uint256 internal constant SwapModule__NoStateChange = 211009;

    /// @notice thrown when token reserves overflow
    uint256 internal constant SwapModule__TokenReservesOverflow = 211010;

    /// @notice thrown when sqrt price deviation due to rounding exceeds 0.01%
    uint256 internal constant SwapModule__SqrtPriceDeviationTooHigh = 211011;

    /***********************************|
    |         Helper Errors             | 
    |__________________________________*/

    /// @notice thrown when dex is not initialized
    uint256 internal constant Helpers__DexNotInitialized = 212001;

    /// @notice thrown when caller is not the controller
    uint256 internal constant Helpers__Unauthorized = 212002;

    /// @notice thrown when power is invalid (not in 0-9 range)
    uint256 internal constant Helpers__InvalidPower = 212003;

    /// @notice thrown when amount is out of allowed limits
    uint256 internal constant Helpers__AmountOutOfLimits = 212004;

    /// @notice thrown when adjusted amount is out of allowed limits
    uint256 internal constant Helpers__AdjustedAmountOutOfLimits = 212005;

    /// @notice thrown when sqrt price change percentage is out of bounds
    uint256 internal constant Helpers__SqrtPriceChangeOutOfBounds = 212006;

    /// @notice thrown when liquidity is out of allowed limits
    uint256 internal constant Helpers__LiquidityOutOfLimits = 212007;

    /// @notice thrown when liquidity change is too low or too high
    uint256 internal constant Helpers__LiquidityChangeInvalid = 212008;

    /// @notice thrown when amount out exceeds maximum allowed
    uint256 internal constant Helpers__AmountOutOverflow = 212009;

    /// @notice thrown when amount in exceeds maximum allowed
    uint256 internal constant Helpers__AmountInOverflow = 212010;

    /// @notice thrown when LP fee exceeds maximum
    uint256 internal constant Helpers__LpFeeInvalid = 212011;

    /// @notice thrown when function is not called via delegatecall
    uint256 internal constant Helpers__OnlyDelegateCallAllowed = 212012;

    /// @notice thrown when reserve and debt ratio exceeds allowed limits
    uint256 internal constant Helpers__ReserveDebtRatioExceeded = 212013;

    /// @notice thrown when exchange price from liquidity layer is zero/invalid
    uint256 internal constant Helpers__InvalidExchangePrice = 212014;

    /***********************************|
    |      Admin Module Errors          | 
    |__________________________________*/

    /// @notice thrown when protocol fee exceeds maximum
    uint256 internal constant AdminModule__ProtocolFeeInvalid = 213001;

    /// @notice thrown when protocol cut fee is below minimum non-zero value
    uint256 internal constant AdminModule__ProtocolCutFeeTooLow = 213002;

    /// @notice thrown when protocol cut fee exceeds maximum
    uint256 internal constant AdminModule__ProtocolCutFeeInvalid = 213003;

    /***********************************|
    |    Controller Module Errors       | 
    |__________________________________*/

    /// @notice thrown when trying to set dynamic fee on non-dynamic fee pool
    uint256 internal constant ControllerModule__NotDynamicFeePool = 214001;

    /// @notice thrown when LP fee exceeds maximum
    uint256 internal constant ControllerModule__LpFeeInvalid = 214002;

    /// @notice thrown when max decay time is invalid
    uint256 internal constant ControllerModule__MaxDecayTimeInvalid = 214003;

    /// @notice thrown when price impact to fee division factor is invalid
    uint256 internal constant ControllerModule__PriceImpactDivisionFactorInvalid = 214004;

    /// @notice thrown when min fee exceeds maximum fee
    uint256 internal constant ControllerModule__MinFeeInvalid = 214005;

    /// @notice thrown when max fee is invalid
    uint256 internal constant ControllerModule__MaxFeeInvalid = 214006;

    /// @notice thrown when min fee is greater than or equal to max fee
    uint256 internal constant ControllerModule__MinFeeGteMaxFee = 214007;

    /// @notice thrown when fee version is invalid
    uint256 internal constant ControllerModule__InvalidFeeVersion = 214008;
}
