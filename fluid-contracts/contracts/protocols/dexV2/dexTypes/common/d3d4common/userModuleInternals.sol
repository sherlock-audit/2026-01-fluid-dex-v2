// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { LiquidityCalcs as LC } from "../../../../../libraries/liquidityCalcs.sol";
import { LiquidityAmounts as LA } from "lib/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { TickMath as TM } from "lib/v3-core/contracts/libraries/TickMath.sol"; // This library uses different min tick, max tick, min sqrt price, max sqrt price than us. But this wont cause any issues for us hence we can use it

import "./controllerModuleInternals.sol";

abstract contract CommonUserModuleInternals is CommonControllerModuleInternals {
    function _addLiquidity(AddLiquidityInternalParams memory params_) internal 
        returns (uint256 amount0Raw_, uint256 amount1Raw_, uint256 feeAccruedToken0_, uint256 feeAccruedToken1_, uint256 liquidityIncreaseRaw_) {
        AddLiquidityInternalVariables memory v_;

        v_.positionId = keccak256(abi.encode(msg.sender, params_.tickLower, params_.tickUpper, params_.positionSalt));
        if (!((params_.tickLower < params_.tickUpper) &&
                (params_.tickUpper <= MAX_TICK) &&
                (params_.tickLower >= MIN_TICK) &&
                (params_.tickLower % int24(params_.dexKey.tickSpacing) == 0) &&
                (params_.tickUpper % int24(params_.dexKey.tickSpacing) == 0) &&
                (params_.tickUpper - params_.tickLower <= int24(MAX_TICK_RANGE)))
        ) {
            revert FluidDexV2D3D4Error(ErrorTypes.UserModule__InvalidTickRange);
        }

        // Calculate liquidity based on current price and range
        liquidityIncreaseRaw_ = LA.getLiquidityForAmounts(
            uint160(params_.dexVariables.sqrtPriceX96),
            uint160(params_.sqrtPriceLowerX96),
            uint160(params_.sqrtPriceUpperX96),
            params_.amount0DesiredRaw,
            params_.amount1DesiredRaw
        );

        if (params_.isSmartCollateral) {
            // We explicitly round down the liquidity for smart collateral so protocol is on the winning side
            liquidityIncreaseRaw_ = (liquidityIncreaseRaw_ * ROUNDING_FACTOR_MINUS_ONE) / ROUNDING_FACTOR;
            if (liquidityIncreaseRaw_ > 0) liquidityIncreaseRaw_ -= 1;
        } else {
            // We explicitly round up the liquidity for smart debt so protocol is on the winning side
            liquidityIncreaseRaw_ = ((liquidityIncreaseRaw_ * ROUNDING_FACTOR_PLUS_ONE) / ROUNDING_FACTOR) + 1;
        }

        _verifyLiquidityLimits(liquidityIncreaseRaw_);

        // Calculate the actual token amounts needed for the liquidity based on current price and range
        (amount0Raw_, amount1Raw_) = LA.getAmountsForLiquidity(
            uint160(params_.dexVariables.sqrtPriceX96),
            uint160(params_.sqrtPriceLowerX96),
            uint160(params_.sqrtPriceUpperX96),
            uint128(liquidityIncreaseRaw_)
        );

        v_.maxLiquidityPerTick = _getMaxLiquidityPerTick(params_.dexKey.tickSpacing);

        TickData memory tickDataLower_;
        {
            // Update TickData & TickData for lower tick
            uint256 tickLiquidityGrossLower_ = _tickLiquidityGross[params_.dexType][params_.dexId][params_.tickLower];
            tickDataLower_ = _tickData[params_.dexType][params_.dexId][params_.tickLower];

            if (tickLiquidityGrossLower_ == 0) {
                // Initialize feeGrowthOutside for new tick
                // When a tick is initialized, by convention, it is assumed that all the fee so far was generated below the tick // This doesn't affect fee calculation because we anyway use the difference between fee variables for fee calculation
                if (params_.tickLower <= params_.dexVariables.currentTick) {
                    tickDataLower_.feeGrowthOutside0X102 = params_.dexVariables.feeGrowthGlobal0X102;
                    tickDataLower_.feeGrowthOutside1X102 = params_.dexVariables.feeGrowthGlobal1X102;
                }

                // Initialize the tick in bitmap
                _setTickBitmap(params_.dexKey, params_.dexType, params_.dexId, params_.tickLower, true);
            }

            _verifyLiquidityChangeLimits(tickLiquidityGrossLower_, liquidityIncreaseRaw_);
            unchecked {
                tickLiquidityGrossLower_ += liquidityIncreaseRaw_;
            }
            if (tickLiquidityGrossLower_ > v_.maxLiquidityPerTick) {
                revert FluidDexV2D3D4Error(ErrorTypes.UserModule__MaxLiquidityPerTickExceeded);
            }
            _tickLiquidityGross[params_.dexType][params_.dexId][params_.tickLower] = tickLiquidityGrossLower_;
        }

        unchecked {
            // NOTE: Removed liquidity change checks for liquidity net because it can be very small because its difference 
            // _verifyLiquidityChangeLimits(tickDataLower_.liquidityNet < 0 ? 
            //     uint256(-tickDataLower_.liquidityNet) : uint256(tickDataLower_.liquidityNet), liquidityIncreaseRaw_);
            tickDataLower_.liquidityNet += int256(liquidityIncreaseRaw_); // For 0 to 1 swap, liquidity net is subtracted. Also, price is decreasing, hence when tick lower will be crossed, liquidity should decrease, hence we add because liquidity net is subtracted for 0 to 1 swap
        }
        _tickData[params_.dexType][params_.dexId][params_.tickLower] = tickDataLower_;

        TickData memory tickDataUpper_;
        {
            // Update TickData & TickData for upper tick
            uint256 tickLiquidityGrossUpper_ = _tickLiquidityGross[params_.dexType][params_.dexId][params_.tickUpper];
            tickDataUpper_ = _tickData[params_.dexType][params_.dexId][params_.tickUpper];

            if (tickLiquidityGrossUpper_ == 0) {
                // Initialize feeGrowthOutside for new tick
                // When a tick is initialized, by convention, it is assumed that all the fee so far was generated below the tick // This doesn't affect fee calculation because we anyway use the difference between fee variables for fee calculation
                if (params_.tickUpper <= params_.dexVariables.currentTick) {
                    tickDataUpper_.feeGrowthOutside0X102 = params_.dexVariables.feeGrowthGlobal0X102;
                    tickDataUpper_.feeGrowthOutside1X102 = params_.dexVariables.feeGrowthGlobal1X102;
                }

                // Initialize the tick in bitmap if not already initialized
                _setTickBitmap(params_.dexKey, params_.dexType, params_.dexId, params_.tickUpper, true);
            }

            _verifyLiquidityChangeLimits(tickLiquidityGrossUpper_, liquidityIncreaseRaw_);
            unchecked {
                tickLiquidityGrossUpper_ += liquidityIncreaseRaw_;
            }
            if (tickLiquidityGrossUpper_ > v_.maxLiquidityPerTick) {
                revert FluidDexV2D3D4Error(ErrorTypes.UserModule__MaxLiquidityPerTickExceeded);
            }
            _tickLiquidityGross[params_.dexType][params_.dexId][params_.tickUpper] = tickLiquidityGrossUpper_;
        }

        unchecked {
            // NOTE: Removed liquidity change checks for liquidity net because it can be very small because its difference 
            // _verifyLiquidityChangeLimits(tickDataUpper_.liquidityNet < 0 ? 
            //     uint256(-tickDataUpper_.liquidityNet) : uint256(tickDataUpper_.liquidityNet), liquidityIncreaseRaw_);
            tickDataUpper_.liquidityNet -= int256(liquidityIncreaseRaw_); // For 0 to 1 swap, liquidity net is subtracted. Also, price is decreasing, hence when tick upper will be crossed, liquidity should increase, hence we subtract because liquidity net is subtracted for 0 to 1 swap
        }
        _tickData[params_.dexType][params_.dexId][params_.tickUpper] = tickDataUpper_;

        // Calculate feeGrowthInside for both tokens

        // Calculate fee growth inside the range
        // For lower tick
        if (params_.tickLower <= params_.dexVariables.currentTick) {
            v_.feeGrowthBelow0X102 = tickDataLower_.feeGrowthOutside0X102;
            v_.feeGrowthBelow1X102 = tickDataLower_.feeGrowthOutside1X102;
        } else {
            unchecked {
                v_.feeGrowthBelow0X102 = params_.dexVariables.feeGrowthGlobal0X102 - tickDataLower_.feeGrowthOutside0X102;
                v_.feeGrowthBelow1X102 = params_.dexVariables.feeGrowthGlobal1X102 - tickDataLower_.feeGrowthOutside1X102;
            }
        }

        // For upper tick
        if (params_.dexVariables.currentTick < params_.tickUpper) {
            v_.feeGrowthAbove0X102 = tickDataUpper_.feeGrowthOutside0X102;
            v_.feeGrowthAbove1X102 = tickDataUpper_.feeGrowthOutside1X102;
        } else {
            unchecked {
                v_.feeGrowthAbove0X102 = params_.dexVariables.feeGrowthGlobal0X102 - tickDataUpper_.feeGrowthOutside0X102;
                v_.feeGrowthAbove1X102 = params_.dexVariables.feeGrowthGlobal1X102 - tickDataUpper_.feeGrowthOutside1X102;
            }
        }

        unchecked {
            v_.feeGrowthInside0X102 = params_.dexVariables.feeGrowthGlobal0X102 - v_.feeGrowthBelow0X102 - v_.feeGrowthAbove0X102;
            v_.feeGrowthInside1X102 = params_.dexVariables.feeGrowthGlobal1X102 - v_.feeGrowthBelow1X102 - v_.feeGrowthAbove1X102;
        }

        // Get current position info
        PositionData memory positionData_ = _positionData[params_.dexType][params_.dexId][v_.positionId];

        if (positionData_.liquidity > 0) {
            // Calculate fees accrued
            /// @dev fee is stored in adjusted token amounts per raw liquidity, hence no need to multiple by exchange prices
            unchecked {
                feeAccruedToken0_ = FM.mulDiv(v_.feeGrowthInside0X102 - positionData_.feeGrowthInside0X102, positionData_.liquidity, Q102);
                feeAccruedToken1_ = FM.mulDiv(v_.feeGrowthInside1X102 - positionData_.feeGrowthInside1X102, positionData_.liquidity, Q102);
            }
        }

        unchecked {
            positionData_.liquidity += liquidityIncreaseRaw_;
        }
        positionData_.feeGrowthInside0X102 = v_.feeGrowthInside0X102;
        positionData_.feeGrowthInside1X102 = v_.feeGrowthInside1X102;

        // Update position
        _positionData[params_.dexType][params_.dexId][v_.positionId] = positionData_;

        // Update active liquidity in dex variables 2 if needed
        if (params_.tickLower <= params_.dexVariables.currentTick && params_.tickUpper > params_.dexVariables.currentTick) {
            uint256 activeLiquidity_ = (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_ACTIVE_LIQUIDITY) & X102;
            // NOTE: Removed liquidity change checks for active liquidity because it can cause issues because liquidity gross at a tick and active liquidity can be far apart
            // _verifyLiquidityChangeLimits(activeLiquidity_, liquidityIncreaseRaw_);
            unchecked {
                activeLiquidity_ += liquidityIncreaseRaw_;
                // This will never happen because of max liquidity per tick check but still checking for extra security
                if (activeLiquidity_ > X102) {
                    revert FluidDexV2D3D4Error(ErrorTypes.UserModule__ActiveLiquidityOverflow);
                }
                _dexVariables2[params_.dexType][params_.dexId] = (params_.dexVariables2 & ~(X102 << DSL.BITS_DEX_V2_VARIABLES2_ACTIVE_LIQUIDITY)) | // Clearing out the bits we want to set
                    (activeLiquidity_ << DSL.BITS_DEX_V2_VARIABLES2_ACTIVE_LIQUIDITY);
            }
        }

        if (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_POOL_ACCOUNTING_FLAG & X1 == 0) {
            uint256 token0Reserves_;
            uint256 token1Reserves_; 
            {
                uint256 tokenReserves_ = _tokenReserves[params_.dexType][params_.dexId];

                token0Reserves_ = ((tokenReserves_ >> DSL.BITS_DEX_V2_TOKEN_RESERVES_TOKEN_0_RESERVES) & X128) + amount0Raw_;
                token1Reserves_ = ((tokenReserves_ >> DSL.BITS_DEX_V2_TOKEN_RESERVES_TOKEN_1_RESERVES) & X128) + amount1Raw_;
            }

            if (token0Reserves_ > X128 || token1Reserves_ > X128) {
                revert FluidDexV2D3D4Error(ErrorTypes.UserModule__TokenReservesOverflow);
            }

            _tokenReserves[params_.dexType][params_.dexId] = (token0Reserves_ << DSL.BITS_DEX_V2_TOKEN_RESERVES_TOKEN_0_RESERVES) | 
                (token1Reserves_ << DSL.BITS_DEX_V2_TOKEN_RESERVES_TOKEN_1_RESERVES);
        }
    }

    /// @dev Function to remove liquidity
    function _removeLiquidity(RemoveLiquidityInternalParams memory params_) internal 
        returns (uint256 amount0Raw_, uint256 amount1Raw_, uint256 feeAccruedToken0_, uint256 feeAccruedToken1_, uint256 liquidityDecreaseRaw_) {
        RemoveLiquidityInternalVariables memory v_;

        v_.positionId = keccak256(abi.encode(msg.sender, params_.tickLower, params_.tickUpper, params_.positionSalt));
        if (!((params_.tickLower < params_.tickUpper) &&
                (params_.tickUpper <= MAX_TICK) &&
                (params_.tickLower >= MIN_TICK) &&
                (params_.tickLower % int24(params_.dexKey.tickSpacing) == 0) &&
                (params_.tickUpper % int24(params_.dexKey.tickSpacing) == 0) &&
                (params_.tickUpper - params_.tickLower <= int24(MAX_TICK_RANGE)))
        ) {
            revert FluidDexV2D3D4Error(ErrorTypes.UserModule__InvalidTickRange);
        }

        // Calculate liquidity based on current price and range
        liquidityDecreaseRaw_ = LA.getLiquidityForAmounts(
            uint160(params_.dexVariables.sqrtPriceX96),
            uint160(params_.sqrtPriceLowerX96),
            uint160(params_.sqrtPriceUpperX96),
            params_.amount0DesiredRaw,
            params_.amount1DesiredRaw
        );
        // NOTE: Removing liquidity limit check from _removeLiquidity function because it can cause liquidations to get stuck
        // _verifyLiquidityLimits(liquidityDecreaseRaw_);

        // Get current position info and if liquidity to be burned is more than the position liquidity, then set liquidity to be burned to the position liquidity
        PositionData memory positionData_ = _positionData[params_.dexType][params_.dexId][v_.positionId];
        if (liquidityDecreaseRaw_ > positionData_.liquidity) liquidityDecreaseRaw_ = positionData_.liquidity;

        // Calculate the actual token amounts needed for the liquidity based on current price and range
        (amount0Raw_, amount1Raw_) = LA.getAmountsForLiquidity(
            uint160(params_.dexVariables.sqrtPriceX96),
            uint160(params_.sqrtPriceLowerX96),
            uint160(params_.sqrtPriceUpperX96),
            uint128(liquidityDecreaseRaw_)
        );

        TickData memory tickDataLower_;
        {
            // Update TickData & TickData for lower tick
            uint256 tickLiquidityGrossLower_ = _tickLiquidityGross[params_.dexType][params_.dexId][params_.tickLower];
            tickDataLower_ = _tickData[params_.dexType][params_.dexId][params_.tickLower];

            // NOTE: Removing liquidity change checks for _removeLiquidity function because it can cause liquidations to get stuck
            // _verifyLiquidityChangeLimits(tickLiquidityGrossLower_, liquidityDecreaseRaw_);
            unchecked {
                tickLiquidityGrossLower_ -= liquidityDecreaseRaw_;
            }

            if (tickLiquidityGrossLower_ == 0) {
                // Delete variables for gas refund
                delete _tickLiquidityGross[params_.dexType][params_.dexId][params_.tickLower];
                delete _tickData[params_.dexType][params_.dexId][params_.tickLower];

                // Uninitialize tick in bitmap
                _setTickBitmap(params_.dexKey, params_.dexType, params_.dexId, params_.tickLower, false);
            } else {
                unchecked {
                    // NOTE: Removed liquidity change checks for liquidity net because it can be very small because its difference 
                    // _verifyLiquidityChangeLimits(tickDataLower_.liquidityNet < 0 ? 
                    //     uint256(-tickDataLower_.liquidityNet) : uint256(tickDataLower_.liquidityNet), liquidityDecreaseRaw_);
                    tickDataLower_.liquidityNet -= int256(liquidityDecreaseRaw_); // For 0 to 1 swap, liquidity net is subtracted. Also, price is decreasing, hence when tick lower will be crossed, liquidity should decrease less, hence we subtract because liquidity net is subtracted for 0 to 1 swap
                }

                // Set tick data and tick data 2
                _tickLiquidityGross[params_.dexType][params_.dexId][params_.tickLower] = tickLiquidityGrossLower_;
                _tickData[params_.dexType][params_.dexId][params_.tickLower] = tickDataLower_;
            }
        }

        TickData memory tickDataUpper_;
        {
            // Update TickData & TickData for upper tick
            uint256 tickLiquidityGrossUpper_ = _tickLiquidityGross[params_.dexType][params_.dexId][params_.tickUpper];
            tickDataUpper_ = _tickData[params_.dexType][params_.dexId][params_.tickUpper];

            // NOTE: Removing liquidity change checks for _removeLiquidity function because it can cause liquidations to get stuck
            // _verifyLiquidityChangeLimits(tickLiquidityGrossUpper_, liquidityDecreaseRaw_);
            unchecked {
                tickLiquidityGrossUpper_ -= liquidityDecreaseRaw_;
            }

            if (tickLiquidityGrossUpper_ == 0) {
                // Delete variables for gas refund
                delete _tickLiquidityGross[params_.dexType][params_.dexId][params_.tickUpper];
                delete _tickData[params_.dexType][params_.dexId][params_.tickUpper];

                // Uninitialize tick in bitmap
                _setTickBitmap(params_.dexKey, params_.dexType, params_.dexId, params_.tickUpper, false);
            } else {
                unchecked {
                    // NOTE: Removed liquidity change checks for liquidity net because it can be very small because its difference 
                    // _verifyLiquidityChangeLimits(tickDataUpper_.liquidityNet < 0 ? 
                    //     uint256(-tickDataUpper_.liquidityNet) : uint256(tickDataUpper_.liquidityNet), liquidityDecreaseRaw_);
                    tickDataUpper_.liquidityNet += int256(liquidityDecreaseRaw_); // For 0 to 1 swap, liquidity net is subtracted. Also, price is decreasing, hence when tick upper will be crossed, liquidity should decrease more, hence we add because liquidity net is subtracted for 0 to 1 swap
                }

                // Set tick data and tick data 2
                _tickLiquidityGross[params_.dexType][params_.dexId][params_.tickUpper] = tickLiquidityGrossUpper_;
                _tickData[params_.dexType][params_.dexId][params_.tickUpper] = tickDataUpper_;
            }
        }

        // Calculate feeGrowthInside for both tokens
        // Calculate fee growth inside the range

        // For lower tick
        if (params_.tickLower <= params_.dexVariables.currentTick) {
            v_.feeGrowthBelow0X102 = tickDataLower_.feeGrowthOutside0X102;
            v_.feeGrowthBelow1X102 = tickDataLower_.feeGrowthOutside1X102;
        } else {
            unchecked {
                v_.feeGrowthBelow0X102 = params_.dexVariables.feeGrowthGlobal0X102 - tickDataLower_.feeGrowthOutside0X102;
                v_.feeGrowthBelow1X102 = params_.dexVariables.feeGrowthGlobal1X102 - tickDataLower_.feeGrowthOutside1X102;
            }
        }

        // For upper tick
        if (params_.dexVariables.currentTick < params_.tickUpper) {
            v_.feeGrowthAbove0X102 = tickDataUpper_.feeGrowthOutside0X102;
            v_.feeGrowthAbove1X102 = tickDataUpper_.feeGrowthOutside1X102;
        } else {
            unchecked {
                v_.feeGrowthAbove0X102 = params_.dexVariables.feeGrowthGlobal0X102 - tickDataUpper_.feeGrowthOutside0X102;
                v_.feeGrowthAbove1X102 = params_.dexVariables.feeGrowthGlobal1X102 - tickDataUpper_.feeGrowthOutside1X102;
            }
        }

        unchecked {
            v_.feeGrowthInside0X102 = params_.dexVariables.feeGrowthGlobal0X102 - v_.feeGrowthBelow0X102 - v_.feeGrowthAbove0X102;
            v_.feeGrowthInside1X102 = params_.dexVariables.feeGrowthGlobal1X102 - v_.feeGrowthBelow1X102 - v_.feeGrowthAbove1X102;
        }

        // Calculate fees accrued
        /// @dev fee is stored in adjusted token amounts per raw liquidity, hence no need to multiple by exchange prices
        unchecked {
            feeAccruedToken0_ = FM.mulDiv(v_.feeGrowthInside0X102 - positionData_.feeGrowthInside0X102, positionData_.liquidity, Q102);
            feeAccruedToken1_ = FM.mulDiv(v_.feeGrowthInside1X102 - positionData_.feeGrowthInside1X102, positionData_.liquidity, Q102);

            positionData_.liquidity -= liquidityDecreaseRaw_;
        }

        if (positionData_.liquidity > 0) {
            positionData_.feeGrowthInside0X102 = v_.feeGrowthInside0X102;
            positionData_.feeGrowthInside1X102 = v_.feeGrowthInside1X102;

            // Update position
            _positionData[params_.dexType][params_.dexId][v_.positionId] = positionData_;
        } else {
            // Position is fully closed, hence we delete the position data
            delete _positionData[params_.dexType][params_.dexId][v_.positionId];
        }

        // Update active liquidity in dex variables 2 if needed
        if (params_.tickLower <= params_.dexVariables.currentTick && params_.tickUpper > params_.dexVariables.currentTick) {
            uint256 activeLiquidity_ = (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_ACTIVE_LIQUIDITY) & X102;
            // NOTE: Removed liquidity change checks for active liquidity because it can cause issues because liquidity gross at a tick and active liquidity can be far apart
            // _verifyLiquidityChangeLimits(activeLiquidity_, liquidityDecreaseRaw_);

            unchecked {
                // This will never happen because active liquidity is made up of all the liquidity of all users combined, but still checking for extra security
                if (liquidityDecreaseRaw_ > activeLiquidity_) {
                    revert FluidDexV2D3D4Error(ErrorTypes.UserModule__LiquidityDecreaseExceedsActive);
                }
                activeLiquidity_ -= liquidityDecreaseRaw_;
                _dexVariables2[params_.dexType][params_.dexId] = (params_.dexVariables2 & ~(X102 << DSL.BITS_DEX_V2_VARIABLES2_ACTIVE_LIQUIDITY)) | // Clearing out the bits we want to set
                    (activeLiquidity_ << DSL.BITS_DEX_V2_VARIABLES2_ACTIVE_LIQUIDITY);
            }
        }

        if (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_POOL_ACCOUNTING_FLAG & X1 == 0) {
            uint256 token0Reserves_;
            uint256 token1Reserves_;

            {
                uint256 tokenReserves_ = _tokenReserves[params_.dexType][params_.dexId];   

                token0Reserves_ = ((tokenReserves_ >> DSL.BITS_DEX_V2_TOKEN_RESERVES_TOKEN_0_RESERVES) & X128) - amount0Raw_;
                token1Reserves_ = ((tokenReserves_ >> DSL.BITS_DEX_V2_TOKEN_RESERVES_TOKEN_1_RESERVES) & X128) - amount1Raw_;
            }

            _tokenReserves[params_.dexType][params_.dexId] = 
                (token0Reserves_ << DSL.BITS_DEX_V2_TOKEN_RESERVES_TOKEN_0_RESERVES) | 
                (token1Reserves_ << DSL.BITS_DEX_V2_TOKEN_RESERVES_TOKEN_1_RESERVES);
        }
    }

    function _initialize(InitializeInternalParams memory params_) internal {
        InitializeVariables memory v_;

        if (params_.dexKey.tickSpacing > MAX_TICK_SPACING || params_.dexKey.tickSpacing < MIN_TICK_SPACING) {
            revert FluidDexV2D3D4Error(ErrorTypes.UserModule__InvalidTickSpacing);
        }
        if (params_.dexKey.token0 >= params_.dexKey.token1) {
            revert FluidDexV2D3D4Error(ErrorTypes.UserModule__InvalidTokenOrder);
        }

        v_.lpFee = _validateLPFee(params_.dexKey.fee);

        // We need to do the check here for sqrt price because the library we are using uses different min and max sqrt price than us
        if (params_.sqrtPriceX96 > MAX_SQRT_PRICE_X96 || params_.sqrtPriceX96 < MIN_SQRT_PRICE_X96) {
            revert FluidDexV2D3D4Error(ErrorTypes.UserModule__SqrtPriceOutOfBounds);
        }
        v_.tick = TM.getTickAtSqrtRatio(uint160(params_.sqrtPriceX96));

        v_.dexId = keccak256(abi.encode(params_.dexKey));

        if (_dexVariables[params_.dexType][v_.dexId] != 0) {
            revert FluidDexV2D3D4Error(ErrorTypes.UserModule__DexAlreadyInitialized);
        }
        unchecked {
            _dexVariables[params_.dexType][v_.dexId] = (uint256(v_.tick < 0 ? 0 : 1) << DSL.BITS_DEX_V2_VARIABLES_CURRENT_TICK_SIGN) |
                (uint256(v_.tick < 0 ? -int256(v_.tick) : int256(v_.tick)) << DSL.BITS_DEX_V2_VARIABLES_ABSOLUTE_CURRENT_TICK) |
                (BM.toBigNumber(params_.sqrtPriceX96, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << DSL.BITS_DEX_V2_VARIABLES_CURRENT_SQRT_PRICE);
        }

        if (params_.dexKey.token0 == NATIVE_TOKEN) v_.token0Decimals = NATIVE_TOKEN_DECIMALS;
        else v_.token0Decimals = IERC20WithDecimals(params_.dexKey.token0).decimals();

        if (params_.dexKey.token1 == NATIVE_TOKEN) v_.token1Decimals = NATIVE_TOKEN_DECIMALS;
        else v_.token1Decimals = IERC20WithDecimals(params_.dexKey.token1).decimals();

        if (v_.token0Decimals < MIN_TOKEN_DECIMALS || v_.token0Decimals > MAX_TOKEN_DECIMALS) revert FluidDexV2D3D4Error(ErrorTypes.UserModule__InvalidTokenDecimals);
        if (v_.token1Decimals < MIN_TOKEN_DECIMALS || v_.token1Decimals > MAX_TOKEN_DECIMALS) revert FluidDexV2D3D4Error(ErrorTypes.UserModule__InvalidTokenDecimals);

        if (v_.token0Decimals == 15 || v_.token0Decimals == 16 || v_.token0Decimals == 17) revert FluidDexV2D3D4Error(ErrorTypes.UserModule__InvalidTokenDecimals);
        if (v_.token1Decimals == 15 || v_.token1Decimals == 16 || v_.token1Decimals == 17) revert FluidDexV2D3D4Error(ErrorTypes.UserModule__InvalidTokenDecimals);

        if (v_.token0Decimals == 18) v_.token0Decimals = 15;
        if (v_.token1Decimals == 18) v_.token1Decimals = 15;

        _dexVariables2[params_.dexType][v_.dexId] = 
            (v_.token0Decimals << DSL.BITS_DEX_V2_VARIABLES2_TOKEN_0_DECIMALS) |
            (v_.token1Decimals << DSL.BITS_DEX_V2_VARIABLES2_TOKEN_1_DECIMALS) |
            (v_.lpFee << DSL.BITS_DEX_V2_VARIABLES2_LP_FEE);

        _dexKey[params_.dexType][v_.dexId] = params_.dexKey;

        emit LogInitialize(params_.dexType, v_.dexId, params_.dexKey, params_.sqrtPriceX96);
    }
}