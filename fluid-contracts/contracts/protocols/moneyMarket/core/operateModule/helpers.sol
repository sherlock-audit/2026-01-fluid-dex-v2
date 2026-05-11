// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./events.sol";

abstract contract Helpers is CommonImport {
    function _addPosition(uint256 nftId_, uint256 nftConfig_, uint256 positionData_) internal returns (uint256 positionIndex_) {
        positionIndex_ = ((nftConfig_ >> MSL.BITS_NFT_CONFIGS_NUMBER_OF_POSITIONS) & X10) + 1;

        if (positionIndex_ > (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_MAX_POSITIONS_PER_NFT) & X10) revert(); // Max positions per NFT reached

        // Update the number of positions in the nft config
        _nftConfigs[nftId_] =
            (nftConfig_ & ~(X10 << MSL.BITS_NFT_CONFIGS_NUMBER_OF_POSITIONS)) |
            (positionIndex_ << MSL.BITS_NFT_CONFIGS_NUMBER_OF_POSITIONS);

        // Add to mapping
        _positionData[nftId_][positionIndex_] = positionData_;
    }

    function _beforeCreatingIsolatedCollateralPosition(uint256 nftId_, uint256 nftConfig_, uint256 tokenIndex_) internal returns (uint256) {
        // If collateral being supplied is an isolated collateral there can be 2 cases:
        // 1. The isolated collateral flag is already ON in the nft config. In this case we just need to check that the isolated token index in the nft config is the same as the token index in the action data
        // 2. The isolated collateral flag is OFF in the nft config. This means that an isolated collateral is being supplied for the first time. In this case we need to:
        //    a. Check that there should be no positions of type 4 (smart debt)
        //    b. For all positions of type 2, update the Total Token Raw Borrow in the _isolatedCapConfigs mapping and make sure that it doesnt exceed the Max Total Token Raw Borrow
        //    c. Update the isolated collateral flag and isolated collateral index

        if ((nftConfig_ >> MSL.BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_FLAG) & X1 == 1) {
            // Case 1: The isolated collateral flag is already ON in the nft config
            if ((nftConfig_ >> MSL.BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_TOKEN_INDEX) & X12 != tokenIndex_) revert();
        } else {
            // Check that there should be no positions of type 4 (smart debt)
            uint256 numberOfPositions_ = (nftConfig_ >> MSL.BITS_NFT_CONFIGS_NUMBER_OF_POSITIONS) & X10;
            for (uint256 i_ = 1; i_ <= numberOfPositions_; i_++) {
                uint256 stepPositionData_ = _positionData[nftId_][i_];
                uint256 stepPositionType_ = (stepPositionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE) & X5;
                if (stepPositionType_ == D4_POSITION_TYPE) {
                    revert(); // smart debt not allowed
                } else if (stepPositionType_ == NORMAL_BORROW_POSITION_TYPE) {
                    // Updating the Total Token Raw Borrow in the _isolatedCapConfigs mapping and make sure that it doesnt exceed the Max Total Token Raw Borrow
                    uint256 tokenRawBorrow_ = (stepPositionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT) & X64;
                    tokenRawBorrow_ = BM.fromBigNumber(tokenRawBorrow_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

                    uint256 stepTokenIndex_ = (stepPositionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_INDEX) & X12;

                    uint256 isolatedCapConfigs_ = _isolatedCapConfigs[tokenIndex_][stepTokenIndex_];
                    uint256 maxTotalTokenRawBorrow_ = (isolatedCapConfigs_ >> MSL.BITS_ISOLATED_CAP_CONFIGS_MAX_TOTAL_TOKEN_RAW_BORROW) & X18;
                    maxTotalTokenRawBorrow_ = BM.fromBigNumber(maxTotalTokenRawBorrow_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

                    uint256 totalTokenRawBorrow_ = (isolatedCapConfigs_ >> MSL.BITS_ISOLATED_CAP_CONFIGS_TOTAL_TOKEN_RAW_BORROW) & X64;
                    totalTokenRawBorrow_ = BM.fromBigNumber(totalTokenRawBorrow_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

                    totalTokenRawBorrow_ += tokenRawBorrow_;

                    if (totalTokenRawBorrow_ > maxTotalTokenRawBorrow_) revert();

                    totalTokenRawBorrow_ = BM.toBigNumber(totalTokenRawBorrow_, DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_UP); // Rounding up here so caps dont get violated because of any precision loss
                    _isolatedCapConfigs[tokenIndex_][stepTokenIndex_] = isolatedCapConfigs_ & ~(X64 << MSL.BITS_ISOLATED_CAP_CONFIGS_TOTAL_TOKEN_RAW_BORROW) | 
                        (totalTokenRawBorrow_ << MSL.BITS_ISOLATED_CAP_CONFIGS_TOTAL_TOKEN_RAW_BORROW);
                }
            }

            // Update the isolated collateral flag and isolated collateral index
            // NOTE: Not updating the nftConfig on storage here because the _addPosition function will update it on storage
            nftConfig_ = (nftConfig_ & ~(X12 << MSL.BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_TOKEN_INDEX)) | 
                (X1 << MSL.BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_FLAG) |
                (tokenIndex_ << MSL.BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_TOKEN_INDEX);
        }

        return nftConfig_;
    }

    function _checkAndUpdatePositionCap(bytes32 positionId_, uint256 tokenRawAmount_) internal {
        uint256 positionCapConfigs_ = _positionCapConfigs[positionId_];
        uint256 maxTotalTokenRawAmount_ = (positionCapConfigs_ >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_MAX_TOTAL_TOKEN_RAW_AMOUNT) & X18;
        maxTotalTokenRawAmount_ = BM.fromBigNumber(maxTotalTokenRawAmount_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
        
        uint256 totalTokenRawAmount_ = (positionCapConfigs_ >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_TOTAL_TOKEN_RAW_AMOUNT) & X64;
        totalTokenRawAmount_ = BM.fromBigNumber(totalTokenRawAmount_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

        totalTokenRawAmount_ += tokenRawAmount_;

        if (totalTokenRawAmount_ > maxTotalTokenRawAmount_) revert();

        totalTokenRawAmount_ = BM.toBigNumber(totalTokenRawAmount_, DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_UP); // Rounding up here so caps dont get violated because of any precision loss
        _positionCapConfigs[positionId_] = positionCapConfigs_ & ~(X64 << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_TOTAL_TOKEN_RAW_AMOUNT) | 
            (totalTokenRawAmount_ << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_TOTAL_TOKEN_RAW_AMOUNT);
    }

    function _checkAndUpdateCapsForNormalSupply(uint256 tokenIndex_, uint256 tokenRawSupply_) internal {
        _checkAndUpdatePositionCap(keccak256(abi.encode(NORMAL_SUPPLY_POSITION_TYPE, tokenIndex_)), tokenRawSupply_);
    }

    function _checkAndUpdateCapsForNormalBorrow(uint256 nftConfig_, uint256 tokenIndex_, uint256 tokenRawBorrow_) internal {
        // Check if the nft has isolated collateral flag as ON, if it is then we need to update the _isolatedCapConfigs mapping with the debt and make sure that it doesnt exceed the cap
        if ((nftConfig_ >> MSL.BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_FLAG) & X1 == 1) {
            uint256 isolatedTokenIndex_ = (nftConfig_ >> MSL.BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_TOKEN_INDEX) & X12;

            uint256 isolatedCapConfigs_ = _isolatedCapConfigs[isolatedTokenIndex_][tokenIndex_];
            uint256 maxTotalTokenRawBorrow_ = (isolatedCapConfigs_ >> MSL.BITS_ISOLATED_CAP_CONFIGS_MAX_TOTAL_TOKEN_RAW_BORROW) & X18;
            maxTotalTokenRawBorrow_ = BM.fromBigNumber(maxTotalTokenRawBorrow_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

            uint256 totalTokenRawBorrow_ = (isolatedCapConfigs_ >> MSL.BITS_ISOLATED_CAP_CONFIGS_TOTAL_TOKEN_RAW_BORROW) & X64;
            totalTokenRawBorrow_ = BM.fromBigNumber(totalTokenRawBorrow_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

            totalTokenRawBorrow_ += tokenRawBorrow_;

            if (totalTokenRawBorrow_ > maxTotalTokenRawBorrow_) revert();

            totalTokenRawBorrow_ = BM.toBigNumber(totalTokenRawBorrow_, DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_UP); // Rounding up here so caps dont get violated because of any precision loss
            _isolatedCapConfigs[isolatedTokenIndex_][tokenIndex_] = isolatedCapConfigs_ & ~(X64 << MSL.BITS_ISOLATED_CAP_CONFIGS_TOTAL_TOKEN_RAW_BORROW) | 
                (totalTokenRawBorrow_ << MSL.BITS_ISOLATED_CAP_CONFIGS_TOTAL_TOKEN_RAW_BORROW);
        }

        // Now we need to update the debt amount in the _positionCapConfigs mapping
        _checkAndUpdatePositionCap(keccak256(abi.encode(NORMAL_BORROW_POSITION_TYPE, tokenIndex_)), tokenRawBorrow_);
    }

    function _createPosition(uint256 nftId_, uint256 nftConfig_, uint256 emode_, bytes calldata actionData_) internal returns (uint256 positionIndex_) {
        // First we check which type of position does the user wants to create
        uint256 positionType_ = abi.decode(actionData_, (uint256));

        if (positionType_ == NORMAL_SUPPLY_POSITION_TYPE) {
            (, uint256 tokenIndex_, uint256 supplyAmount_) = abi.decode(actionData_, (uint256, uint256, uint256));
            if (tokenIndex_ == 0 || tokenIndex_ > (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_TOKENS) & X12) revert();
            _verifyAmountLimits(supplyAmount_);

            uint256 tokenRawSupply_;
            {
                uint256 tokenConfigs_ = _getTokenConfigs(emode_, tokenIndex_);
                address token_ = address(uint160(tokenConfigs_)); // The first 160 bits of the token configs are the token address
                if (token_ == address(0)) revert();

                uint256 ethAmount_;
                if (token_ == NATIVE_TOKEN) {
                    ethAmount_ = supplyAmount_;
                    _msgValue -= ethAmount_; // will revert if it goes negative
                }
                // Get the supply from the user
                (uint256 supplyExchangePrice_, ) = LIQUIDITY.operate{value: ethAmount_}(
                    token_,
                    int256(supplyAmount_),
                    0,
                    address(0),
                    address(0),
                    abi.encode(MONEY_MARKET_IDENTIFIER, CREATE_NORMAL_SUPPLY_POSITION_ACTION_IDENTIFIER)
                );

                {
                    uint256 collateralClass_ = (tokenConfigs_ >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) & X3;

                    if (collateralClass_ == COLLATERAL_CLASS_NOT_ENABLED) {
                        revert(); // collateral not enabled
                    } else if (collateralClass_ == COLLATERAL_CLASS_ISOLATED) {
                        nftConfig_ = _beforeCreatingIsolatedCollateralPosition(nftId_, nftConfig_, tokenIndex_);
                    }
                }
                // If collateral class is 1 or 2, then that means a good collateral is being supplied hence we continue

                // rounded down so protocol is on the winning side
                tokenRawSupply_ = ((uint256(supplyAmount_) * LC.EXCHANGE_PRICES_PRECISION) - 1) / supplyExchangePrice_;
                if (tokenRawSupply_ > 0) tokenRawSupply_ -= 1;
            }

            _checkAndUpdateCapsForNormalSupply(tokenIndex_, tokenRawSupply_);

            // Now we need to update the supply the _positionData mapping
            tokenRawSupply_ = BM.toBigNumber(tokenRawSupply_, DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN); // rounded down so protocol is on the winning side
            {
                uint256 positionData_ = (NORMAL_SUPPLY_POSITION_TYPE << MSL.BITS_POSITION_DATA_POSITION_TYPE) | 
                    (tokenIndex_ << MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_INDEX) |
                    (tokenRawSupply_ << MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT);

                // Store the position data on storage
                positionIndex_ = _addPosition(nftId_, nftConfig_, positionData_);
            }

            // NOTE: No need to check the health factor as the user is supplying
        } else if (positionType_ == NORMAL_BORROW_POSITION_TYPE) {
            (, uint256 tokenIndex_, uint256 borrowAmount_, address to_) = abi.decode(actionData_, (uint256, uint256, uint256, address));
            if (tokenIndex_ == 0 || tokenIndex_ > (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_TOKENS) & X12) revert();
            _verifyAmountLimits(borrowAmount_);

            address token_;
            {
                uint256 tokenConfigs_ = _getTokenConfigs(emode_, tokenIndex_);

                token_ = address(uint160(tokenConfigs_)); // The first 160 bits of the token configs are the token address
                if (token_ == address(0)) revert();

                if ((tokenConfigs_ >> MSL.BITS_TOKEN_CONFIGS_DEBT_CLASS) & X3 == DEBT_CLASS_NOT_ENABLED) {
                    revert(); // debt not enabled
                }
            }

            _validateDebtForEmode(emode_, tokenIndex_);

            uint256 tokenRawBorrow_;
            {
                (, uint256 borrowExchangePrice_) = _getExchangePrices(token_);
                tokenRawBorrow_ = (((uint256(borrowAmount_) * LC.EXCHANGE_PRICES_PRECISION) + 1) / borrowExchangePrice_) + 1; // rounded up so protocol is on the winning side
            }

            _checkAndUpdateCapsForNormalBorrow(nftConfig_, tokenIndex_, tokenRawBorrow_);

            // Now we need to update the debt amount in the _positionData mapping
            tokenRawBorrow_ = BM.toBigNumber(tokenRawBorrow_, DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_UP); // rounded up so protocol is on the winning side
            {
                uint256 positionData_ = (NORMAL_BORROW_POSITION_TYPE << MSL.BITS_POSITION_DATA_POSITION_TYPE) | 
                    (tokenIndex_ << MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_INDEX) |
                    (tokenRawBorrow_ << MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT);

                // Store the position data on storage
                positionIndex_ = _addPosition(nftId_, nftConfig_, positionData_);
            }

            // Check the health factor of the position
            _checkHf(nftId_, IS_OPERATE);

            // Give the borrow to the user
            LIQUIDITY.operate(
                token_, 
                0, 
                int256(borrowAmount_), 
                address(0), 
                to_, 
                abi.encode(MONEY_MARKET_IDENTIFIER, CREATE_NORMAL_BORROW_POSITION_ACTION_IDENTIFIER)
            );
        } else if (positionType_ == D3_POSITION_TYPE || positionType_ == D4_POSITION_TYPE) {
            (
                ,
                CreateD3D4PositionParams memory p_
            ) = abi.decode(actionData_, (uint256, CreateD3D4PositionParams));

            {
                uint256 totalTokens_ = (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_TOKENS) & X12;
                if (p_.token0Index == 0 || p_.token0Index > totalTokens_ || p_.token1Index == 0 || p_.token1Index > totalTokens_) revert();
            }

            // Make sure that this is not a fee collection operation
            if (p_.amount0 == 0 && p_.amount1 == 0) revert();

            // NOTE: This is checked in the start operation callback
            // Verify the amounts are within the limits
            // if (p_.amount0 > 0) _verifyAmountLimits(p_.amount0);
            // if (p_.amount1 > 0) _verifyAmountLimits(p_.amount1);

            CreateD3D4PositionVariables memory v_;

            v_.token0Configs = _getTokenConfigs(emode_, p_.token0Index);
            v_.token1Configs = _getTokenConfigs(emode_, p_.token1Index);

            if (positionType_ == D3_POSITION_TYPE) {
                uint256 token0CollateralClass_ = (v_.token0Configs >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) & X3;
                uint256 token1CollateralClass_ = (v_.token1Configs >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) & X3;

                // We need to check the following:
                // 1. If any of the tokens is not enabled as collateral, then revert
                // 2. If both the tokens are of isolated collateral class, then revert
                // 3. If any one of the tokens is of isolated collateral class, then we need to update the nft config and _isolatedCapConfigs
                if (token0CollateralClass_ == COLLATERAL_CLASS_NOT_ENABLED || token1CollateralClass_ == COLLATERAL_CLASS_NOT_ENABLED) {
                    revert();
                } else if (token0CollateralClass_ == COLLATERAL_CLASS_ISOLATED && token1CollateralClass_ == COLLATERAL_CLASS_ISOLATED) {
                    // Both the tokens cannot be of isolated collateral class because 2 isolated collaterals are not allowed
                    revert();
                } else if (token0CollateralClass_ == COLLATERAL_CLASS_ISOLATED) {
                    nftConfig_ = _beforeCreatingIsolatedCollateralPosition(nftId_, nftConfig_, p_.token0Index);
                } else if (token1CollateralClass_ == COLLATERAL_CLASS_ISOLATED) {
                    nftConfig_ = _beforeCreatingIsolatedCollateralPosition(nftId_, nftConfig_, p_.token1Index);
                }

                // If both of the tokens are of permissionless class then its a permissionless deposit, otherwise its a permissioned deposit
                // If its a permissionless deposit in the start operation callback the _positionCapConfigs will be updated with the position liquidity without doing any checks
                // if its a permissioned deposit then in the start operation callback we will check if the position the user is trying to create is valid and then update the _positionCapConfigs
                if (token0CollateralClass_ == COLLATERAL_CLASS_PERMISSIONLESS && token1CollateralClass_ == COLLATERAL_CLASS_PERMISSIONLESS) {
                    v_.permissionlessTokens = true;
                }
            } else if (positionType_ == D4_POSITION_TYPE) {
                // Check if the nft has isolated collateral flag as ON, if it is then we need to update revert because if there is an isolated collateral we cannot have smart debt
                if ((nftConfig_ >> MSL.BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_FLAG) & X1 == 1) {
                    revert();
                }

                {
                    uint256 token0DebtClass_ = (v_.token0Configs >> MSL.BITS_TOKEN_CONFIGS_DEBT_CLASS) & X3;
                    uint256 token1DebtClass_ = (v_.token1Configs >> MSL.BITS_TOKEN_CONFIGS_DEBT_CLASS) & X3;

                    if (token0DebtClass_ == DEBT_CLASS_NOT_ENABLED || token1DebtClass_ == DEBT_CLASS_NOT_ENABLED) {
                        revert();
                    }

                    // If both of the tokens are of permissionless debt class then its a permissionless borrow, otherwise its a permissioned borrow
                    // If its a permissionless borrow in the start operation callback the _positionCapConfigs will be updated with the position liquidity without doing any checks
                    // if its a permissioned borrow then in the start operation callback we will check if the position the user is trying to create is valid and then update the _positionCapConfigs
                    if (token0DebtClass_ == DEBT_CLASS_PERMISSIONLESS && token1DebtClass_ == DEBT_CLASS_PERMISSIONLESS) {
                        v_.permissionlessTokens = true;
                    }
                }

                // NOTE: These checks are added in the start operation callback
                // _validateDebtForEmode(emode_, p_.token0Index);
                // _validateDebtForEmode(emode_, p_.token1Index);

                // NOTE: We dont allow creating D4 positions for tokens who are not enabled as collateral or are isolated collateral class
                // because the fee accrued is counted on the collateral side
                {
                    uint256 token0CollateralClass_ = (v_.token0Configs >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) & X3;
                    uint256 token1CollateralClass_ = (v_.token1Configs >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) & X3;
                    if (
                        token0CollateralClass_ == COLLATERAL_CLASS_NOT_ENABLED || 
                        token1CollateralClass_ == COLLATERAL_CLASS_NOT_ENABLED ||
                        token0CollateralClass_ == COLLATERAL_CLASS_ISOLATED || 
                        token1CollateralClass_ == COLLATERAL_CLASS_ISOLATED
                    ) revert();
                }
            } else {
                // This wont ever happen
                revert(); // Invalid position type
            }

            if (p_.fee == DYNAMIC_FEE_FLAG) {
                v_.isDynamicFeeFlag = 1;
                p_.fee = 0;
            } else if (p_.fee > X17) revert();

            if (p_.tickSpacing > MAX_TICK_SPACING ||
                p_.tickLower >= p_.tickUpper ||
                p_.tickLower < MIN_TICK ||
                p_.tickUpper > MAX_TICK
            ) revert();

            // Build the dex key
            DexKey memory dexKey_ = DexKey({
                token0: address(uint160(v_.token0Configs)), // The first 160 bits of the token configs are the token address
                token1: address(uint160(v_.token1Configs)), // The first 160 bits of the token configs are the token address
                fee: v_.isDynamicFeeFlag == 1 ? DYNAMIC_FEE_FLAG : p_.fee,
                tickSpacing: p_.tickSpacing,
                controller: p_.controller
            });

            // Build the position salt
            v_.positionSalt = keccak256(abi.encode(nftId_));

            if (!_isD3D4PositionEmpty(nftId_, positionType_, dexKey_, p_.tickLower, p_.tickUpper, v_.positionSalt)) revert(); // Position already exists

            {
                uint256 positionData_ = (positionType_ << MSL.BITS_POSITION_DATA_POSITION_TYPE) |
                    (p_.token0Index << MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_0_INDEX) |
                    (p_.token1Index << MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_1_INDEX) |
                    (v_.isDynamicFeeFlag << MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_IS_DYNAMIC_FEE_POOL) |
                    (uint256(p_.fee) << MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_FEE) |
                    (uint256(p_.tickSpacing) << MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TICK_SPACING) |
                    (uint256(uint160(p_.controller)) << MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_CONTROLLER_ADDRESS) |
                    ((p_.tickLower < 0 ? uint256(0) : uint256(1)) << MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_LOWER_TICK_SIGN) |
                    ((p_.tickLower < 0 ? uint256(uint24(-p_.tickLower)) : uint256(uint24(p_.tickLower))) << MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_ABSOLUTE_LOWER_TICK) |
                    ((p_.tickUpper < 0 ? uint256(0) : uint256(1)) << MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_UPPER_TICK_SIGN) |
                    ((p_.tickUpper < 0 ? uint256(uint24(-p_.tickUpper)) : uint256(uint24(p_.tickUpper))) << MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_ABSOLUTE_UPPER_TICK);

                // Store the position data on storage
                positionIndex_ = _addPosition(nftId_, nftConfig_, positionData_);
            }

            DEX_V2.startOperation(
                abi.encode(
                    dexKey_,
                    StartOperationParams({
                        isOperate: IS_OPERATE,
                        positionType: positionType_,
                        nftId: nftId_,
                        nftConfig: nftConfig_,
                        token0Index: p_.token0Index,
                        token1Index: p_.token1Index,
                        positionIndex: positionIndex_,
                        tickLower: p_.tickLower,
                        tickUpper: p_.tickUpper,
                        positionSalt: v_.positionSalt,
                        emode: emode_,
                        permissionlessTokens: v_.permissionlessTokens,
                        actionData: abi.encode(int256(p_.amount0), int256(p_.amount1), p_.amount0Min, p_.amount1Min, p_.to)
                    })
                )
            );
        } else {
            revert(); // Invalid position type
        }
    }

    function _processNormalSupplyAction(
        uint256 nftId_,
        uint256 nftConfig_,
        uint256 positionIndex_,
        uint256 positionData_,
        uint256 emode_,
        bytes calldata actionData_
    ) internal {
        uint256 tokenIndex_ = (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_INDEX) & X12;
        // if (tokenIndex_ >= (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_TOKENS) & X14) revert(); // This check is not needed because we got the tokenIndex_ from the position data only

        address token_ = address(uint160(_getTokenConfigs(emode_, tokenIndex_))); // The first 160 bits of the token configs are the token address
        if (token_ == address(0)) revert();

        uint256 tokenRawSupply_ = (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT) & X64;
        tokenRawSupply_ = BM.fromBigNumber(tokenRawSupply_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

        // For position type 1 the action data can either be supply or withdraw, hence action data will be decoded accordingly
        (int256 supplyAmount_, address to_) = abi.decode(actionData_, (int256, address));

        if (supplyAmount_ > 0) {
            // User is supplying
            // Get the supply from the user

            _verifyAmountLimits(supplyAmount_);
            
            if (token_ == NATIVE_TOKEN) {
                _msgValue -= uint256(supplyAmount_); // will revert if it goes negative
            }

            uint256 supplyAmountRaw_;
            {
                (uint256 supplyExchangePrice_, ) = LIQUIDITY.operate{value: token_ == NATIVE_TOKEN ? uint256(supplyAmount_) : 0 }(
                    token_, 
                    supplyAmount_, 
                    0, 
                    address(0), 
                    address(0), 
                    abi.encode(MONEY_MARKET_IDENTIFIER, NORMAL_SUPPLY_ACTION_IDENTIFIER)
                );

                // rounded down so protocol is on the winning side
                supplyAmountRaw_ = ((uint256(supplyAmount_) * LC.EXCHANGE_PRICES_PRECISION) - 1) / supplyExchangePrice_;
                if (supplyAmountRaw_ > 0) supplyAmountRaw_ -= 1;
            }

            _checkAndUpdateCapsForNormalSupply(tokenIndex_, supplyAmountRaw_);

            // Update the supply in position data
            tokenRawSupply_ += supplyAmountRaw_;
            tokenRawSupply_ = BM.toBigNumber(tokenRawSupply_, DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN); // rounded down so protocol is on the winning side
            _positionData[nftId_][positionIndex_] =
                (positionData_ & ~(X64 << MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT)) |
                (tokenRawSupply_ << MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT);

            // No need to check the health factor if the user is supplying
            // _checkHf(nftId_, IS_OPERATE);
        } else {
            // User is withdrawing
            (uint256 supplyExchangePrice_, ) = _getExchangePrices(token_);

            // Check if user wants to withdraw all
            uint256 withdrawAmountRaw_;
            if (supplyAmount_ == type(int256).min) {
                withdrawAmountRaw_ = tokenRawSupply_; // Full amount will be withdrawn
                // Calculate the actual withdraw amount
                // rounded down so protocol is on the winning side
                uint256 withdrawAmount_ = ((tokenRawSupply_ * supplyExchangePrice_) - 1) / LC.EXCHANGE_PRICES_PRECISION;
                if (withdrawAmount_ > 0) withdrawAmount_ -= 1;
                supplyAmount_ = -int256(withdrawAmount_);
            } else {
                withdrawAmountRaw_ = (((uint256(-supplyAmount_) * LC.EXCHANGE_PRICES_PRECISION) + 1) / supplyExchangePrice_) + 1; // rounded up so protocol is on the winning side
                if (withdrawAmountRaw_ > tokenRawSupply_) withdrawAmountRaw_ = tokenRawSupply_; // added this check for safety
            }

            _verifyAmountLimits(supplyAmount_);

            _updateStorageForWithdraw(
                nftId_, 
                nftConfig_, 
                positionIndex_, 
                positionData_, 
                tokenIndex_, 
                tokenRawSupply_, 
                withdrawAmountRaw_
            );

            // Check the health factor of the position
            _checkHf(nftId_, IS_OPERATE);

            // Give the withdraw to the user
            LIQUIDITY.operate(token_, supplyAmount_, 0, to_, address(0), abi.encode(MONEY_MARKET_IDENTIFIER, NORMAL_WITHDRAW_ACTION_IDENTIFIER));
        }
    }

    function _processNormalBorrowAction(
        uint256 nftId_,
        uint256 nftConfig_,
        uint256 positionIndex_,
        uint256 positionData_,
        uint256 emode_,
        bytes calldata actionData_
    ) internal {
        uint256 tokenIndex_ = (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_INDEX) & X12;
        // NOTE: This check is not needed because we got the tokenIndex_ from the position data only
        // if (tokenIndex_ >= (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_TOKENS) & X14) revert();

        address token_ = address(uint160(_getTokenConfigs(emode_, tokenIndex_))); // The first 160 bits of the token configs are the token address
        if (token_ == address(0)) revert();

        uint256 tokenRawBorrow_ = (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT) & X64;
        tokenRawBorrow_ = BM.fromBigNumber(tokenRawBorrow_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

        // For it the action data can either be borrow or payback, hence action data will be decoded accordingly
        (int256 borrowAmount_, address to_) = abi.decode(actionData_, (int256, address));

        if (borrowAmount_ > 0) {
            _verifyAmountLimits(borrowAmount_);

            _validateDebtForEmode(emode_, tokenIndex_);

            // User is borrowing
            // Update the borrow on storage
            uint256 borrowAmountRaw_;
            {
                (, uint256 borrowExchangePrice_) = _getExchangePrices(token_);
                borrowAmountRaw_ = (((uint256(borrowAmount_) * LC.EXCHANGE_PRICES_PRECISION) + 1) / borrowExchangePrice_) + 1; // rounded up so protocol is on the winning side
            }

            _checkAndUpdateCapsForNormalBorrow(nftConfig_, tokenIndex_, borrowAmountRaw_);

            // Now we need to update the borrow in position data
            tokenRawBorrow_ += borrowAmountRaw_;
            tokenRawBorrow_ = BM.toBigNumber(tokenRawBorrow_, DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_UP); // rounded up so protocol is on the winning side
            _positionData[nftId_][positionIndex_] =
                (positionData_ & ~(X64 << MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT)) |
                (tokenRawBorrow_ << MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT);

            // Check the health factor of the position
            _checkHf(nftId_, IS_OPERATE);

            // Give the borrow to the user
            LIQUIDITY.operate(token_, 0, borrowAmount_, address(0), to_, abi.encode(MONEY_MARKET_IDENTIFIER, NORMAL_BORROW_ACTION_IDENTIFIER));
        } else {
            // User is paying back
            // Get the pay back from the user
            
            (, uint256 borrowExchangePrice_) = _getExchangePrices(token_);

            // Check if user wants to pay back all
            uint256 paybackAmountRaw_;
            if (borrowAmount_ == type(int256).min) {
                paybackAmountRaw_ = tokenRawBorrow_;
                // Calculate the actual payback amount for liquidity layer
                borrowAmount_ = -int256((((tokenRawBorrow_ * borrowExchangePrice_) + 1) / LC.EXCHANGE_PRICES_PRECISION) + 1); // rounded up so protocol is on the winning side
            } else {
                // rounded down so protocol is on the winning side
                paybackAmountRaw_ = ((uint256(-borrowAmount_) * LC.EXCHANGE_PRICES_PRECISION) - 1) / borrowExchangePrice_;
                if (paybackAmountRaw_ > 0) paybackAmountRaw_ -= 1;
            }

            _verifyAmountLimits(borrowAmount_);

            // Update ethAmount if native token
            uint256 ethAmount_;
            if (token_ == NATIVE_TOKEN) {
                ethAmount_ = uint256(-borrowAmount_);
                _msgValue -= ethAmount_; // will revert if it goes negative
            }

            LIQUIDITY.operate{value: ethAmount_}(
                token_, 
                0, 
                borrowAmount_, 
                address(0), 
                address(0), 
                abi.encode(MONEY_MARKET_IDENTIFIER, NORMAL_PAYBACK_ACTION_IDENTIFIER)
            );

            _updateStorageForPayback(
                nftId_, 
                nftConfig_, 
                positionIndex_, 
                positionData_, 
                tokenIndex_, 
                tokenRawBorrow_, 
                paybackAmountRaw_
            );

            // No need to check the health factor if the user is paying back
            // _checkHf(nftId_, IS_OPERATE);
        }
    }
}