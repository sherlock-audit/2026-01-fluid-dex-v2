// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./helpers.sol";

/// @title FluidMoneyMarketCallbackImplementation
/// @notice Handles callbacks from DexV2 for D3/D4 position operations
/// @dev Called via delegatecall from main contract. Processes deposits, withdrawals, borrows, paybacks, and fee collection.
contract FluidMoneyMarketCallbackImplementation is Helpers {
    // NOTE: All functions in this contract are only callable by specific addresses

    address internal immutable THIS_ADDRESS;

    /// @dev Ensures function is called via delegatecall, not directly
    modifier _onlyDelegateCall() {
        if (address(this) == THIS_ADDRESS) {
            revert();
        }
        _;
    }

    /// @notice Initializes the Callback Module with Liquidity and DexV2 addresses
    /// @param liquidityAddress_ The FluidLiquidity contract address
    /// @param dexV2Address_ The FluidDexV2 contract address
    constructor(address liquidityAddress_, address dexV2Address_) {
        THIS_ADDRESS = address(this);
        LIQUIDITY = IFluidLiquidity(liquidityAddress_);
        DEX_V2 = IFluidDexV2(dexV2Address_);
    }
    
    /// @notice Handles DexV2 callbacks for D3/D4 position operations
    /// @dev Processes:
    ///      - Fee collection (amount0=0 && amount1=0)
    ///      - D3 deposits/withdrawals (smart collateral)
    ///      - D4 borrows/paybacks (smart debt)
    ///      Updates position caps, fee storage, and validates health factor where applicable.
    /// @param data_ Encoded (DexKey, StartOperationParams) containing position and action details
    /// @return returnData_ Encoded result indicating position deletion status and amounts
    function startOperationCallback(bytes calldata data_) external _onlyDelegateCall returns (bytes memory returnData_) {
        if (msg.sender != address(DEX_V2)) revert();
        if (_msgSender == address(0)) revert();

        (DexKey memory dexKey_, StartOperationParams memory s_) = abi.decode(data_, (DexKey, StartOperationParams));

        // For it the action data can either be add or remove liquidity, hence action data will be decoded accordingly
        (int256 amount0_, int256 amount1_) = abi.decode(s_.actionData, (int256, int256));

        if (amount0_ == 0 && amount1_ == 0) {
            // This means that the user is trying to collect fees
            (, , uint256 feeCollectionAmount0_, uint256 feeCollectionAmount1_, address to_) = abi.decode(
                s_.actionData,
                (int256, int256, uint256, uint256, address)
            );

            // First we will collect the accrued fees
            if (s_.positionType == D3_POSITION_TYPE) {
                // Collecting the accrued fees by passing zero withdraw amounts
                returnData_ = DEX_V2.operate(
                    D3_DEX_TYPE, D3_USER_MODULE_IMPLEMENTATION_ID,
                    abi.encodeWithSelector(
                        DEX_V2_WITHDRAW_SELECTOR, 
                        WithdrawParams({
                            dexKey: dexKey_,
                            tickLower: s_.tickLower,
                            tickUpper: s_.tickUpper,
                            positionSalt: s_.positionSalt,
                            amount0: uint256(0),
                            amount1: uint256(0),
                            amount0Min: 0,
                            amount1Min: 0
                        })
                    )
                );

                uint256 feeAccruedToken0_;
                uint256 feeAccruedToken1_;

                {    
                    uint256 amount0Withdrawn_;
                    uint256 amount1Withdrawn_;
                    uint256 liquidityDecrease_;
                    (
                        amount0Withdrawn_, 
                        amount1Withdrawn_, 
                        feeAccruedToken0_, 
                        feeAccruedToken1_, 
                        liquidityDecrease_
                    ) = abi.decode(returnData_, (uint256, uint256, uint256, uint256, uint256));
                    if (!(amount0Withdrawn_ == 0 && amount1Withdrawn_ == 0 && liquidityDecrease_ == 0)) revert();
                }

                bytes32 positionId_ = keccak256(abi.encode(D3_POSITION_TYPE, dexKey_));
                bytes32 dexV2PositionId_ = keccak256(abi.encode(address(this), s_.tickLower, s_.tickUpper, s_.positionSalt));

                (feeCollectionAmount0_, feeCollectionAmount1_) = _updateAndCollectFees(FeeCollectionParams({
                    nftId: s_.nftId,
                    positionId: positionId_,
                    dexV2PositionId: dexV2PositionId_,
                    feeAccruedToken0: feeAccruedToken0_,
                    feeAccruedToken1: feeAccruedToken1_,
                    feeCollectionAmount0: feeCollectionAmount0_,
                    feeCollectionAmount1: feeCollectionAmount1_,
                    isOperate: s_.isOperate
                }));

                if (_isD3D4PositionEmpty(s_.nftId, D3_POSITION_TYPE, dexKey_, s_.tickLower, s_.tickUpper, s_.positionSalt)) {
                    _handleD3PositionDeletion(s_);
                    returnData_ = abi.encode(POSITION_DELETED);
                } else {
                    returnData_ = abi.encode(POSITION_NOT_DELETED);
                }

                _feeSettle(dexKey_.token0, feeAccruedToken0_, feeCollectionAmount0_, to_);
                _feeSettle(dexKey_.token1, feeAccruedToken1_, feeCollectionAmount1_, to_);
            } else if (s_.positionType == D4_POSITION_TYPE) {               
                // Collecting the accrued fees by passing zero payback amounts
                returnData_ = DEX_V2.operate(
                    D4_DEX_TYPE, 
                    D4_USER_MODULE_IMPLEMENTATION_ID, 
                    abi.encodeWithSelector(
                        DEX_V2_PAYBACK_SELECTOR, 
                        PaybackParams({
                            dexKey: dexKey_,
                            tickLower: s_.tickLower,
                            tickUpper: s_.tickUpper,
                            positionSalt: s_.positionSalt,
                            amount0: uint256(0),
                            amount1: uint256(0),
                            amount0Min: 0,
                            amount1Min: 0
                        })
                    )
                );

                uint256 feeAccruedToken0_;
                uint256 feeAccruedToken1_;
                {
                    uint256 amount0Payedback_;
                    uint256 amount1Payedback_;
                    uint256 liquidityDecrease_;
                    (
                        amount0Payedback_, 
                        amount1Payedback_, 
                        feeAccruedToken0_, 
                        feeAccruedToken1_, 
                        liquidityDecrease_
                    ) = abi.decode(returnData_, (uint256, uint256, uint256, uint256, uint256));
                    if (!(amount0Payedback_ == 0 && amount1Payedback_ == 0 && liquidityDecrease_ == 0)) revert();
                }

                bytes32 positionId_ = keccak256(abi.encode(D4_POSITION_TYPE, dexKey_));
                bytes32 dexV2PositionId_ = keccak256(abi.encode(address(this), s_.tickLower, s_.tickUpper, s_.positionSalt));

                (feeCollectionAmount0_, feeCollectionAmount1_) = _updateAndCollectFees(FeeCollectionParams({
                    nftId: s_.nftId,
                    positionId: positionId_,
                    dexV2PositionId: dexV2PositionId_,
                    feeAccruedToken0: feeAccruedToken0_,
                    feeAccruedToken1: feeAccruedToken1_,
                    feeCollectionAmount0: feeCollectionAmount0_,
                    feeCollectionAmount1: feeCollectionAmount1_,
                    isOperate: s_.isOperate
                }));

                if (_isD3D4PositionEmpty(s_.nftId, D4_POSITION_TYPE, dexKey_, s_.tickLower, s_.tickUpper, s_.positionSalt)) {
                    _deletePosition(s_.nftId, s_.nftConfig, s_.positionIndex);
                    returnData_ = abi.encode(POSITION_DELETED);
                } else {
                    returnData_ = abi.encode(POSITION_NOT_DELETED);
                }

                _feeSettle(dexKey_.token0, feeAccruedToken0_, feeCollectionAmount0_, to_);
                _feeSettle(dexKey_.token1, feeAccruedToken1_, feeCollectionAmount1_, to_);
            } else {
                revert();
            }

            // We check hf after fee collection
            if (s_.isOperate) {
                _checkHf(s_.nftId, IS_OPERATE);
            }
        } else {
            (, , uint256 amount0Min_, uint256 amount1Min_, address to_) = abi.decode(
                s_.actionData,
                (int256, int256, uint256, uint256, address)
            );

            if (s_.positionType == D3_POSITION_TYPE) {
                if (amount0_ >= 0 && amount1_ >= 0) {
                    // Deposit
                    if (amount0_ > 0) _verifyAmountLimits(amount0_);
                    if (amount1_ > 0) _verifyAmountLimits(amount1_);

                    returnData_ = DEX_V2.operate(
                        D3_DEX_TYPE, 
                        D3_USER_MODULE_IMPLEMENTATION_ID, 
                        abi.encodeWithSelector(
                            DEX_V2_DEPOSIT_SELECTOR, 
                            DepositParams({
                                dexKey: dexKey_,
                                tickLower: s_.tickLower,
                                tickUpper: s_.tickUpper,
                                positionSalt: s_.positionSalt,
                                amount0: uint256(amount0_),
                                amount1: uint256(amount1_),
                                amount0Min: amount0Min_,
                                amount1Min: amount1Min_
                            })
                        )
                    );

                    bytes32 positionId_;
                    uint256 liquidityIncrease_;
                    {
                        uint256 feeAccruedToken0_;
                        uint256 feeAccruedToken1_;
                        {
                            uint256 amount0Supplied_;
                            uint256 amount1Supplied_;
                            (
                                amount0Supplied_, 
                                amount1Supplied_, 
                                feeAccruedToken0_, 
                                feeAccruedToken1_, 
                                liquidityIncrease_
                            ) = abi.decode(returnData_, (uint256, uint256, uint256, uint256, uint256));

                            _depositSettle(dexKey_.token0, amount0Supplied_, feeAccruedToken0_, to_);
                            _depositSettle(dexKey_.token1, amount1Supplied_, feeAccruedToken1_, to_);
                        }

                        positionId_ = keccak256(abi.encode(D3_POSITION_TYPE, dexKey_));

                        _updateFeeStoredWithNewFeeAccrued(
                            s_.nftId, 
                            positionId_, 
                            keccak256(abi.encode(address(this), s_.tickLower, s_.tickUpper, s_.positionSalt)), 
                            feeAccruedToken0_, 
                            feeAccruedToken1_
                        );
                    }

                    _checkAndUpdateCapsForD3D4LiquidityIncrease(
                        positionId_,
                        D3_DEX_TYPE,
                        dexKey_,
                        s_.tickLower, 
                        s_.tickUpper, 
                        liquidityIncrease_, 
                        s_.permissionlessTokens
                    );

                    returnData_ = abi.encode(POSITION_NOT_DELETED);

                    // NOTE: We dont check hf after deposits
                } else if (amount0_ <= 0 && amount1_ <= 0) {
                    // Withdraw
                    if (s_.isOperate) {
                        if (amount0_ < 0) _verifyAmountLimits(amount0_);
                        if (amount1_ < 0) _verifyAmountLimits(amount1_);
                    }

                    returnData_ = DEX_V2.operate(
                        D3_DEX_TYPE, 
                        D3_USER_MODULE_IMPLEMENTATION_ID, 
                        abi.encodeWithSelector(
                            DEX_V2_WITHDRAW_SELECTOR, 
                            WithdrawParams({
                                dexKey: dexKey_,
                                tickLower: s_.tickLower,
                                tickUpper: s_.tickUpper,
                                positionSalt: s_.positionSalt,
                                amount0: uint256(-amount0_),
                                amount1: uint256(-amount1_),
                                amount0Min: amount0Min_,
                                amount1Min: amount1Min_
                            })
                        )
                    );

                    {
                        uint256 feeAccruedToken0_;
                        uint256 feeAccruedToken1_;
                        uint256 liquidityDecrease_;
                        {
                            uint256 amount0Withdrawn_;
                            uint256 amount1Withdrawn_;
                            (
                                amount0Withdrawn_, 
                                amount1Withdrawn_, 
                                feeAccruedToken0_, 
                                feeAccruedToken1_, 
                                liquidityDecrease_
                            ) = abi.decode(returnData_, (uint256, uint256, uint256, uint256, uint256));

                            _withdrawSettle(dexKey_.token0, amount0Withdrawn_, feeAccruedToken0_, to_);
                            _withdrawSettle(dexKey_.token1, amount1Withdrawn_, feeAccruedToken1_, to_);
                        }

                        bytes32 positionId_ = keccak256(abi.encode(D3_POSITION_TYPE, dexKey_));

                        _updateFeeStoredWithNewFeeAccrued(
                            s_.nftId, 
                            positionId_, 
                            keccak256(abi.encode(address(this), s_.tickLower, s_.tickUpper, s_.positionSalt)), 
                            feeAccruedToken0_, 
                            feeAccruedToken1_
                        );

                        _updatePositionCapsForD3D4LiquidityDecrease(positionId_, s_.tickLower, s_.tickUpper, liquidityDecrease_);
                    }

                    // Decoding here to get amount0Withdrawn_ and amount1Withdrawn_ because doing it above was giving stack too deep
                    (uint256 amount0Withdrawn_, uint256 amount1Withdrawn_) = abi.decode(returnData_, (uint256, uint256));
                    
                    if (_isD3D4PositionEmpty(s_.nftId, D3_POSITION_TYPE, dexKey_, s_.tickLower, s_.tickUpper, s_.positionSalt)) {
                        _handleD3PositionDeletion(s_);
                        returnData_ = abi.encode(POSITION_DELETED, amount0Withdrawn_, amount1Withdrawn_);
                    } else {
                        returnData_ = abi.encode(POSITION_NOT_DELETED, amount0Withdrawn_, amount1Withdrawn_);
                    }

                    // We check hf after withdrawals
                    if (s_.isOperate) {
                        _checkHf(s_.nftId, IS_OPERATE);
                    }
                } else {
                    revert();
                }
            } else if (s_.positionType == D4_POSITION_TYPE) {
                if (amount0_ >= 0 && amount1_ >= 0) {
                    // Borrow
                    if (amount0_ > 0) _verifyAmountLimits(amount0_);
                    if (amount1_ > 0) _verifyAmountLimits(amount1_);

                    // Check if the position's emode allows taking debt of both the tokens
                    _validateDebtForEmode(s_.emode, s_.token0Index);
                    _validateDebtForEmode(s_.emode, s_.token1Index);

                    returnData_ = DEX_V2.operate(
                        D4_DEX_TYPE, 
                        D4_USER_MODULE_IMPLEMENTATION_ID, 
                        abi.encodeWithSelector(
                            DEX_V2_BORROW_SELECTOR, 
                            BorrowParams({
                                dexKey: dexKey_,
                                tickLower: s_.tickLower,
                                tickUpper: s_.tickUpper,
                                positionSalt: s_.positionSalt,
                                amount0: uint256(amount0_),
                                amount1: uint256(amount1_),
                                amount0Min: amount0Min_,
                                amount1Min: amount1Min_
                            })
                        )
                    );

                    uint256 liquidityIncrease_;
                    uint256 feeAccruedToken0_;
                    uint256 feeAccruedToken1_;
                    {
                        uint256 amount0Borrowed_;
                        uint256 amount1Borrowed_;
                        (
                            amount0Borrowed_, 
                            amount1Borrowed_, 
                            feeAccruedToken0_, 
                            feeAccruedToken1_, 
                            liquidityIncrease_
                        ) = abi.decode(returnData_, (uint256, uint256, uint256, uint256, uint256));

                        // Settle is happening before below storage updates, we put it here because of stack to deep 
                        // This should not an issue because we have reentrancy checks and there is not callback also
                        _borrowSettle(dexKey_.token0, amount0Borrowed_, feeAccruedToken0_, to_);
                        _borrowSettle(dexKey_.token1, amount1Borrowed_, feeAccruedToken1_, to_);
                    }

                    // NOTE: We are calculating positionId twice below to prevent stack too deep
        
                    _updateFeeStoredWithNewFeeAccrued(
                        s_.nftId, 
                        keccak256(abi.encode(D4_POSITION_TYPE, dexKey_)), 
                        keccak256(abi.encode(address(this), s_.tickLower, s_.tickUpper, s_.positionSalt)), 
                        feeAccruedToken0_, 
                        feeAccruedToken1_
                    );

                    _checkAndUpdateCapsForD3D4LiquidityIncrease(
                        keccak256(abi.encode(D4_POSITION_TYPE, dexKey_)), 
                        D4_DEX_TYPE,
                        dexKey_, 
                        s_.tickLower, 
                        s_.tickUpper, 
                        liquidityIncrease_, 
                        s_.permissionlessTokens
                    );

                    // We check hf after borrows
                    if (s_.isOperate) {
                        _checkHf(s_.nftId, IS_OPERATE);
                    }

                    returnData_ = abi.encode(POSITION_NOT_DELETED);
                } else if (amount0_ <= 0 && amount1_ <= 0) {
                    // Payback

                    if (s_.isOperate) {
                        if (amount0_ < 0) _verifyAmountLimits(amount0_);
                        if (amount1_ < 0) _verifyAmountLimits(amount1_);
                    }

                    returnData_ = DEX_V2.operate(
                        D4_DEX_TYPE, 
                        D4_USER_MODULE_IMPLEMENTATION_ID, 
                        abi.encodeWithSelector(
                            DEX_V2_PAYBACK_SELECTOR, 
                            PaybackParams({
                                dexKey: dexKey_,
                                tickLower: s_.tickLower,
                                tickUpper: s_.tickUpper,
                                positionSalt: s_.positionSalt,
                                amount0: uint256(-amount0_),
                                amount1: uint256(-amount1_),
                                amount0Min: amount0Min_,
                                amount1Min: amount1Min_
                            })
                        )
                    );

                    {
                        uint256 feeAccruedToken0_;
                        uint256 feeAccruedToken1_;
                        uint256 liquidityDecrease_;
                        {
                            uint256 amount0Payedback_;
                            uint256 amount1Payedback_;
                            (
                                amount0Payedback_, 
                                amount1Payedback_, 
                                feeAccruedToken0_, 
                                feeAccruedToken1_, 
                                liquidityDecrease_
                            ) = abi.decode(returnData_, (uint256, uint256, uint256, uint256, uint256));

                            _paybackSettle(dexKey_.token0, amount0Payedback_, feeAccruedToken0_, to_);
                            _paybackSettle(dexKey_.token1, amount1Payedback_, feeAccruedToken1_, to_);
                        }

                        {
                            bytes32 positionId_ = keccak256(abi.encode(D4_POSITION_TYPE, dexKey_));

                            _updateFeeStoredWithNewFeeAccrued(
                                s_.nftId, 
                                positionId_,
                                keccak256(abi.encode(address(this), s_.tickLower, s_.tickUpper, s_.positionSalt)), 
                                feeAccruedToken0_, 
                                feeAccruedToken1_
                            );

                            _updatePositionCapsForD3D4LiquidityDecrease(positionId_, s_.tickLower, s_.tickUpper, liquidityDecrease_);
                        }
                    }

                    // Decoding here again to get amount0Payedback_ and amount1Payedback_ because doing it above was giving stack too deep
                    (uint256 amount0Payedback_, uint256 amount1Payedback_) = abi.decode(returnData_, (uint256, uint256));

                    if (_isD3D4PositionEmpty(s_.nftId, D4_POSITION_TYPE, dexKey_, s_.tickLower, s_.tickUpper, s_.positionSalt)) {
                        _deletePosition(s_.nftId, s_.nftConfig, s_.positionIndex);
                        returnData_ = abi.encode(POSITION_DELETED, amount0Payedback_, amount1Payedback_);
                    } else {
                        returnData_ = abi.encode(POSITION_NOT_DELETED, amount0Payedback_, amount1Payedback_);
                    }
                    // NOTE: We dont check hf after paybacks
                } else {
                    revert();
                }
            } else {
                revert();
            }
        }
    }
}