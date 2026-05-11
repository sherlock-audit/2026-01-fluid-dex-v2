// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./structs.sol";

import { SqrtPriceMath as SPM } from "@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol";

abstract contract Helpers is CommonImport {
    function _feeSettle(address token_, uint256 feeAccrued_, uint256 feeCollection_, address to_) internal {
        int256 supplyAmount_ = -int256(feeAccrued_);
        int256 storeAmount_ = int256(feeAccrued_) - int256(feeCollection_);
        if (!(supplyAmount_ == 0 && storeAmount_ == 0)) {
            DEX_V2.settle(token_, supplyAmount_, 0, storeAmount_, to_, IS_CALLBACK);
        }
    }

    function _withdrawSettle(address token_, uint256 amount_, uint256 feeAccrued_, address to_) internal {
        if (!(amount_ == 0 && feeAccrued_ == 0)) {
            DEX_V2.settle(token_, -int256(amount_ + feeAccrued_), 0, int256(feeAccrued_), to_, IS_CALLBACK);
        }
    }

    function _borrowSettle(address token_, uint256 amount_, uint256 feeAccrued_, address to_) internal {
        if (!(amount_ == 0 && feeAccrued_ == 0)) {
            DEX_V2.settle(token_, -int256(feeAccrued_), int256(amount_), int256(feeAccrued_), to_, IS_CALLBACK);
        }
    }

    function _depositSettle(address token_, uint256 amount_, uint256 feeAccrued_, address to_) internal {
        if (!(amount_ == 0 && feeAccrued_ == 0)) {
            uint256 ethValue_;
            if (token_ == NATIVE_TOKEN) {
                ethValue_ = amount_;
                _msgValue -= ethValue_;
            }
            DEX_V2.settle{value: ethValue_}(token_, int256(amount_) - int256(feeAccrued_), 0, int256(feeAccrued_), to_, IS_CALLBACK);
        }
    }

    function _paybackSettle(address token_, uint256 amount_, uint256 feeAccrued_, address to_) internal {
        if (!(amount_ == 0 && feeAccrued_ == 0)) {
            uint256 ethValue_;
            if (token_ == NATIVE_TOKEN) { 
                ethValue_ = amount_; 
                _msgValue -= ethValue_; 
            }
            DEX_V2.settle{value: ethValue_}(token_, -int256(feeAccrued_), -int256(amount_), int256(feeAccrued_), to_, IS_CALLBACK);
        }
    }

    function _updateFeeStoredWithNewFeeAccrued(
        uint256 nftId_, 
        bytes32 positionId_, 
        bytes32 dexV2PositionId_, 
        uint256 feeAccruedToken0_, 
        uint256 feeAccruedToken1_
    ) internal {
        uint256 positionFeeStored_ = _positionFeeStored[nftId_][positionId_][dexV2PositionId_];
        uint256 feeStoredToken0_ = ((positionFeeStored_ >> MSL.BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_0) & X128) + feeAccruedToken0_;
        uint256 feeStoredToken1_ = ((positionFeeStored_ >> MSL.BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_1) & X128) + feeAccruedToken1_;

        if (feeStoredToken0_ > X128 || feeStoredToken1_ > X128) revert();

        _positionFeeStored[nftId_][positionId_][dexV2PositionId_] = (feeStoredToken0_ << MSL.BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_0) | 
            (feeStoredToken1_ << MSL.BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_1);
    }

    /// @dev Updates fee stored and returns the final fee collection amounts after handling max value and verification
    function _updateAndCollectFees(FeeCollectionParams memory p_) internal returns (uint256, uint256) {
        uint256 positionFeeStored_ = _positionFeeStored[p_.nftId][p_.positionId][p_.dexV2PositionId];
        uint256 feeStoredToken0_ = (positionFeeStored_ >> MSL.BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_0) & X128;
        uint256 feeStoredToken1_ = (positionFeeStored_ >> MSL.BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_1) & X128;

        if (p_.feeCollectionAmount0 == type(uint256).max) p_.feeCollectionAmount0 = feeStoredToken0_ + p_.feeAccruedToken0;
        if (p_.feeCollectionAmount1 == type(uint256).max) p_.feeCollectionAmount1 = feeStoredToken1_ + p_.feeAccruedToken1;

        if (p_.isOperate) {
            if (p_.feeCollectionAmount0 > 0) _verifyAmountLimits(p_.feeCollectionAmount0);
            if (p_.feeCollectionAmount1 > 0) _verifyAmountLimits(p_.feeCollectionAmount1);
        }

        feeStoredToken0_ = feeStoredToken0_ + p_.feeAccruedToken0 - p_.feeCollectionAmount0;
        feeStoredToken1_ = feeStoredToken1_ + p_.feeAccruedToken1 - p_.feeCollectionAmount1;
        
        if (feeStoredToken0_ > X128 || feeStoredToken1_ > X128) revert();

        _positionFeeStored[p_.nftId][p_.positionId][p_.dexV2PositionId] = (feeStoredToken0_ << MSL.BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_0) | 
            (feeStoredToken1_ << MSL.BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_1);

        return (p_.feeCollectionAmount0, p_.feeCollectionAmount1);
    }

    /// @dev Handles D3 position deletion including isolated collateral check
    function _handleD3PositionDeletion(StartOperationParams memory s_) internal {
        if ((s_.nftConfig >> MSL.BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_FLAG) & X1 == 1) {
            if ((s_.nftConfig >> MSL.BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_TOKEN_INDEX) & X12 == s_.token0Index) {
                s_.nftConfig = _afterIsolatedCollateralFullWithdraw(s_.nftId, s_.nftConfig, s_.token0Index, s_.positionIndex);
            } else if ((s_.nftConfig >> MSL.BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_TOKEN_INDEX) & X12 == s_.token1Index) {
                s_.nftConfig = _afterIsolatedCollateralFullWithdraw(s_.nftId, s_.nftConfig, s_.token1Index, s_.positionIndex);
            }
        }
        _deletePosition(s_.nftId, s_.nftConfig, s_.positionIndex);
    }

    function _checkAndUpdateCapsForD3D4LiquidityIncrease(
        bytes32 positionId_,
        uint256 dexType_,
        DexKey memory dexKey_,
        int24 tickLower_, 
        int24 tickUpper_, 
        uint256 liquidityIncrease_, 
        bool permissionlessTokens_
    ) internal {
        uint256 positionCapConfigs_ = _positionCapConfigs[positionId_];

        if (positionCapConfigs_ == 0) {
            if (permissionlessTokens_) {
                // This means that this is a permissionless dex and liquidity is getting added for the first time to this dex
                // Hence we need to set the cap configs for this dex

                uint256 permissionlessDexCapConfigs_ = _defaultPermissionlessDexCapConfigs[dexType_][dexKey_.token0][dexKey_.token1];
                if (permissionlessDexCapConfigs_ == 0) {
                    permissionlessDexCapConfigs_ = _globalDefaultPermissionlessDexCapConfigs[dexType_];
                    if (permissionlessDexCapConfigs_ == 0) {
                        revert();
                    }
                }

                positionCapConfigs_ = permissionlessDexCapConfigs_;
            } else {
                // This dex is neither whitelisted nor permissionless
                revert();
            }
        }

        {
            int256 minTick_ = int256((positionCapConfigs_ >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_ABSOLUTE_MIN_TICK) & X19);
            if ((positionCapConfigs_ >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MIN_TICK_SIGN) & X1 == 0) minTick_ = -minTick_;
            int256 maxTick_ = int256((positionCapConfigs_ >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_ABSOLUTE_MAX_TICK) & X19);
            if ((positionCapConfigs_ >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_TICK_SIGN) & X1 == 0) maxTick_ = -maxTick_;

            if (tickLower_ < minTick_ || tickUpper_ > maxTick_) revert();
        }

        uint160 sqrtPriceX96Lower_ = TM.getSqrtRatioAtTick(tickLower_);
        uint160 sqrtPriceX96Upper_ = TM.getSqrtRatioAtTick(tickUpper_);

        uint256 currentMaxRawAdjustedAmount0_ = (positionCapConfigs_ >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_0) & X64;
        currentMaxRawAdjustedAmount0_ = BM.fromBigNumber(currentMaxRawAdjustedAmount0_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
        currentMaxRawAdjustedAmount0_ += SPM.getAmount0Delta(
            uint160(sqrtPriceX96Lower_), 
            uint160(sqrtPriceX96Upper_), 
            uint128(liquidityIncrease_), 
            ROUND_UP
        );

        uint256 currentMaxRawAdjustedAmount1_ = (positionCapConfigs_ >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_1) & X64;
        currentMaxRawAdjustedAmount1_ = BM.fromBigNumber(currentMaxRawAdjustedAmount1_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
        currentMaxRawAdjustedAmount1_ += SPM.getAmount1Delta(
            uint160(sqrtPriceX96Lower_), 
            uint160(sqrtPriceX96Upper_), 
            uint128(liquidityIncrease_), 
            ROUND_UP
        );

        {
            uint256 maxRawAdjustedAmount0Cap_ = (positionCapConfigs_ >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_RAW_ADJUSTED_AMOUNT_0_CAP) & X18;
            maxRawAdjustedAmount0Cap_ = BM.fromBigNumber(maxRawAdjustedAmount0Cap_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

            uint256 maxRawAdjustedAmount1Cap_ = (positionCapConfigs_ >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_RAW_ADJUSTED_AMOUNT_1_CAP) & X18;
            maxRawAdjustedAmount1Cap_ = BM.fromBigNumber(maxRawAdjustedAmount1Cap_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

            if ((currentMaxRawAdjustedAmount0_ > maxRawAdjustedAmount0Cap_) || (currentMaxRawAdjustedAmount1_ > maxRawAdjustedAmount1Cap_)) revert();
        }

        positionCapConfigs_ = positionCapConfigs_ & ~(X64 << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_0) | 
            (
                BM.toBigNumber(currentMaxRawAdjustedAmount0_, DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_UP) // Rounding up here because its for caps
                << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_0
            );

        _positionCapConfigs[positionId_] = positionCapConfigs_ & ~(X64 << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_1) | 
            (
                BM.toBigNumber(currentMaxRawAdjustedAmount1_, DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_UP) // Rounding up here because its for caps
                << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_1
            );
    }

    function _updatePositionCapsForD3D4LiquidityDecrease(bytes32 positionId_, int24 tickLower_, int24 tickUpper_, uint256 liquidityDecrease_) internal {
        // Since this is withdraw/payback we can skip the checks and just update the current total liquidity in the _positionCapConfigs mapping
        uint256 positionCapConfigs_ = _positionCapConfigs[positionId_];

        uint160 sqrtPriceX96Lower_ = TM.getSqrtRatioAtTick(tickLower_);
        uint160 sqrtPriceX96Upper_ = TM.getSqrtRatioAtTick(tickUpper_);

        uint256 currentMaxRawAdjustedAmount0_ = (positionCapConfigs_ >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_0) & X64;
        currentMaxRawAdjustedAmount0_ = BM.fromBigNumber(currentMaxRawAdjustedAmount0_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
        currentMaxRawAdjustedAmount0_ -= SPM.getAmount0Delta(
            uint160(sqrtPriceX96Lower_), 
            uint160(sqrtPriceX96Upper_), 
            uint128(liquidityDecrease_), 
            ROUND_DOWN
        );

        uint256 currentMaxRawAdjustedAmount1_ = (positionCapConfigs_ >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_1) & X64;
        currentMaxRawAdjustedAmount1_ = BM.fromBigNumber(currentMaxRawAdjustedAmount1_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
        currentMaxRawAdjustedAmount1_ -= SPM.getAmount1Delta(
            uint160(sqrtPriceX96Lower_), 
            uint160(sqrtPriceX96Upper_), 
            uint128(liquidityDecrease_), 
            ROUND_DOWN
        );

        positionCapConfigs_ = positionCapConfigs_ & ~(X64 << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_0) | 
            (
                BM.toBigNumber(currentMaxRawAdjustedAmount0_, DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_UP) // Rounding up here because its for caps
                << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_0
            );

        _positionCapConfigs[positionId_] = positionCapConfigs_ & ~(X64 << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_1) | 
            (
                BM.toBigNumber(currentMaxRawAdjustedAmount1_, DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_UP) // Rounding up here because its for caps
                    << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_1
            );
    }
}