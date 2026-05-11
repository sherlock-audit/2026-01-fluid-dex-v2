// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./adminModule.sol";

/// @title FluidDexV2
/// @notice Main entry point for Fluid DexV2 protocol operations
/// @dev Supports D3 (smart collateral) and D4 (smart debt) DEX types with concentrated liquidity positions.
///      Operations must be wrapped in startOperation/callback pattern for atomic multi-step transactions.
contract FluidDexV2 is DexV2AdminModule {
    /// @notice Initializes the DexV2 with Liquidity contract address
    /// @param liquidity_ The FluidLiquidity contract address for token operations
    constructor(address liquidity_) {
        LIQUIDITY = IFluidLiquidity(liquidity_);
    }

    /// @notice Starts an operation
    /// @param data_ The data to pass to the callback
    /// @return result_ The result of the operation
    function startOperation(bytes calldata data_) external returns (bytes memory result_) {
        // Activate the operation (also checks if operation is already active, reverts if it is)
        OC.activateOperation();

        // Call the callback on the sender to perform operations
        result_ = IDexV2Callbacks(msg.sender).startOperationCallback(data_);

        // Ensure all pending transfers are cleared before completing
        PT.requireAllPendingTransfersCleared();

        // Deactivate the operation
        OC.deactivateOperation();

        return result_;
    }

    /// @notice Routes an operation to a specific DEX type implementation module
    /// @dev Only callable after startOperation. Routes to D3/D4 swap, user, or controller modules.
    /// @param dexType_ The DEX type (3 = D3 smart collateral, 4 = D4 smart debt)
    /// @param implementationId_ The module ID within the DEX type (1=swap, 2=user, 3=controller)
    /// @param data_ Encoded function call data for the target module
    /// @return returnData_ The result from the module execution
    function operate(uint256 dexType_, uint256 implementationId_, bytes memory data_) external _onlyAfterOperationStarted returns (bytes memory returnData_) {
        address dexImplementationAddress_;
        if (dexType_ == 3) {
            if (implementationId_ == D3_SWAP_MODULE_IMPLEMENTATION_ID) dexImplementationAddress_ = D3_SWAP_MODULE_IMPLEMENTATION;
            else if (implementationId_ == D3_USER_MODULE_IMPLEMENTATION_ID) dexImplementationAddress_ = D3_USER_MODULE_IMPLEMENTATION;
            else if (implementationId_ == D3_CONTROLLER_MODULE_IMPLEMENTATION_ID) dexImplementationAddress_ = D3_CONTROLLER_MODULE_IMPLEMENTATION;
            else revert FluidDexV2Error(ErrorTypes.DexV2Main__InvalidDexTypeOrImplementationId);
        } else if (dexType_ == 4) {
            if (implementationId_ == D4_SWAP_MODULE_IMPLEMENTATION_ID) dexImplementationAddress_ = D4_SWAP_MODULE_IMPLEMENTATION;
            else if (implementationId_ == D4_USER_MODULE_IMPLEMENTATION_ID) dexImplementationAddress_ = D4_USER_MODULE_IMPLEMENTATION;
            else if (implementationId_ == D4_CONTROLLER_MODULE_IMPLEMENTATION_ID) dexImplementationAddress_ = D4_CONTROLLER_MODULE_IMPLEMENTATION;
            else revert FluidDexV2Error(ErrorTypes.DexV2Main__InvalidDexTypeOrImplementationId);
        } else {
            revert FluidDexV2Error(ErrorTypes.DexV2Main__InvalidDexTypeOrImplementationId);
        }

        returnData_ = _spell(dexImplementationAddress_, data_);

        emit LogOperate(msg.sender, dexType_, implementationId_);
    }

    /// @notice Settles pending token transfers between user and protocol
    /// @dev Only callable after startOperation. Handles supply, borrow, and stored amounts.
    ///      Use type(int128).max/min to clear entire pending supply/borrow.
    ///      Optimizes by skipping Liquidity layer when possible (if contract has sufficient balance).
    /// @param token_ The token address to settle
    /// @param supplyAmount_ Net supply amount (positive = deposit, negative = withdraw)
    /// @param borrowAmount_ Net borrow amount (positive = borrow, negative = payback)
    /// @param storeAmount_ Amount to store/unstore in contract
    /// @param to_ Recipient for outgoing tokens (defaults to msg.sender if zero)
    /// @param isCallback_ If true, uses dexCallback for token transfers instead of transferFrom
    function settle(
        address token_,
        int256 supplyAmount_,
        int256 borrowAmount_,
        int256 storeAmount_,
        address to_,
        bool isCallback_
    ) external payable _onlyAfterOperationStarted _reentrancyLock {
        if ((supplyAmount_) == 0 && (borrowAmount_ == 0) && (storeAmount_ == 0)) {
            revert FluidDexV2Error(ErrorTypes.DexV2Main__OperateAmountsZero);
        }
        if (
            supplyAmount_ < type(int128).min ||
            supplyAmount_ > type(int128).max ||
            borrowAmount_ < type(int128).min ||
            borrowAmount_ > type(int128).max ||
            storeAmount_ < type(int128).min ||
            storeAmount_ > type(int128).max
        ) {
            revert FluidDexV2Error(ErrorTypes.DexV2Main__OperateAmountOutOfBounds);
        }

        // If the supply amount is passed as type(int128).max or type(int128).min, then that means they user wants to clear entire pending supply
        if (supplyAmount_ == type(int128).max || supplyAmount_ == type(int128).min) {
            supplyAmount_ = PT.getPendingSupply(msg.sender, token_);
        }
        // If the borrow amount is passed as type(int128).max or type(int128).min, then that means they user wants to clear entire pending borrow
        if (borrowAmount_ == type(int128).max || borrowAmount_ == type(int128).min) {
            borrowAmount_ = PT.getPendingBorrow(msg.sender, token_);
        }
        // If the store amount is passed as type(int128).max or type(int128).min, then that means the user wants to use the stored amount to handle things and hence skip any token transfers
        if (storeAmount_ == type(int128).max || storeAmount_ == type(int128).min) {
            storeAmount_ = borrowAmount_ - supplyAmount_;
        }
        // If the to_ address is not set, then set it to the msg.sender
        if (to_ == address(0)) {
            to_ = msg.sender;
        }

        // there should not be msg.value if the token is not the native token
        if (token_ != NATIVE_TOKEN && msg.value > 0) {
            revert FluidDexV2Error(ErrorTypes.DexV2Main__MsgValueForNonNativeToken);
        }

        int256 netSupplyAmount_ = supplyAmount_ + storeAmount_; // amount is stored as supply on liquidity
        int256 netAmount_ = netSupplyAmount_ - borrowAmount_; // positive means user is paying tokens in net, negative means user is receiving tokens in net

        // if protocol is paying tokens in net, then we need to update our accounting before paying the user
        // this is done to mitigate any risks of reentrancy attacks
        if (netAmount_ <= 0) _updateSettledAmountsOnStorage(token_, supplyAmount_, borrowAmount_, storeAmount_);

        uint256 tokenBalance_ = token_ == NATIVE_TOKEN ? (address(this).balance - msg.value) : IERC20(token_).balanceOf(address(this));

        if (netAmount_ > 0 && uint256(netAmount_) < tokenBalance_) {
            // Net tokens coming in from user and they are less than the token balance hence we can skip liquidity layer interactions
            // We only skip the liquidity layer interactions if the amount coming in is not going to make the amount in the contract more than double of what it is right now
            // One can call settle in parts to bypass this condition but that will cause more gas as transfers will happen twice or more
            if (token_ == NATIVE_TOKEN) {
                unchecked {
                    if (msg.value > uint256(netAmount_)) SafeTransfer.safeTransferNative(msg.sender, msg.value - uint256(netAmount_));
                    else if (msg.value < uint256(netAmount_)) {
                        revert FluidDexV2Error(ErrorTypes.DexV2Main__MsgValueMismatch);
                    }
                }
            } else {
                if (isCallback_) {
                    IDexV2Callbacks(msg.sender).dexCallback(token_, address(this), uint256(netAmount_));
                    if ((IERC20(token_).balanceOf(address(this)) - tokenBalance_) < uint256(netAmount_)) {
                        revert FluidDexV2Error(ErrorTypes.DexV2Main__BalanceCheckFailed);
                    }
                } else SafeTransfer.safeTransferFrom(token_, msg.sender, address(this), uint256(netAmount_));
            }

            // Net amount > 0; net tokens coming in from the user, hence we do any storage updates after the money comes in
            if (borrowAmount_ != 0) _unaccountedBorrowAmount[BASE_SLOT][token_] += borrowAmount_;
        } else if (netAmount_ < 0 && uint256(-netAmount_) < tokenBalance_) {
            // Net amount < 0; net tokens going out to the user, hence we do any storage updates before the money goes out
            if (borrowAmount_ != 0) _unaccountedBorrowAmount[BASE_SLOT][token_] += borrowAmount_;

            // Net tokens going out to user and they are less than the token balance hence we can skip liquidity layer interactions
            if (msg.value > 0) SafeTransfer.safeTransferNative(msg.sender, msg.value);
            unchecked {
                if (token_ == NATIVE_TOKEN) SafeTransfer.safeTransferNative(to_, uint256(-netAmount_));
                else SafeTransfer.safeTransfer(token_, to_, uint256(-netAmount_));
            }
        } else if (!(netSupplyAmount_ == 0 && borrowAmount_ == 0)) {
            if (!_callLiquidityLayer(token_, netSupplyAmount_, borrowAmount_, to_, isCallback_)) {
                // Fallback when liquidity layer fails
                if (netAmount_ > 0) {
                    // Net tokens coming in from user - take funds directly into dex
                    if (token_ == NATIVE_TOKEN) {
                        // NOTE: This must have already happened in _callLiquidityLayer function
                        // unchecked {
                        //     if (msg.value > uint256(netAmount_)) SafeTransfer.safeTransferNative(msg.sender, msg.value - uint256(netAmount_));
                        //     else if (msg.value < uint256(netAmount_)) {
                        //         revert FluidDexV2Error(ErrorTypes.DexV2Main__MsgValueMismatch);
                        //     }
                        // }
                    } else {
                        if (isCallback_) {
                            IDexV2Callbacks(msg.sender).dexCallback(token_, address(this), uint256(netAmount_));
                            if ((IERC20(token_).balanceOf(address(this)) - tokenBalance_) < uint256(netAmount_)) {
                                revert FluidDexV2Error(ErrorTypes.DexV2Main__BalanceCheckFailed);
                            }
                        } else SafeTransfer.safeTransferFrom(token_, msg.sender, address(this), uint256(netAmount_));
                    }
                    // Update borrow accounting
                    if (borrowAmount_ != 0) _unaccountedBorrowAmount[BASE_SLOT][token_] += borrowAmount_;
                } else if (netAmount_ < 0) {
                    // Net tokens going out to user - skip the transfer
                    if (borrowAmount_ != 0) _unaccountedBorrowAmount[BASE_SLOT][token_] += borrowAmount_;

                    // NOTE: This must have already happened in _callLiquidityLayer function
                    // if (msg.value > 0) SafeTransfer.safeTransferNative(msg.sender, msg.value);

                    // Since the call is failing we'll skip the transfer and store the amount in the contract so the user can withdraw later
                    _userStoredTokenAmount[BASE_SLOT][to_][token_] += uint256(-netAmount_);

                    // emitting event so any backend tracking to calculate interest revenue works fine
                    // using address(0) as msg.sender to differentiate this specific case
                    emit LogSettle(address(0), token_, 0, 0, -netAmount_, to_);
                } else {
                    // netAmount_ == 0: No net token flow - just update accounting
                    if (borrowAmount_ != 0) _unaccountedBorrowAmount[BASE_SLOT][token_] += borrowAmount_;

                    // NOTE: This must have already happened in _callLiquidityLayer function
                    // if (msg.value > 0) SafeTransfer.safeTransferNative(msg.sender, msg.value);
                }
            }
        }

        // if protocol is receiving tokens in net, then we need to update our accounting after receiving tokens from the user
        // this is done to mitigate any risks of reentrancy attacks
        if (netAmount_ > 0) _updateSettledAmountsOnStorage(token_, supplyAmount_, borrowAmount_, storeAmount_);

        emit LogSettle(msg.sender, token_, supplyAmount_, borrowAmount_, storeAmount_, to_);
    }

    /// @dev THE BELOW FUNCTIONS DONT HAVE _onlyAfterOperationStarted MODIFIER

    /// @notice Routes an admin operation to a specific DEX type admin implementation
    /// @dev Only callable by authorized addresses. Does NOT require startOperation wrapper.
    /// @param dexType_ The DEX type (3 = D3, 4 = D4)
    /// @param implementationId_ The admin module implementation ID
    /// @param data_ Encoded function call data for the admin module
    /// @return returnData_ The result from the admin module execution
    function operateAdmin(uint256 dexType_, uint256 implementationId_, bytes memory data_) external onlyAuths returns (bytes memory returnData_) {
        address dexAdminImplementationAddress_ = _dexTypeToAdminImplementation[BASE_SLOT][dexType_][implementationId_];

        if (dexAdminImplementationAddress_ == address(0)) {
            revert FluidDexV2Error(ErrorTypes.DexV2Main__AdminImplementationNotSet);
        }
        bool success_;
        (success_, returnData_) = dexAdminImplementationAddress_.delegatecall(data_);
        if (!success_) {
            assembly {
                revert(add(returnData_, 32), mload(returnData_))
            }
        }

        emit LogOperateAdmin(msg.sender, dexType_, implementationId_);
    }

    /// @notice Callback from Liquidity layer for token transfers during settle/rebalance
    /// @dev Only callable by the LIQUIDITY contract. Handles SETTLE and REBALANCE action types.
    /// @param token_ The token address being transferred
    /// @param amount_ The minimum amount required by Liquidity
    /// @param data_ Encoded (dexIdentifier, actionIdentifier, ...) with action-specific params
    function liquidityCallback(address token_, uint amount_, bytes calldata data_) external {
        if (msg.sender != address(LIQUIDITY)) {
            revert FluidDexV2Error(ErrorTypes.DexV2Main__UnauthorizedLiquidityCallback);
        }

        (
            bytes32 dexIdentifier_,
            bytes32 actionIdentifier_
        ) = abi.decode(data_, (bytes32, bytes32));

        if (dexIdentifier_ != DEXV2_IDENTIFIER) {
            revert FluidDexV2Error(ErrorTypes.DexV2Main__InvalidDexIdentifier);
        }

        if (actionIdentifier_ == SETTLE_ACTION_IDENTIFIER) {
            (,, uint256 amountToSend_, bool isCallback_, address from_) = abi.decode(data_, (bytes32, bytes32, uint256, bool, address));
            if (amountToSend_ < amount_) {
                revert FluidDexV2Error(ErrorTypes.DexV2Main__AmountToSendInsufficient);
            }

            if (isCallback_) IDexV2Callbacks(from_).dexCallback(token_, address(LIQUIDITY), amountToSend_);
            else SafeTransfer.safeTransferFrom(token_, from_, address(LIQUIDITY), amountToSend_);
        } else if (actionIdentifier_ == REBALANCE_ACTION_IDENTIFIER) {
            if (token_ == NATIVE_TOKEN) {
                // this case should be impossible from LL side, but revert just to be sure
                revert FluidDexV2Error(ErrorTypes.DexV2Main__NativeTokenRequiresMsgValue);
            } else SafeTransfer.safeTransfer(token_, address(LIQUIDITY), amount_);
        } else {
            revert FluidDexV2Error(ErrorTypes.DexV2Main__InvalidActionIdentifier);
        }
    }

    /// @notice Reads a uint256 value from a specific storage slot
    /// @param slot_ The storage slot to read from
    /// @return result_ The value stored at the specified slot
    function readFromStorage(bytes32 slot_) public view returns (uint256 result_) {
        assembly {
            result_ := sload(slot_) // read value from the storage slot
        }
    }

    /// @notice Reads a uint256 value from a specific transient storage slot
    /// @param slot_ The transient storage slot to read from
    /// @return result_ The value stored at the specified transient slot
    function readFromTransientStorage(bytes32 slot_) public view returns (uint256 result_) {
        assembly {
            result_ := tload(slot_) // read value from the transient storage slot
        }
    }

    /// @notice Receive function to accept native token transfers
    receive() external payable {}
}
