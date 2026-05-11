// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BigMathMinified as BM } from "../../../../libraries/bigMathMinified.sol";
import { LiquidityCalcs as LC } from "../../../../libraries/liquidityCalcs.sol";
import { DexV2D3D4CommonSlotsLink as DSL } from "../../../../libraries/dexV2D3D4CommonSlotsLink.sol";
import { FullMath as FM } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import { FixedPointMathLib as FPM } from "solmate/src/utils/FixedPointMathLib.sol";
import { LiquidityAmounts as LA } from "lib/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { TickMath as TM } from "lib/v3-core/contracts/libraries/TickMath.sol";
import { MoneyMarketSlotsLink as MSL } from "../../../../libraries/moneyMarketSlotsLink.sol";
import { LiquiditySlotsLink as LSL } from "../../../../libraries/liquiditySlotsLink.sol";
import { SafeTransfer } from "../../../../libraries/safeTransfer.sol";

import "./variables.sol";

abstract contract CommonHelpers is Variables {
    function _getGovernanceAddr() internal view returns (address governance_) {
        governance_ = address(uint160(LIQUIDITY.readFromStorage(LIQUIDITY_GOVERNANCE_SLOT)));
    }
    
    function _verifyAmountLimits(uint256 amount_) internal pure {
        if (amount_ < FOUR_DECIMALS || amount_ > X128) revert();
    }

    function _verifyAmountLimits(int256 amount_) internal pure {
        if (amount_ > 0) {
            if (amount_ < int256(FOUR_DECIMALS) || amount_ > int256(X128)) revert();
        } else {
            if (amount_ > -int256(FOUR_DECIMALS) || amount_ < -int256(X128)) revert();
        }
    }

    function _getTokenConfigs(uint256 emode_, uint256 tokenIndex_) internal view returns (uint256 tokenConfigs_) {
        if (emode_ == NO_EMODE) {
            tokenConfigs_ = _tokenConfigs[NO_EMODE][tokenIndex_];
        } else {
            if ((_emodeMap[emode_][(tokenIndex_ - 1) / 128] >> (((tokenIndex_ - 1) % 128) * 2)) & X1 == 0) tokenConfigs_ = _tokenConfigs[NO_EMODE][tokenIndex_]; // the configs for this token dont change for this emode
            else tokenConfigs_ = _tokenConfigs[emode_][tokenIndex_]; // the configs for this token change for this emode
        }
    }

    function _validateDebtForEmode(uint256 emode_, uint256 tokenIndex_) internal view {
        // If its no emode then all debts are allowed, hence no need to check anything
        if (emode_ != NO_EMODE) {
            if ((_emodeMap[emode_][(tokenIndex_ - 1) / 128] >> ((((tokenIndex_ - 1) % 128) * 2) + 1)) & X1 == 0) revert(); // Debt not allowed for this emode 
        }
    }

    function _deletePosition(uint256 nftId_, uint256 nftConfig_, uint256 positionIndex_) internal {
        uint256 numberOfPositions_ = (nftConfig_ >> MSL.BITS_NFT_CONFIGS_NUMBER_OF_POSITIONS) & X10;
        if (positionIndex_ == 0 || positionIndex_ > numberOfPositions_) revert(); // Invalid position index

        if (positionIndex_ == numberOfPositions_) {
            // If the position to be deleted is the last position, then we can just delete it
            delete _positionData[nftId_][positionIndex_];
        } else {
            // If the position to be deleted is not the last position, then we need move the last position to the position index to be deleted, and delete the last position
            _positionData[nftId_][positionIndex_] = _positionData[nftId_][numberOfPositions_];
            delete _positionData[nftId_][numberOfPositions_];
        }

        // Update the number of positions in the nft config
        _nftConfigs[nftId_] =
            (nftConfig_ & ~(X10 << MSL.BITS_NFT_CONFIGS_NUMBER_OF_POSITIONS)) |
            ((numberOfPositions_ - 1) << MSL.BITS_NFT_CONFIGS_NUMBER_OF_POSITIONS);
    }

    function _decodeD3D4PositionData(
        uint256 positionData_, 
        uint256 token0Configs_, 
        uint256 token1Configs_
    ) internal pure returns (DexKey memory dexKey_, int24 tickLower_, int24 tickUpper_) {
        dexKey_.token0 = address(uint160(token0Configs_));
        dexKey_.token1 = address(uint160(token1Configs_));
        if (dexKey_.token0 == address(0) || dexKey_.token1 == address(0)) revert(); // Invalid token address

        if ((positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_IS_DYNAMIC_FEE_POOL) & X1 == 1) dexKey_.fee = DYNAMIC_FEE_FLAG;
        else dexKey_.fee = uint24((positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_FEE) & X17);

        dexKey_.tickSpacing = uint24((positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TICK_SPACING) & X9);
        dexKey_.controller = address(uint160((positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_CONTROLLER_ADDRESS) & X160));

        // Position Data
        tickLower_ = int24(uint24((positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_ABSOLUTE_LOWER_TICK) & X19));
        if ((positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_LOWER_TICK_SIGN) & X1 == 0) tickLower_ = -tickLower_;

        tickUpper_ = int24(uint24((positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_ABSOLUTE_UPPER_TICK) & X19));
        if ((positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_UPPER_TICK_SIGN) & X1 == 0) tickUpper_ = -tickUpper_;
    }

    function _updateStorageForWithdraw(
        uint256 nftId_,
        uint256 nftConfig_,
        uint256 positionIndex_,
        uint256 positionData_,
        uint256 tokenIndex_,
        uint256 tokenRawSupply_,
        uint256 withdrawAmountRaw_
    ) internal returns (bool positionDeleted_) {
        if (tokenRawSupply_ < withdrawAmountRaw_) revert(); // Withdraw exceeds supply

        // Now we need to update the withdraw amount in the _positionCapConfigs mapping
        // NOTE: No need of checking maxTotalTokenRawAmount_ like we did in supply because this is withdraw, withdrawals are allowed even if supply is above caps
        bytes32 positionId_ = keccak256(abi.encode(NORMAL_SUPPLY_POSITION_TYPE, tokenIndex_));
        uint256 positionCapConfigs_ = _positionCapConfigs[positionId_];
        
        uint256 totalTokenRawAmount_ = (positionCapConfigs_ >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_TOTAL_TOKEN_RAW_AMOUNT) & X64;
        totalTokenRawAmount_ = BM.fromBigNumber(totalTokenRawAmount_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

        totalTokenRawAmount_ -= withdrawAmountRaw_;

        totalTokenRawAmount_ = BM.toBigNumber(totalTokenRawAmount_, DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_UP); // Rounding up here so caps dont get violated because of any precision loss
        _positionCapConfigs[positionId_] = positionCapConfigs_ & ~(X64 << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_TOTAL_TOKEN_RAW_AMOUNT) | 
            (totalTokenRawAmount_ << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_TOTAL_TOKEN_RAW_AMOUNT);

        // Update the withdraw in position data
        unchecked {
            tokenRawSupply_ = tokenRawSupply_ - withdrawAmountRaw_;
        }
        tokenRawSupply_ = BM.toBigNumber(tokenRawSupply_, DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN); // Rounding down user supply so protocol is not at a loss
        // NOTE: We are checking if it became zero after doing toBigNumber so basically after removing least significant precision
        if (tokenRawSupply_ == 0) {
            // If this was an isolated token, then we need to update the _isolatedCapConfigs mapping and nft config

            if ((
                (nftConfig_ >> MSL.BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_FLAG) & X1 == 1) && 
                ((nftConfig_ >> MSL.BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_TOKEN_INDEX) & X12 == tokenIndex_)
                ) {
                nftConfig_ = _afterIsolatedCollateralFullWithdraw(nftId_, nftConfig_, tokenIndex_, positionIndex_);
            }
            // Remove the position from storage
            _deletePosition(nftId_, nftConfig_, positionIndex_);
            positionDeleted_ = POSITION_DELETED;
        } else {
            _positionData[nftId_][positionIndex_] =
                (positionData_ & ~(X64 << MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT)) |
                (tokenRawSupply_ << MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT);
            
            positionDeleted_ = POSITION_NOT_DELETED;
        }
    }

    function _updateStorageForPayback(
        uint256 nftId_, 
        uint256 nftConfig_, 
        uint256 positionIndex_,
        uint256 positionData_,
        uint256 tokenIndex_,
        uint256 tokenRawBorrow_, 
        uint256 paybackAmountRaw_
    ) internal returns (bool positionDeleted_){
        if (tokenRawBorrow_ < paybackAmountRaw_) revert(); // Payback exceeds borrow

        uint256 totalTokenRawBorrow_;
        // If isolated collateral flag is ON, then we need to update the payback in the _isolatedCapConfigs mapping
        if ((nftConfig_ >> MSL.BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_FLAG) & X1 == 1) {
            uint256 isolatedTokenIndex_ = (nftConfig_ >> MSL.BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_TOKEN_INDEX) & X12;
            uint256 isolatedCapConfigs_ = _isolatedCapConfigs[isolatedTokenIndex_][tokenIndex_];
            totalTokenRawBorrow_ = (isolatedCapConfigs_ >> MSL.BITS_ISOLATED_CAP_CONFIGS_TOTAL_TOKEN_RAW_BORROW) & X64;
            totalTokenRawBorrow_ = BM.fromBigNumber(totalTokenRawBorrow_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

            totalTokenRawBorrow_ -= paybackAmountRaw_;

            // We dont need to check the cap because this is payback
            // if (totalTokenRawBorrow_ > maxTotalTokenRawBorrow_) revert();

            totalTokenRawBorrow_ = BM.toBigNumber(totalTokenRawBorrow_, DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_UP); // Rounding up here so caps dont get violated because of any precision loss
            _isolatedCapConfigs[isolatedTokenIndex_][tokenIndex_] = isolatedCapConfigs_ & ~(X64 << MSL.BITS_ISOLATED_CAP_CONFIGS_TOTAL_TOKEN_RAW_BORROW) | 
                (totalTokenRawBorrow_ << MSL.BITS_ISOLATED_CAP_CONFIGS_TOTAL_TOKEN_RAW_BORROW);
        }

        // Now we need to update the pay back amount in the _positionCapConfigs mapping
        bytes32 positionId_ = keccak256(abi.encode(NORMAL_BORROW_POSITION_TYPE, tokenIndex_));
        uint256 positionCapConfigs_ = _positionCapConfigs[positionId_];
        totalTokenRawBorrow_ = (positionCapConfigs_ >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_TOTAL_TOKEN_RAW_AMOUNT) & X64;
        totalTokenRawBorrow_ =  BM.fromBigNumber(totalTokenRawBorrow_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

        totalTokenRawBorrow_ -= paybackAmountRaw_;

        totalTokenRawBorrow_ = BM.toBigNumber(totalTokenRawBorrow_, DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_UP); // Rounding up here so caps dont get violated because of any precision loss
        _positionCapConfigs[positionId_] = positionCapConfigs_ & ~(X64 << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_TOTAL_TOKEN_RAW_AMOUNT) | 
            (totalTokenRawBorrow_ << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_TOTAL_TOKEN_RAW_AMOUNT);

        // Now we need to update the payback in position data
        unchecked {
            tokenRawBorrow_ -= paybackAmountRaw_;
        }
        tokenRawBorrow_ = BM.toBigNumber(tokenRawBorrow_, DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_UP); // Rounding up user borrow amount to avoid protocol loss
        if (tokenRawBorrow_ == 0) {
            // Remove the position from storage
            _deletePosition(nftId_, nftConfig_, positionIndex_);
            positionDeleted_ = POSITION_DELETED;
        } else {
            _positionData[nftId_][positionIndex_] =
                (positionData_ & ~(X64 << MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT)) |
                (tokenRawBorrow_ << MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT);
            
            positionDeleted_ = POSITION_NOT_DELETED;
        }
    }

    function _getDexId(DexKey memory dexKey_) internal pure returns (bytes32) {
        return keccak256(abi.encode(dexKey_));
    }

    function _getDexV2PositionData(
        uint256 dexType_,
        bytes32 dexId_,
        int24 tickLower_,
        int24 tickUpper_,
        bytes32 positionSalt_
    ) internal view returns (PositionData memory) {
        bytes32 positionId_ = keccak256(abi.encode(address(this), tickLower_, tickUpper_, positionSalt_));
        bytes32 baseSlot_ = DSL.calculateTripleMappingStorageSlot(DSL.DEX_V2_POSITION_DATA_MAPPING_SLOT, bytes32(dexType_), dexId_, positionId_);
        
        // Read the struct fields from consecutive storage slots
        return PositionData({
            liquidity: uint256(DEX_V2.readFromStorage(baseSlot_)),
            feeGrowthInside0X102: uint256(DEX_V2.readFromStorage(bytes32(uint256(baseSlot_) + 1))),
            feeGrowthInside1X102: uint256(DEX_V2.readFromStorage(bytes32(uint256(baseSlot_) + 2)))
        });
    }

    function _isD3D4PositionEmpty(
        uint256 nftId_,
        uint256 positionType_,
        DexKey memory dexKey_,
        int24 tickLower_, 
        int24 tickUpper_,
        bytes32 positionSalt_
    ) internal view returns (bool) {
        uint256 dexType_;
        if (positionType_ == D3_POSITION_TYPE) {
            dexType_ = D3_DEX_TYPE;
        } else if (positionType_ == D4_POSITION_TYPE) {
            dexType_ = D4_DEX_TYPE;
        } else {
            revert(); // Invalid position type
        }

        bytes32 dexId_ = _getDexId(dexKey_);
        bytes32 positionId_ = keccak256(abi.encode(dexType_, dexKey_));

        bytes32 dexV2PositionId_ = keccak256(abi.encode(address(this), tickLower_, tickUpper_, positionSalt_));
        bytes32 baseSlot_ = DSL.calculateTripleMappingStorageSlot(DSL.DEX_V2_POSITION_DATA_MAPPING_SLOT, bytes32(dexType_), dexId_, dexV2PositionId_);

        uint256 dexV2PositionLiquidity_ = uint256(DEX_V2.readFromStorage(baseSlot_));
        uint256 positionFeeStored_ = _positionFeeStored[nftId_][positionId_][dexV2PositionId_];

        return dexV2PositionLiquidity_ == 0 && positionFeeStored_ == 0;
    }

    function _afterIsolatedCollateralFullWithdraw(uint256 nftId_, uint256 nftConfig_, uint256 tokenIndex_, uint256 positionIndexToSkip_) internal returns (uint256) {
        // If the isolated collateral is being fully withdrawn, then we need to:
        // 1. Check if this collateral is still part of any of positions of this nft by iterating through all positions, if it is then we dont need to do anything
        // 2. If it is not, then we need to iterate through all the positions again and look for positions of type 2 and remove the debt amounts from the _isolatedCapConfigs mapping and update the nft config

        uint256 numberOfPositions_ = (nftConfig_ >> MSL.BITS_NFT_CONFIGS_NUMBER_OF_POSITIONS) & X10;
        for (uint256 i_ = 1; i_ <= numberOfPositions_; i_++) {
            if (i_ == positionIndexToSkip_) continue; // Skipping here because this position will get deleted
            uint256 stepPositionData_ = _positionData[nftId_][i_];
            uint256 stepPositionType_ = (stepPositionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE) & X5;
            if (stepPositionType_ == NORMAL_SUPPLY_POSITION_TYPE) {
                // if position type is 1, we need to check if the step token index is same as tokenIndex_, if it is we need to return nftConfig_
                if (((stepPositionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_INDEX) & X12) == tokenIndex_) return nftConfig_;
            } else if (stepPositionType_ == D3_POSITION_TYPE) {
                // if position type is 3, we need to check if the step token index of both token 0 and token 1 and if any of them is same as tokenIndex_, if it is we need to return nftConfig_
                if (
                    ((stepPositionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_0_INDEX) & X12) == tokenIndex_ || 
                    ((stepPositionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_1_INDEX) & X12) == tokenIndex_
                    ) return nftConfig_;
            }
        }

        // If the function is still active then that means none of the positions have the isolated collateral hence we need to iterate through all the positions again and look for positions of type 2 and remove the debt amounts from the _isolatedCapConfigs mapping and update the nft config
        for (uint256 i_ = 1; i_ <= numberOfPositions_; i_++) {
            if (i_ == positionIndexToSkip_) continue; // Skipping here as we know that this is a collateral position
            uint256 stepPositionData_ = _positionData[nftId_][i_];
            if ((stepPositionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE) & X5 == NORMAL_BORROW_POSITION_TYPE) {
                // if position type is 2, we need to remove the debt amount from the _isolatedCapConfigs mapping and update the nft config
                uint256 tokenRawBorrow_ = (stepPositionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT) & X64;
                tokenRawBorrow_ = BM.fromBigNumber(tokenRawBorrow_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

                uint256 stepTokenIndex_ = (stepPositionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_INDEX) & X12;

                uint256 isolatedCapConfigs_ = _isolatedCapConfigs[tokenIndex_][stepTokenIndex_];

                uint256 totalTokenRawBorrow_ = (isolatedCapConfigs_ >> MSL.BITS_ISOLATED_CAP_CONFIGS_TOTAL_TOKEN_RAW_BORROW) & X64;
                totalTokenRawBorrow_ = BM.fromBigNumber(totalTokenRawBorrow_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

                totalTokenRawBorrow_ -= tokenRawBorrow_;

                // NOTE: This check is not needed because we are decreasing totalTokenRawBorrow_
                // if (totalTokenRawBorrow_ > maxTotalTokenRawBorrow_) revert();

                totalTokenRawBorrow_ = BM.toBigNumber(totalTokenRawBorrow_, DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_UP); // Rounding up here so caps dont get violated because of any precision loss
                _isolatedCapConfigs[tokenIndex_][stepTokenIndex_] = isolatedCapConfigs_ & ~(X64 << MSL.BITS_ISOLATED_CAP_CONFIGS_TOTAL_TOKEN_RAW_BORROW) | 
                    (totalTokenRawBorrow_ << MSL.BITS_ISOLATED_CAP_CONFIGS_TOTAL_TOKEN_RAW_BORROW);
            }
        }

        // Remove the isolated collateral flag and isolated collateral index
        // NOTE: Not updating the nftConfig on storage here because the _deletePosition function will update it on storage
        return nftConfig_ & ~(X13 << MSL.BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_FLAG);
    }

    function _getExchangePrices(address token_) internal view returns (uint256 supplyExchangePrice_, uint256 borrowExchangePrice_) {
        (supplyExchangePrice_, borrowExchangePrice_) = LC.calcExchangePrices(
            LIQUIDITY.readFromStorage(LSL.calculateMappingStorageSlot(LSL.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT, token_))
        );
    }

    function _tenPow(uint256 power_) internal pure returns (uint256) {
        // keeping the most used powers at the top for better gas optimization

        // Used for amount calc (convert token to 1e9 decimals)
        if (power_ == 3) {
            return 1_000; // used for 6 or 12 decimals (USDC, USDT)
        }
        if (power_ == 9) {
            return 1_000_000_000; // used for 18 decimals (ETH, and many more)
        }
        if (power_ == 1) {
            return 10; // used for 1 decimals (WBTC and more)
        }

        // Used for price calc (convert token to 1e18 decimals)
        if (power_ == 12) {
            return 1_000_000_000_000; // used for 6 decimals (USDC, USDT)
        }
        if (power_ == 10) {
            return 10_000_000_000; // used for 8 decimals (WBTC and more)
        }

        if (power_ == 0) {
            return 1;
        }
        if (power_ == 2) {
            return 100;
        }
        if (power_ == 4) {
            return 10_000;
        }
        if (power_ == 5) {
            return 100_000;
        }
        if (power_ == 6) {
            return 1_000_000;
        }
        if (power_ == 7) {
            return 10_000_000;
        }
        if (power_ == 8) {
            return 100_000_000;
        }
        if (power_ == 11) {
            return 100_000_000_000;
        }

        // We will only need powers from 0 to 12 as token decimals can only be 6 to 18
        revert(); // Invalid power
    }

    function _calculateNumeratorAndDenominatorPrecisions(uint256 decimals_) internal pure returns (uint256 numerator_, uint256 denominator_) {
        unchecked {
            if (decimals_ > TOKENS_DECIMALS_PRECISION) {
                numerator_ = 1;
                denominator_ = _tenPow(decimals_ - TOKENS_DECIMALS_PRECISION);
            } else {
                numerator_ = _tenPow(TOKENS_DECIMALS_PRECISION - decimals_);
                denominator_ = 1;
            }
        }
    }

    function _getDexV2DexVariables(
        uint256 dexType_, 
        bytes32 dexId_
    ) internal view returns (uint256 dexVariables_) {
        dexVariables_ = uint256(DEX_V2.readFromStorage(
            DSL.calculateDoubleMappingStorageSlot(DSL.DEX_V2_VARIABLES_SLOT, bytes32(dexType_), dexId_)
        ));
    }

    function _getDexV2TickFeeGrowthOutside(
        uint256 dexType_,
        bytes32 dexId_,
        int24 tick_
    ) internal view returns (uint256, uint256) {
        bytes32 baseSlot_ = DSL.calculateTripleMappingStorageSlot(DSL.DEX_V2_TICK_DATA_MAPPING_SLOT, bytes32(dexType_), dexId_, bytes32(uint256(int256(tick_))));
        
        // Read the struct fields from consecutive storage slots
        return (uint256(DEX_V2.readFromStorage(bytes32(uint256(baseSlot_) + 1))), uint256(DEX_V2.readFromStorage(bytes32(uint256(baseSlot_) + 2))));
    }

    function _getDexV2FeeAccruedAmounts(
        uint256 dexType_, 
        bytes32 dexId_,
        int24 tickLower_,
        int24 tickUpper_,
        uint256 dexVariables_,
        PositionData memory positionData_
    ) internal view returns (uint256 feeAccruedToken0_, uint256 feeAccruedToken1_) {
        if (positionData_.liquidity == 0) return (0, 0); // Fee must have been collected already if liquidity is zero

        GetDexV2FeeAccruedAmountsVariables memory v_;

        v_.feeGrowthGlobal0X102 = (dexVariables_ >> DSL.BITS_DEX_V2_VARIABLES_FEE_GROWTH_GLOBAL_0_X102) & X82;
        v_.feeGrowthGlobal0X102 = BM.fromBigNumber(v_.feeGrowthGlobal0X102, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
        v_.feeGrowthGlobal1X102 = (dexVariables_ >> DSL.BITS_DEX_V2_VARIABLES_FEE_GROWTH_GLOBAL_1_X102) & X82;
        v_.feeGrowthGlobal1X102 = BM.fromBigNumber(v_.feeGrowthGlobal1X102, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

        {
            (uint256 feeGrowthOutside0X102Lower_, uint256 feeGrowthOutside1X102Lower_) = _getDexV2TickFeeGrowthOutside(dexType_, dexId_, tickLower_);
            (uint256 feeGrowthOutside0X102Upper_, uint256 feeGrowthOutside1X102Upper_) = _getDexV2TickFeeGrowthOutside(dexType_, dexId_, tickUpper_);

            int256 currentTick_ = int256((dexVariables_ >> DSL.BITS_DEX_V2_VARIABLES_ABSOLUTE_CURRENT_TICK) & X19);
            if ((dexVariables_ >> DSL.BITS_DEX_V2_VARIABLES_CURRENT_TICK_SIGN) & X1 == 0) currentTick_ = -currentTick_;

            if (tickLower_ <= currentTick_) {
                v_.feeGrowthBelow0X102 = feeGrowthOutside0X102Lower_;
                v_.feeGrowthBelow1X102 = feeGrowthOutside1X102Lower_;
            } else {
                unchecked {
                    v_.feeGrowthBelow0X102 = v_.feeGrowthGlobal0X102 - feeGrowthOutside0X102Lower_;
                    v_.feeGrowthBelow1X102 = v_.feeGrowthGlobal1X102 - feeGrowthOutside1X102Lower_;
                }
            }

            if (currentTick_ < tickUpper_) {
                v_.feeGrowthAbove0X102 = feeGrowthOutside0X102Upper_;
                v_.feeGrowthAbove1X102 = feeGrowthOutside1X102Upper_;
            } else {
                unchecked {
                    v_.feeGrowthAbove0X102 = v_.feeGrowthGlobal0X102 - feeGrowthOutside0X102Upper_;
                    v_.feeGrowthAbove1X102 = v_.feeGrowthGlobal1X102 - feeGrowthOutside1X102Upper_;
                }
            }
        }

        uint256 feeGrowthInside0X102_;
        uint256 feeGrowthInside1X102_;
        unchecked {
            feeGrowthInside0X102_ = v_.feeGrowthGlobal0X102 - v_.feeGrowthBelow0X102 - v_.feeGrowthAbove0X102;
            feeGrowthInside1X102_ = v_.feeGrowthGlobal1X102 - v_.feeGrowthBelow1X102 - v_.feeGrowthAbove1X102;
        }

        // Calculate fees accrued
        /// @dev fee is stored in adjusted token amounts per raw liquidity, hence no need to multiple by exchange prices
        unchecked {
            feeAccruedToken0_ = FM.mulDiv(feeGrowthInside0X102_ - positionData_.feeGrowthInside0X102, positionData_.liquidity, Q102);
            feeAccruedToken1_ = FM.mulDiv(feeGrowthInside1X102_ - positionData_.feeGrowthInside1X102, positionData_.liquidity, Q102);
        }
    }

    function _getD3SupplyAmounts(
        bytes32 dexId_,
        GetD3D4AmountsParams memory params_
    ) internal view returns (uint256 token0SupplyAmount_, uint256 token1SupplyAmount_, uint256 feeAccruedToken0_, uint256 feeAccruedToken1_) {
        PositionData memory positionData_;
        {
            uint256 dexVariables_ = _getDexV2DexVariables(D3_DEX_TYPE, dexId_);
            positionData_ = _getDexV2PositionData(D3_DEX_TYPE, dexId_, params_.tickLower, params_.tickUpper, params_.positionSalt);
            if (positionData_.liquidity == 0) return (0, 0, 0, 0); // No supply and no fees

            if (params_.sqrtPriceX96 == AT_POOL_PRICE) {
                params_.sqrtPriceX96 = (dexVariables_ >> DSL.BITS_DEX_V2_VARIABLES_CURRENT_SQRT_PRICE) & X72;
                params_.sqrtPriceX96 = BM.fromBigNumber(params_.sqrtPriceX96, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
            }

            (feeAccruedToken0_, feeAccruedToken1_) = _getDexV2FeeAccruedAmounts(
                D3_DEX_TYPE, 
                dexId_, 
                params_.tickLower, 
                params_.tickUpper, 
                dexVariables_, 
                positionData_
            );
        }

        // NOTE: These are raw adjusted amounts
        (token0SupplyAmount_, token1SupplyAmount_) = LA.getAmountsForLiquidity(
            uint160(params_.sqrtPriceX96),
            TM.getSqrtRatioAtTick(params_.tickLower),
            TM.getSqrtRatioAtTick(params_.tickUpper),
            uint128(positionData_.liquidity)
        );

        (uint256 token0NumeratorPrecision_, uint256 token0DenominatorPrecision_) = _calculateNumeratorAndDenominatorPrecisions(params_.token0Decimals);
        (uint256 token1NumeratorPrecision_, uint256 token1DenominatorPrecision_) = _calculateNumeratorAndDenominatorPrecisions(params_.token1Decimals);

        // Convert raw adjusted amounts to normal amounts
        // Also explicitly rounding down to match DEX v2 rounding
        token0SupplyAmount_ = (token0SupplyAmount_ * token0DenominatorPrecision_ * params_.token0ExchangePrice * ROUNDING_FACTOR_MINUS_ONE) / 
            (token0NumeratorPrecision_ * LC.EXCHANGE_PRICES_PRECISION * ROUNDING_FACTOR);
        if (token0SupplyAmount_ > 0) {
            token0SupplyAmount_ -= 1;
        }

        token1SupplyAmount_ = (token1SupplyAmount_ * token1DenominatorPrecision_ * params_.token1ExchangePrice * ROUNDING_FACTOR_MINUS_ONE) / 
            (token1NumeratorPrecision_ * LC.EXCHANGE_PRICES_PRECISION * ROUNDING_FACTOR);
        if (token1SupplyAmount_ > 0) {
            token1SupplyAmount_ -= 1;
        }

        // Convert adjusted fee amounts to normal amounts
        // Also explicitly rounding down to match DEX v2 rounding
        feeAccruedToken0_ = (feeAccruedToken0_ * token0DenominatorPrecision_ * ROUNDING_FACTOR_MINUS_ONE) / (token0NumeratorPrecision_ * ROUNDING_FACTOR);
        if (feeAccruedToken0_ > 0) {
            feeAccruedToken0_ -= 1;
        }

        feeAccruedToken1_ = (feeAccruedToken1_ * token1DenominatorPrecision_ * ROUNDING_FACTOR_MINUS_ONE) / (token1NumeratorPrecision_ * ROUNDING_FACTOR);
        if (feeAccruedToken1_ > 0) {
            feeAccruedToken1_ -= 1;
        }
    }

    // BELOW 2 FUNCTION ARE COPIED AS IT IS FROM DEX V2 D4 HELPERS

    /// @notice Calculates the real and imaginary debt reserves for both tokens
    /// @dev This function uses a quadratic equation to determine the debt reserves
    ///      based on the geometric mean price and the current debt amounts
    /// @param gp_ The geometric mean price of upper range & lower range X96
    /// @param pa_ The price of upper range X96
    /// @param pb_ The price of lower range X96
    /// @param rx_ The real debt reserve of token0
    /// @param ry_ The real debt reserve of token1
    /// @return dx_ The debt amount of token0
    /// @return dy_ The debt amount of token1
    function _calculateDebtAmountsFromReserves(uint256 gp_, uint256 pa_, uint256 pb_, uint256 rx_, uint256 ry_) internal pure returns (uint256 dx_, uint256 dy_) {
        if (rx_ == 0) {
            // dy_ = 0;
            dx_ = FM.mulDiv(ry_, Q96, gp_);
        } else if (ry_ == 0) {
            // dx_ = 0;
            dy_ = FM.mulDiv(rx_, gp_, Q96);
        } else {
            /// @dev FINDING dx_
            // Assigning letter to knowns:
            // w = realDebtReserveA
            // x = realDebtReserveB
            // e = upperPrice
            // f = lowerPrice
            // g = upperPrice^1/2
            // h = lowerPrice^1/2

            // Assigning letter to unknowns:
            // c = debtA
            // d = debtB
            // y = imaginaryDebtReserveA
            // z = imaginaryDebtReserveB
            // k = k

            // below quadratic will give answer of debtA
            // A, B, C of quadratic equation:
            // A = -gf
            // B = hx − gwf
            // C = gwx

            // after finding the solution & simplifying: (note: gm is geometricMean, means (g*h))
            // c = ((x - gm.w) / 2.gm) + (((x - gm.w) / 2.gm)^2 + (w.x/f))^(1/2)

            // dividing in 3 parts for simplification:
            // part1 = (x - gm.w) / 2.gm
            // part2 = w.x/f
            // c = (part1 + (part2 + part1^2)^(1/2))
            // NOTE: part1 will almost always be < 1e27 but in case it goes above 1e27 then it's extremely unlikely it'll go above > 1e28

            // part1 = (realDebtReserveB - (realDebtReserveA * geometricMean)) / 2 * geometricMean
            // part2 = realDebtReserveA * realDebtReserveB / lowerPrice

            // converting decimals properly as price is in X96 decimals
            // part1 = ((realDebtReserveB * (1<<96)) - (realDebtReserveA * geometricMean)) / 2 * geometricMean
            // part2 = realDebtReserveA * realDebtReserveB * (1<<96) / lowerPrice
            // final c equals:
            // c = (part1 + (part2 + part1^2)^(1/2))
            int256 p1_ = (int256(ry_ * Q96) - int256(rx_ * gp_)) / (2 * int256(gp_));
            uint256 p2_ = rx_ * ry_;
            p2_ = FM.mulDiv(p2_, Q96, pb_);
            dx_ = uint256(p1_ + int256(FPM.sqrt((p2_ + uint256(p1_ * p1_)))));

            /// @dev FINDING z:
            // Because of mathematical symmetry, we convert the above formula to find dy_ by replacing:
            // rx_ <-> ry_
            // gp_ <-> Q192 / gp_
            // pb_ <-> Q192 / pa_
            p1_ = (int256(rx_ * gp_) - int256(ry_ * Q96)) / (2 * int256(Q96));
            p2_ = ry_ * rx_;
            p2_ = FM.mulDiv(p2_, pa_, Q96);
            dy_ = uint256(p1_ + int256(FPM.sqrt((p2_ + uint256(p1_ * p1_)))));
        }
    }

    function _getDebtAmountsFromReserves(
        uint256 geometricMeanPrice_,
        uint256 upperRangePrice_,
        uint256 lowerRangePrice_,
        uint256 token0Reserves_,
        uint256 token1Reserves_
    ) internal pure returns (uint256 token0Debt_, uint256 token1Debt_) {
        if (geometricMeanPrice_ < Q96) {
            (token0Debt_, token1Debt_) = _calculateDebtAmountsFromReserves(geometricMeanPrice_, upperRangePrice_, lowerRangePrice_, token0Reserves_, token1Reserves_);
        } else {
            // inversing, something like `xy = k` so for calculation we are making everything related to x into y & y into x
            // 1 / geometricMean for new geometricMean
            // 1 / lowerRange will become upper range
            // 1 / upperRange will become lower range
            (token1Debt_, token0Debt_) = 
                _calculateDebtAmountsFromReserves(Q192 / geometricMeanPrice_, Q192 / lowerRangePrice_, Q192 / upperRangePrice_,token1Reserves_, token0Reserves_);
        }
    }

    function _getD4DebtAmounts(
        bytes32 dexId_,
        GetD3D4AmountsParams memory params_
    ) internal view returns (uint256 token0DebtAmount_, uint256 token1DebtAmount_, uint256 feeAccruedToken0_, uint256 feeAccruedToken1_) {
        PositionData memory positionData_;
        {
            uint256 dexVariables_ = _getDexV2DexVariables(D4_DEX_TYPE, dexId_);
            positionData_ = _getDexV2PositionData(D4_DEX_TYPE, dexId_, params_.tickLower, params_.tickUpper, params_.positionSalt);
            if (positionData_.liquidity == 0) return (0, 0, 0, 0); // No debt and no fees

            if (params_.sqrtPriceX96 == AT_POOL_PRICE) {
                params_.sqrtPriceX96 = (dexVariables_ >> DSL.BITS_DEX_V2_VARIABLES_CURRENT_SQRT_PRICE) & X72;
                params_.sqrtPriceX96 = BM.fromBigNumber(params_.sqrtPriceX96, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
            }

            // NOTE: These are raw adjusted amounts
            (feeAccruedToken0_, feeAccruedToken1_) = _getDexV2FeeAccruedAmounts(
                D4_DEX_TYPE, 
                dexId_, 
                params_.tickLower, 
                params_.tickUpper, 
                dexVariables_, 
                positionData_
            );
        }

        {
            uint256 sqrtPriceLowerX96_ = TM.getSqrtRatioAtTick(params_.tickLower);
            uint256 sqrtPriceUpperX96_ = TM.getSqrtRatioAtTick(params_.tickUpper);
            (uint256 token0ReserveAmountRawAdjusted_, uint256 token1ReserveAmountRawAdjusted_) = LA.getAmountsForLiquidity(
                uint160(params_.sqrtPriceX96),
                uint160(sqrtPriceLowerX96_),
                uint160(sqrtPriceUpperX96_),
                uint128(positionData_.liquidity)
            );

            // NOTE: These are raw adjusted amounts
            (token0DebtAmount_, token1DebtAmount_) = _getDebtAmountsFromReserves(
                FM.mulDiv(sqrtPriceLowerX96_, sqrtPriceUpperX96_, Q96), // geometricMeanPriceX96_
                FM.mulDiv(sqrtPriceUpperX96_, sqrtPriceUpperX96_, Q96), // priceUpperX96_
                FM.mulDiv(sqrtPriceLowerX96_, sqrtPriceLowerX96_, Q96), // priceLowerX96_
                token0ReserveAmountRawAdjusted_,
                token1ReserveAmountRawAdjusted_
            );
        }

        (uint256 token0NumeratorPrecision_, uint256 token0DenominatorPrecision_) = _calculateNumeratorAndDenominatorPrecisions(params_.token0Decimals);
        (uint256 token1NumeratorPrecision_, uint256 token1DenominatorPrecision_) = _calculateNumeratorAndDenominatorPrecisions(params_.token1Decimals);

        // Convert raw adjusted amounts to normal amounts
        // Also explicitly rounding up to match DEX v2 rounding
        token0DebtAmount_ = (token0DebtAmount_ * token0DenominatorPrecision_ * params_.token0ExchangePrice * ROUNDING_FACTOR_PLUS_ONE) / 
            (token0NumeratorPrecision_ * LC.EXCHANGE_PRICES_PRECISION * ROUNDING_FACTOR);
        if (token0DebtAmount_ > 0) {
            token0DebtAmount_ += 1;
        }

        token1DebtAmount_ = (token1DebtAmount_ * token1DenominatorPrecision_ * params_.token1ExchangePrice * ROUNDING_FACTOR_PLUS_ONE) / 
            (token1NumeratorPrecision_ * LC.EXCHANGE_PRICES_PRECISION * ROUNDING_FACTOR);
        if (token1DebtAmount_ > 0) {
            token1DebtAmount_ += 1;
        }

        // Convert adjusted fee amounts to normal amounts
        // Also explicitly rounding down to match DEX v2 rounding
        feeAccruedToken0_ = (feeAccruedToken0_ * token0DenominatorPrecision_ * ROUNDING_FACTOR_MINUS_ONE) / (token0NumeratorPrecision_ * ROUNDING_FACTOR);
        if (feeAccruedToken0_ > 0) {
            feeAccruedToken0_ -= 1;
        }

        feeAccruedToken1_ = (feeAccruedToken1_ * token1DenominatorPrecision_ * ROUNDING_FACTOR_MINUS_ONE) / (token1NumeratorPrecision_ * ROUNDING_FACTOR);
        if (feeAccruedToken1_ > 0) {
            feeAccruedToken1_ -= 1;
        }
    }

    function _calculateCollateralValues(
        bool isOperate_, 
        uint256 tokenSupply_, 
        uint256 tokenPrice_, 
        uint256 tokenConfigs_,
        uint256 collateralValue_,
        uint256 normalizedCollateralValue_
    ) internal pure returns (uint256, uint256) {
        uint256 normalizationFactor_;
        if (isOperate_) {
            // For Operate we will use CF for HF
            normalizationFactor_ = (tokenConfigs_ >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_FACTOR) & X10;
        } else {
            // For Liquidate we will use LT
            normalizationFactor_ = (tokenConfigs_ >> MSL.BITS_TOKEN_CONFIGS_LIQUIDATION_THRESHOLD) & X10;
        }

        uint256 tokenValue_;
        if (tokenSupply_ > 0) {
            // rounded down so protocol is on the winning side
            // NOTE: Using 2 steps to round down here so hf calculation doesnt break and stops liquidations
            tokenValue_ = ((tokenSupply_ * tokenPrice_) - 1) / EIGHTEEN_DECIMALS;
            if (tokenValue_ > 0) {
                tokenValue_ -= 1;
            }
        }

        uint256 normalizedTokenValue_;
        if (tokenValue_ > 0) {
            // rounded down so protocol is on the winning side
            // NOTE: Using 2 steps to round down here so hf calculation doesnt break and stops liquidations
            normalizedTokenValue_ = ((tokenValue_ * normalizationFactor_) - 1) / THREE_DECIMALS;
            if (normalizedTokenValue_ > 0) {
                normalizedTokenValue_ -= 1;
            }
        }

        collateralValue_ += tokenValue_;
        normalizedCollateralValue_ += normalizedTokenValue_;

        return (collateralValue_, normalizedCollateralValue_);
    }

    function _getPrice(
        IOracle oracle_, 
        address token_, 
        uint256 tokenDecimals_, 
        uint256 emode_, 
        bool isOperate_, 
        bool isCollateral_
    ) internal returns (uint256 tokenPrice_) {
        tokenPrice_ = oracle_.getPrice(token_, emode_, isOperate_, isCollateral_);

        if (isOperate_) {
            if (tokenPrice_ < 1e9 || tokenPrice_ > 1e27) revert(); // Invalid price
        } else {
            if (tokenPrice_ < 10 || tokenPrice_ > 1e27) revert(); // Invalid price
        }
        
        if (tokenDecimals_ < MAX_TOKEN_DECIMALS) {
            tokenPrice_ = tokenPrice_ * _tenPow(MAX_TOKEN_DECIMALS - tokenDecimals_);
        }
    }

    function _calculateSqrtPriceX96(
        uint256 token0Price_,
        uint256 token1Price_,
        uint256 token0ExchangePrice_,
        uint256 token1ExchangePrice_,
        uint256 token0Decimals_,
        uint256 token1Decimals_
    ) internal pure returns (uint256 sqrtPriceX96_) {
        // We have to use adjusted prices here because the money market prices are decimal adjusted
        // whereas the token amounts are adjusted on the dex v2 side
        if (token0Decimals_ < MAX_TOKEN_DECIMALS) {
            token0Price_ = token0Price_ / _tenPow(MAX_TOKEN_DECIMALS - token0Decimals_);
        }
        if (token1Decimals_ < MAX_TOKEN_DECIMALS) {
            token1Price_ = token1Price_ / _tenPow(MAX_TOKEN_DECIMALS - token1Decimals_);
        }

        sqrtPriceX96_ = FPM.sqrt(FM.mulDiv(token0Price_ * token0ExchangePrice_, Q192, token1Price_ * token1ExchangePrice_));
    }

    function _getHfInfo(uint256 nftId_, bool isOperate_) internal returns (HfInfo memory hfInfo_) {
        GetHfVariables memory v_;
        {
            uint256 moneyMarketVariables_ = _moneyMarketVariables;
            v_.oracle = IOracle(address(uint160(moneyMarketVariables_))); // The first 160 bits of the token configs are the token address
            hfInfo_.minNormalizedCollateralValue = ((moneyMarketVariables_ >> MSL.BITS_MONEY_MARKET_VARIABLES_MIN_NORMALIZED_COLLATERAL_VALUE) & X12) * EIGHTEEN_DECIMALS;
        }

        {
            uint256 nftConfig_ = _nftConfigs[nftId_];
            v_.emode = (nftConfig_ >> MSL.BITS_NFT_CONFIGS_EMODE) & X12;
            v_.numberOfPositions = (nftConfig_ >> MSL.BITS_NFT_CONFIGS_NUMBER_OF_POSITIONS) & X10;
        }

        for (uint256 i_ = 1; i_ <= v_.numberOfPositions; i_++) {
            uint256 positionData_ = _positionData[nftId_][i_];
            uint256 positionType_ = (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE) & X5;
            if (positionType_ == NORMAL_SUPPLY_POSITION_TYPE || positionType_ == NORMAL_BORROW_POSITION_TYPE) {
                uint256 tokenIndex_ = (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_INDEX) & X12;
                uint256 tokenConfigs_ = _getTokenConfigs(v_.emode, tokenIndex_); // The first 160 bits of the token configs are the token address
                address token_ = address(uint160(tokenConfigs_));

                if (positionType_ == NORMAL_SUPPLY_POSITION_TYPE) {
                    uint256 tokenPrice_ = _getPrice(
                        v_.oracle, 
                        token_, 
                        tokenConfigs_ >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS & X5,
                        v_.emode,
                        isOperate_,
                        IS_COLLATERAL
                    );

                    uint256 tokenSupply_ = (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT) & X64;
                    tokenSupply_ = BM.fromBigNumber(tokenSupply_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

                    {
                        (uint256 supplyExchangePrice_, ) = _getExchangePrices(token_);

                        // rounded down so protocol is on the winning side
                        // NOTE: Using 2 steps to round down here so hf calculation doesnt break and stops liquidations
                        if (tokenSupply_ > 0) {
                            tokenSupply_ = ((tokenSupply_ * supplyExchangePrice_) - 1) / LC.EXCHANGE_PRICES_PRECISION;
                            if (tokenSupply_ > 0) {
                                tokenSupply_ -= 1;
                            }
                        }
                    }

                    (hfInfo_.collateralValue, hfInfo_.normalizedCollateralValue) = _calculateCollateralValues(
                        isOperate_,
                        tokenSupply_,
                        tokenPrice_,
                        tokenConfigs_,
                        hfInfo_.collateralValue,
                        hfInfo_.normalizedCollateralValue
                    );
                } else {
                    uint256 tokenPrice_ = _getPrice(
                        v_.oracle, 
                        token_, 
                        tokenConfigs_ >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS & X5,
                        v_.emode,
                        isOperate_,
                        IS_DEBT
                    );

                    uint256 tokenDebt_ = (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT) & X64;
                    tokenDebt_ = BM.fromBigNumber(tokenDebt_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

                    {    
                        (, uint256 borrowExchangePrice_) = _getExchangePrices(token_);
                        tokenDebt_ = (((tokenDebt_ * borrowExchangePrice_) + 1) / LC.EXCHANGE_PRICES_PRECISION) + 1; // rounded up so protocol is on the winning side
                    }

                    if (tokenDebt_ > 0) {
                        hfInfo_.debtValue += (((tokenDebt_ * tokenPrice_) + 1) / EIGHTEEN_DECIMALS) + 1; // rounded up so protocol is on the winning side
                    }
                }
            } else if (positionType_ == D3_POSITION_TYPE || positionType_ == D4_POSITION_TYPE) {
                // Build the dex key
                DexKey memory dexKey_;
                GetHfD3D4Variables memory vhf_;

                vhf_.token0Configs = _getTokenConfigs(v_.emode, (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_0_INDEX) & X12);
                vhf_.token1Configs = _getTokenConfigs(v_.emode, (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_1_INDEX) & X12);

                (dexKey_, vhf_.tickLower, vhf_.tickUpper) = _decodeD3D4PositionData(positionData_, vhf_.token0Configs, vhf_.token1Configs);

                vhf_.positionSalt = keccak256(abi.encode(nftId_));

                vhf_.positionFeeStored = _positionFeeStored[nftId_][keccak256(abi.encode(positionType_, dexKey_))][
                    keccak256(abi.encode(address(this), vhf_.tickLower, vhf_.tickUpper, vhf_.positionSalt))];

                if (positionType_ == D3_POSITION_TYPE) {
                    vhf_.token0Price = _getPrice(
                        v_.oracle, 
                        dexKey_.token0, 
                        vhf_.token0Configs >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS & X5,
                        v_.emode,
                        isOperate_,
                        IS_COLLATERAL
                    );

                    vhf_.token1Price = _getPrice(
                        v_.oracle, 
                        dexKey_.token1, 
                        vhf_.token1Configs >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS & X5,
                        v_.emode,
                        isOperate_,
                        IS_COLLATERAL
                    );

                    uint256 token0SupplyAmount_;
                    uint256 token1SupplyAmount_;
                    {
                        uint256 feeAccruedToken0_;
                        uint256 feeAccruedToken1_;
                        {
                            (uint256 token0SupplyExchangePrice_, ) = _getExchangePrices(dexKey_.token0);
                            (uint256 token1SupplyExchangePrice_, ) = _getExchangePrices(dexKey_.token1);

                            uint256 token0Decimals_ = (vhf_.token0Configs >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) & X5;
                            uint256 token1Decimals_ = (vhf_.token1Configs >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) & X5;

                            uint256 sqrtPriceX96_ = _calculateSqrtPriceX96(
                                vhf_.token0Price, 
                                vhf_.token1Price, 
                                token0SupplyExchangePrice_, 
                                token1SupplyExchangePrice_, 
                                token0Decimals_, 
                                token1Decimals_
                            );

                            (token0SupplyAmount_, token1SupplyAmount_, feeAccruedToken0_, feeAccruedToken1_) = _getD3SupplyAmounts(
                                _getDexId(dexKey_), 
                                GetD3D4AmountsParams({
                                    tickLower: vhf_.tickLower,
                                    tickUpper: vhf_.tickUpper,
                                    positionSalt: vhf_.positionSalt,
                                    token0Decimals: token0Decimals_,
                                    token1Decimals: token1Decimals_,
                                    token0ExchangePrice: token0SupplyExchangePrice_,
                                    token1ExchangePrice: token1SupplyExchangePrice_,
                                    sqrtPriceX96: sqrtPriceX96_
                                })
                            );
                        }

                        // Now we need add fee stored and fees accrued to this amount also
                        token0SupplyAmount_ += ((vhf_.positionFeeStored >> MSL.BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_0) & X128) + feeAccruedToken0_;
                        token1SupplyAmount_ += ((vhf_.positionFeeStored >> MSL.BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_1) & X128) + feeAccruedToken1_;
                    }

                    (hfInfo_.collateralValue, hfInfo_.normalizedCollateralValue) = _calculateCollateralValues(
                        isOperate_, 
                        token0SupplyAmount_, 
                        vhf_.token0Price, 
                        vhf_.token0Configs,
                        hfInfo_.collateralValue,
                        hfInfo_.normalizedCollateralValue
                    );
                    (hfInfo_.collateralValue, hfInfo_.normalizedCollateralValue) = _calculateCollateralValues(
                        isOperate_,
                        token1SupplyAmount_,
                        vhf_.token1Price,
                        vhf_.token1Configs,
                        hfInfo_.collateralValue,
                        hfInfo_.normalizedCollateralValue
                    );
                } else {
                    vhf_.token0Price = _getPrice(
                        v_.oracle, 
                        dexKey_.token0, 
                        vhf_.token0Configs >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS & X5,
                        v_.emode,
                        isOperate_,
                        IS_DEBT
                    );
                    vhf_.token1Price = _getPrice(
                        v_.oracle, 
                        dexKey_.token1, 
                        vhf_.token1Configs >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS & X5,
                        v_.emode,
                        isOperate_,
                        IS_DEBT
                    );

                    uint256 token0FeeAmount_;
                    uint256 token1FeeAmount_;
                    {
                        uint256 token0DebtAmount_;
                        uint256 token1DebtAmount_;
                        {
                            (, uint256 token0BorrowExchangePrice_) = _getExchangePrices(dexKey_.token0);
                            (, uint256 token1BorrowExchangePrice_) = _getExchangePrices(dexKey_.token1);

                            uint256 token0Decimals_ = (vhf_.token0Configs >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) & X5;
                            uint256 token1Decimals_ = (vhf_.token1Configs >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) & X5;

                            uint256 sqrtPriceX96_ = _calculateSqrtPriceX96(
                                vhf_.token0Price, 
                                vhf_.token1Price, 
                                token0BorrowExchangePrice_, 
                                token1BorrowExchangePrice_, 
                                token0Decimals_, 
                                token1Decimals_
                            );

                            uint256 feeAccruedToken0_;
                            uint256 feeAccruedToken1_;
                            (token0DebtAmount_, token1DebtAmount_, feeAccruedToken0_, feeAccruedToken1_) = _getD4DebtAmounts(
                                _getDexId(dexKey_),
                                GetD3D4AmountsParams({
                                    tickLower: vhf_.tickLower,
                                    tickUpper: vhf_.tickUpper,
                                    positionSalt: vhf_.positionSalt,
                                    token0Decimals: token0Decimals_,
                                    token1Decimals: token1Decimals_,
                                    token0ExchangePrice: token0BorrowExchangePrice_,
                                    token1ExchangePrice: token1BorrowExchangePrice_,
                                    sqrtPriceX96: sqrtPriceX96_
                                })
                            );
                            // Now we also need to add fee on the collateral side
                            token0FeeAmount_ = ((vhf_.positionFeeStored >> MSL.BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_0) & X128) + feeAccruedToken0_;
                            token1FeeAmount_ = ((vhf_.positionFeeStored >> MSL.BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_1) & X128) + feeAccruedToken1_;
                        }

                        if (token0DebtAmount_ > 0) {
                            hfInfo_.debtValue += (((token0DebtAmount_ * vhf_.token0Price) + 1) / EIGHTEEN_DECIMALS) + 1; // rounded up so protocol is on the winning side
                        }
                        if (token1DebtAmount_ > 0) {
                            hfInfo_.debtValue += (((token1DebtAmount_ * vhf_.token1Price) + 1) / EIGHTEEN_DECIMALS) + 1; // rounded up so protocol is on the winning side
                        }
                    }

                    // We will need to update to collateral side prices for this
                    vhf_.token0Price = _getPrice(
                        v_.oracle, 
                        dexKey_.token0, 
                        vhf_.token0Configs >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS & X5,
                        v_.emode,
                        isOperate_,
                        IS_COLLATERAL
                    );
                    vhf_.token1Price = _getPrice(
                        v_.oracle, 
                        dexKey_.token1, 
                        vhf_.token1Configs >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS & X5,
                        v_.emode,
                        isOperate_,
                        IS_COLLATERAL
                    );

                    (hfInfo_.collateralValue, hfInfo_.normalizedCollateralValue) = _calculateCollateralValues(
                        isOperate_,
                        token0FeeAmount_,
                        vhf_.token0Price,
                        vhf_.token0Configs,
                        hfInfo_.collateralValue,
                        hfInfo_.normalizedCollateralValue
                    );
                    (hfInfo_.collateralValue, hfInfo_.normalizedCollateralValue) = _calculateCollateralValues(
                        isOperate_,
                        token1FeeAmount_,
                        vhf_.token1Price,
                        vhf_.token1Configs,
                        hfInfo_.collateralValue,
                        hfInfo_.normalizedCollateralValue
                    );
                }
            } else {
                revert(); // Invalid position type
            }
        }

        if (hfInfo_.debtValue == 0) {
            hfInfo_.hf = type(uint256).max;
        } else {
            hfInfo_.hf = (hfInfo_.normalizedCollateralValue * EIGHTEEN_DECIMALS) / hfInfo_.debtValue;
        }

        return hfInfo_;
    }

    function _checkHf(uint256 nftId_, bool isOperate_) internal {
        HfInfo memory hfInfo_ = _getHfInfo(nftId_, isOperate_);
        if (hfInfo_.debtValue != 0) {
            // We will revert if the collateral is too small, because that will make liquidations uneconomical
            if (isOperate_ && hfInfo_.normalizedCollateralValue < hfInfo_.minNormalizedCollateralValue) revert FluidMoneyMarketError(ErrorTypes.Helpers__HealthFactorFailed);
            if (hfInfo_.hf < EIGHTEEN_DECIMALS) revert FluidMoneyMarketError(ErrorTypes.Helpers__HealthFactorFailed);
        }
    }
}