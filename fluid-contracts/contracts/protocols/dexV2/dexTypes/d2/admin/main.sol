// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

// TODO
// import { ErrorTypes } from "../../errorTypes.sol"; // TODO: update this and reverts
// import { Error } from "../../error.sol"; // TODO: update this and reverts

// TODO: Check admin module again
// TODO: Add pool initialization function

import "./events.sol";

import { SafeTransfer } from "../../../../../libraries/safeTransfer.sol";
import { AddressCalcs } from "../../../../../libraries/addressCalcs.sol";
import { DexSlotsLink } from "../../../../../libraries/dexSlotsLink.sol";

/// @notice Fluid Dex protocol Admin Module contract.
///         Implements admin related methods to set pool configs
///         Methods are limited to be called via delegateCall only. Dex CoreModule ("DexT1" contract)
///         is expected to call the methods implemented here after checking the msg.sender is authorized.
contract FluidDexV2D2Admin is CommonImportD2Other {
    using BigMathMinified for uint256;

    constructor(address liquidityAddress_, address deployerContract_) CommonImmutableVariables(liquidityAddress_, deployerContract_) {}

    modifier _onlyDelegateCall() {
        // also indirectly checked by `_check` because pool can never be initialized as long as the initialize method
        // is delegate call only, but just to be sure on Admin logic we add the modifier everywhere nonetheless.
        if (address(this) == THIS_CONTRACT) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__OnlyDelegateCallAllowed);
        }
        _;
    }

    function _check(bytes32 dexId_) internal view {
        if ((_dexVariables2[DEX_TYPE][dexId_] & 1) == 0) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__PoolNotInitialized);
        }
    }

    /// @dev checks that `value_` address is a contract (which includes address zero check) or native address
    function _checkIsContractOrNativeAddress(address value_) internal view {
        if (value_.code.length == 0 && value_ != NATIVE_TOKEN) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__AddressNotAContract);
        }
    }

    /// @dev checks that `value_` address is a contract (which includes address zero check)
    function _checkIsContract(address value_) internal view {
        if (value_.code.length == 0) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__AddressNotAContract);
        }
    }

    /// @param fee_ in 4 decimals, 10000 = 1%
    /// @param revenueCut_ in 4 decimals, 100000 = 10%, 10% cut on fee_, so if fee is 1% and cut is 10% then cut in swap amount will be 10% of 1% = 0.1%
    function updateFeeAndRevenueCut(DexKey memory dexKey_, uint fee_, uint revenueCut_) public _onlyDelegateCall {
        bytes32 dexId_ = keccak256(abi.encode(dexKey_));
        _check(dexId_);

        // cut is an integer in storage slot which is more than enough
        // but from UI we are allowing to send in 4 decimals to maintain consistency & avoid human error in future
        if (revenueCut_ != 0 && revenueCut_ < FOUR_DECIMALS) {
            // human input error. should send 0 for wanting 0, not 0 because of precision reduction.
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
        }

        revenueCut_ = revenueCut_ / FOUR_DECIMALS;

        if (fee_ > FIVE_DECIMALS || revenueCut_ > TWO_DECIMALS) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
        }

        _dexVariables2[DEX_TYPE][dexId_] =
            (_dexVariables2[DEX_TYPE][dexId_] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC000003) |
            (fee_ << 2) |
            (revenueCut_ << 19);

        emit LogUpdateFeeAndRevenueCut(DEX_TYPE, dexId_, fee_, revenueCut_ * FOUR_DECIMALS);
    }

    /// @param upperPercent_ in 4 decimals, 10000 = 1%
    /// @param lowerPercent_ in 4 decimals, 10000 = 1%
    /// @param shiftTime_ in secs, in how much time the upper percent configs change should be fully done
    function updateRangePercents(DexKey memory dexKey_, uint upperPercent_, uint lowerPercent_, uint shiftTime_) public _onlyDelegateCall {
        bytes32 dexId_ = keccak256(abi.encode(dexKey_));
        _check(dexId_);

        uint dexVariables2_ = _dexVariables2[DEX_TYPE][dexId_];
        if (
            (upperPercent_ > (SIX_DECIMALS - FOUR_DECIMALS)) || // capping range to 99%.
            (lowerPercent_ > (SIX_DECIMALS - FOUR_DECIMALS)) || // capping range to 99%.
            (upperPercent_ == 0) ||
            (lowerPercent_ == 0) ||
            (shiftTime_ > X20) ||
            (((dexVariables2_ >> 26) & 1) == 1) // if last shift is still active then don't allow a newer shift
        ) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
        }

        _dexVariables2[DEX_TYPE][dexId_] =
            (dexVariables2_ & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF80000000003FFFFFF) |
            (uint((shiftTime_ > 0) ? 1 : 0) << 26) |
            (upperPercent_ << 27) |
            (lowerPercent_ << 47);

        uint oldUpperPercent_ = (dexVariables2_ >> 27) & X20;
        uint oldLowerPercent_ = (dexVariables2_ >> 47) & X20;

        if (shiftTime_ > 0) {
            _rangeAndThresholdShift[DEX_TYPE][dexId_] =
                (_rangeAndThresholdShift[DEX_TYPE][dexId_] & (X128 << 128)) | // making first 128 bits 0
                oldUpperPercent_ |
                (oldLowerPercent_ << 20) |
                (shiftTime_ << 40) |
                (block.timestamp << 60);
        }
        // Note _rangeShift is reset when the previous shift is fully completed, which is forced to have happened through if check above

        emit LogUpdateRangePercents(DEX_TYPE, dexId_, upperPercent_, lowerPercent_, shiftTime_);
    }

    /// @param upperThresholdPercent_ in 4 decimals, 10000 = 1%
    /// @param lowerThresholdPercent_ in 4 decimals, 10000 = 1%
    /// @param thresholdShiftTime_ in secs, in how much time the threshold percent should take to shift the ranges
    /// @param shiftTime_ in secs, in how much time the upper config changes should be fully done.
    function updateThresholdPercent(
        DexKey memory dexKey_,
        uint upperThresholdPercent_,
        uint lowerThresholdPercent_,
        uint thresholdShiftTime_,
        uint shiftTime_
    ) public _onlyDelegateCall {
        bytes32 dexId_ = keccak256(abi.encode(dexKey_));
        _check(dexId_);

        uint dexVariables2_ = _dexVariables2[DEX_TYPE][dexId_];

        // thresholds are with 0.1% precision, hence removing last 3 decimals.
        // we are allowing to send in 4 decimals to maintain consistency with other params
        upperThresholdPercent_ = upperThresholdPercent_ / THREE_DECIMALS;
        lowerThresholdPercent_ = lowerThresholdPercent_ / THREE_DECIMALS;
        if (
            (upperThresholdPercent_ > THREE_DECIMALS) ||
            (lowerThresholdPercent_ > THREE_DECIMALS) ||
            (thresholdShiftTime_ == 0) ||
            (thresholdShiftTime_ > X24) ||
            ((upperThresholdPercent_ == 0) && (lowerThresholdPercent_ > 0)) ||
            ((upperThresholdPercent_ > 0) && (lowerThresholdPercent_ == 0)) ||
            (shiftTime_ > X20) ||
            (((dexVariables2_ >> 67) & 1) == 1) // if last shift is still active then don't allow a newer shift
        ) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
        }

        _dexVariables2[DEX_TYPE][dexId_] =
            (dexVariables2_ & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000000000007FFFFFFFFFFFFFFFF) |
            (uint((shiftTime_ > 0) ? 1 : 0) << 67) |
            (upperThresholdPercent_ << 68) |
            (lowerThresholdPercent_ << 78) |
            (thresholdShiftTime_ << 88);

        uint oldUpperThresholdPercent_ = (dexVariables2_ >> 68) & X10;
        uint oldLowerThresholdPercent_ = (dexVariables2_ >> 78) & X10;
        uint oldThresholdTime_ = (dexVariables2_ >> 88) & X24;

        if (shiftTime_ > 0) {
            uint256 newThresholdShift_ = oldUpperThresholdPercent_ |
                (oldLowerThresholdPercent_ << 20) |
                (shiftTime_ << 40) |
                (block.timestamp << 60) |
                (oldThresholdTime_ << 93);

            _rangeAndThresholdShift[DEX_TYPE][dexId_] =
                (_rangeAndThresholdShift[DEX_TYPE][dexId_] & ~(X128 << 128)) | // making last 128 bits 0
                (newThresholdShift_ << 128);
        }
        // Note _thresholdShift is reset when the previous shift is fully completed, which is forced to have happened through if check above

        emit LogUpdateThresholdPercent(
            DEX_TYPE,
            dexId_,
            upperThresholdPercent_ * THREE_DECIMALS,
            lowerThresholdPercent_ * THREE_DECIMALS,
            thresholdShiftTime_,
            shiftTime_
        );
    }

    /// @dev we are storing uint nonce from which we will calculate the contract address, to store an address we need 160 bits
    /// which is quite a lot of storage slot
    /// @param centerPriceAddress_ nonce < X30, this nonce will be used to calculate contract address
    function updateCenterPriceAddress(DexKey memory dexKey_, uint centerPriceAddress_, uint percent_, uint time_) public _onlyDelegateCall {
        bytes32 dexId_ = keccak256(abi.encode(dexKey_));
        _check(dexId_);

        if ((centerPriceAddress_ > X30) || (percent_ == 0) || (percent_ > X20) || (time_ == 0) || (time_ > X20)) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
        }

        if (centerPriceAddress_ > 0) {
            address centerPrice_ = AddressCalcs.addressCalc(DEPLOYER_CONTRACT, centerPriceAddress_);
            _checkIsContract(centerPrice_);
            // note: if address is made 0 then as well in the last swap currentPrice is updated on storage, so code will start using that automatically
            _dexVariables2[DEX_TYPE][dexId_] =
                (_dexVariables2[DEX_TYPE][dexId_] & 0xFeFFFFFFFFFFFFFFFFFFFFFFFFFFC0000000FFFFFFFFFFFFFFFFFFFFFFFFFFFF) |
                (centerPriceAddress_ << 112) |
                (uint(1) << 248);

            _centerPriceShift[DEX_TYPE][dexId_] = block.timestamp | (percent_ << 33) | (time_ << 53);
        } else {
            _dexVariables2[DEX_TYPE][dexId_] = (_dexVariables2[DEX_TYPE][dexId_] & 0xFeFFFFFFFFFFFFFFFFFFFFFFFFFFC0000000FFFFFFFFFFFFFFFFFFFFFFFFFFFF);

            _centerPriceShift[DEX_TYPE][dexId_] = 0;
        }

        emit LogUpdateCenterPriceAddress(DEX_TYPE, dexId_, centerPriceAddress_, percent_, time_);
    }

    /// @dev we are storing uint nonce from which we will calculate the contract address, to store an address we need 160 bits
    /// which is quite a lot of storage slot
    /// @param hookAddress_ nonce < X30, this nonce will be used to calculate contract address
    function updateHookAddress(DexKey memory dexKey_, uint hookAddress_) public _onlyDelegateCall {
        bytes32 dexId_ = keccak256(abi.encode(dexKey_));
        _check(dexId_);

        if (hookAddress_ > X30) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
        }

        if (hookAddress_ > 0) {
            address hook_ = AddressCalcs.addressCalc(DEPLOYER_CONTRACT, hookAddress_);
            _checkIsContract(hook_);
        }

        _dexVariables2[DEX_TYPE][dexId_] =
            (_dexVariables2[DEX_TYPE][dexId_] & 0xFFFFFFFFFFFFFFFFFFFFF00000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) |
            (hookAddress_ << 142);

        emit LogUpdateHookAddress(DEX_TYPE, dexId_, hookAddress_);
    }

    function updateCenterPriceLimits(DexKey memory dexKey_, uint maxCenterPrice_, uint minCenterPrice_) public _onlyDelegateCall {
        bytes32 dexId_ = keccak256(abi.encode(dexKey_));
        _check(dexId_);

        uint centerPrice_ = (_dexVariables2[DEX_TYPE][dexId_] >> 81) & X40;
        centerPrice_ = (centerPrice_ >> DEFAULT_EXPONENT_SIZE) << (centerPrice_ & DEFAULT_EXPONENT_MASK);

        if ((maxCenterPrice_ <= minCenterPrice_) || (centerPrice_ <= minCenterPrice_) || (centerPrice_ >= maxCenterPrice_) || (minCenterPrice_ == 0)) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
        }

        _dexVariables2[DEX_TYPE][dexId_] =
            (_dexVariables2[DEX_TYPE][dexId_] & 0xFFFFFFF00000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) |
            (maxCenterPrice_.toBigNumber(20, 8, BigMathMinified.ROUND_UP) << 172) |
            (minCenterPrice_.toBigNumber(20, 8, BigMathMinified.ROUND_DOWN) << 200);

        emit LogUpdateCenterPriceLimits(DEX_TYPE, dexId_, maxCenterPrice_, minCenterPrice_);
    }

    function updateUserBorrowConfigs(DexKey memory dexKey_, UserBorrowConfig[] memory userBorrowConfigs_) external _onlyDelegateCall {
        bytes32 dexId_ = keccak256(abi.encode(dexKey_));
        _check(dexId_);

        uint256 userBorrowData_;

        for (uint256 i; i < userBorrowConfigs_.length; ) {
            _checkIsContract(userBorrowConfigs_[i].user);
            if (
                // max debt ceiling must not be smaller than base debt ceiling. Also covers case where max = 0 but base > 0
                userBorrowConfigs_[i].baseDebtCeiling > userBorrowConfigs_[i].maxDebtCeiling ||
                // can not set expand duration to 0 as that could cause a division by 0 in LiquidityCalcs.
                // having expand duration as 0 is anyway not an expected config so removing the possibility for that.
                // if no expansion is wanted, simply set expandDuration to 1 and expandPercent to 0.
                userBorrowConfigs_[i].expandDuration == 0
            ) {
                revert(); // FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
            }
            if (userBorrowConfigs_[i].expandPercent > X14) {
                // expandPercent is max 14 bits
                revert(); // FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
            }
            if (userBorrowConfigs_[i].expandDuration > X24) {
                // duration is max 24 bits
                revert(); // FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
            }
            if (userBorrowConfigs_[i].baseDebtCeiling == 0 || userBorrowConfigs_[i].maxDebtCeiling == 0) {
                // limits can not be 0. As a side effect, this ensures that there is no borrow config
                // where all values would be 0, so configured users can be differentiated in the mapping.
                revert(); // FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
            }
            // @dev baseDebtCeiling & maxDebtCeiling have no max bits amount as they are in normal token amount
            // and then converted to BigNumber

            // get current user config data from storage
            userBorrowData_ = _userBorrowData[DEX_TYPE][dexId_][userBorrowConfigs_[i].user];

            // Updating user data on storage

            _userBorrowData[DEX_TYPE][dexId_][userBorrowConfigs_[i].user] =
                // mask to update first bit (mode) + bits 162-235 (debt limit values)
                (userBorrowData_ & 0xfffff0000000000000000003ffffffffffffffffffffffffffffffffffffffff) |
                (1) |
                (userBorrowConfigs_[i].expandPercent << DexSlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) |
                (userBorrowConfigs_[i].expandDuration << DexSlotsLink.BITS_USER_BORROW_EXPAND_DURATION) |
                // convert base debt limit to BigNumber for storage (10 | 8). (borrow is always possible below this)
                (userBorrowConfigs_[i].baseDebtCeiling.toBigNumber(SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN) <<
                    DexSlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) |
                // convert max debt limit to BigNumber for storage (10 | 8). (no borrowing ever possible above this)
                (userBorrowConfigs_[i].maxDebtCeiling.toBigNumber(SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN) <<
                    DexSlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT);

            unchecked {
                ++i;
            }
        }

        emit LogUpdateUserBorrowConfigs(DEX_TYPE, dexId_, userBorrowConfigs_);
    }

    function pauseUser(DexKey memory dexKey_, address user_) public _onlyDelegateCall {
        bytes32 dexId_ = keccak256(abi.encode(dexKey_));
        _check(dexId_);

        _checkIsContract(user_);

        uint256 userData_ = _userBorrowData[DEX_TYPE][dexId_][user_];
        if (userData_ == 0) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__UserNotDefined);
        }
        if (userData_ & 1 == 0) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__InvalidPauseToggle);
        }
        // set first bit as 0, meaning all user's borrow operations are paused
        _userBorrowData[DEX_TYPE][dexId_][user_] = userData_ & (~uint(1));

        emit LogPauseUser(DEX_TYPE, dexId_, user_);
    }

    function unpauseUser(DexKey memory dexKey_, address user_) public _onlyDelegateCall {
        bytes32 dexId_ = keccak256(abi.encode(dexKey_));
        _check(dexId_);

        _checkIsContract(user_);

        uint256 userData_ = _userBorrowData[DEX_TYPE][dexId_][user_];
        if (userData_ == 0) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__UserNotDefined);
        }
        if (userData_ & 1 == 1) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__InvalidPauseToggle);
        }

        // set first bit as 1, meaning unpause
        _userBorrowData[DEX_TYPE][dexId_][user_] = userData_ | 1;

        emit LogUnpauseUser(DEX_TYPE, dexId_, user_);
    }

    /// @dev Can only borrow if DEX pool address borrow config is added in Liquidity Layer for both the tokens else Liquidity Layer will revert
    /// governance will have access to _turnOnSmartDebt, technically governance here can borrow as much as limits are set
    /// so it's governance responsibility that it borrows small amount between $100 - $10,000
    /// Borrowing in 50:50 ratio (doesn't matter if pool configuration is set to 20:80, 30:70, etc, external swap will arbitrage & balance the pool)
    function _lockInitialAmount(DexKey memory dexKey_, bytes32 dexId_, uint token0Amt_, uint centerPrice_, uint token0Decimals_, uint token1Decimals_) internal {
        LockInitialAmountVariables memory v_;

        (v_.token0NumeratorPrecision, v_.token0DenominatorPrecision) = calculateNumeratorAndDenominatorPrecisions(token0Decimals_);
        (v_.token1NumeratorPrecision, v_.token1DenominatorPrecision) = calculateNumeratorAndDenominatorPrecisions(token1Decimals_);

        v_.token0AmtAdjusted = (token0Amt_ * v_.token0NumeratorPrecision) / v_.token0DenominatorPrecision;

        v_.token1AmtAdjusted = (centerPrice_ * v_.token0AmtAdjusted) / 1e27;

        v_.token1Amt = (v_.token1AmtAdjusted * v_.token1DenominatorPrecision) / v_.token1NumeratorPrecision;

        LIQUIDITY.operate(dexKey_.token0, 0, int(token0Amt_), address(0), TEAM_MULTISIG, new bytes(0));
        LIQUIDITY.operate(dexKey_.token1, 0, int(v_.token1Amt), address(0), TEAM_MULTISIG, new bytes(0));

        // minting shares as whatever tokenAmt is bigger
        // adding shares on storage but not adding shares for any user, hence locking these shares forever
        // adjusted amounts are in 12 decimals, making shares in 18 decimals
        v_.totalBorrowShares = (v_.token0AmtAdjusted > v_.token1AmtAdjusted)
            ? v_.token0AmtAdjusted * 10 ** (18 - TOKENS_DECIMALS_PRECISION)
            : v_.token1AmtAdjusted * 10 ** (18 - TOKENS_DECIMALS_PRECISION);

        if (v_.totalBorrowShares < NINE_DECIMALS) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__UnexpectedPoolState);
        }

        // setting initial max shares as X128
        v_.totalBorrowShares = (v_.totalBorrowShares & X128) | (X128 << 128);
        // storing in storage
        _totalBorrowShares[DEX_TYPE][dexId_] = v_.totalBorrowShares;
    }

    // TODO: Check this again later
    /// note we have not added updateUtilizationLimit in the params here because struct of InitializeVariables already has 16 variables
    /// we might skip adding it and let it update through the indepdent function to keep initialize struct simple
    function initialize(InitializeParams memory i_) public payable _onlyDelegateCall {
        InitializeVariables memory v_;

        v_.dexId = keccak256(abi.encode(i_.dexKey));
        v_.dexVariables2 = _dexVariables2[DEX_TYPE][v_.dexId];
        if (v_.dexVariables2 & 1 == 1) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__PoolAlreadyInitialized);
        }

        _checkIsContract(TEAM_MULTISIG);

        // cut is an integer in storage slot which is more than enough
        // but from UI we are allowing to send in 4 decimals to maintain consistency & avoid human error in future
        if (i_.revenueCut != 0 && i_.revenueCut < FOUR_DECIMALS) {
            // human input error. should send 0 for wanting 0, not 0 because of precision reduction.
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
        }

        // revenue cut has no decimals
        i_.revenueCut = i_.revenueCut / FOUR_DECIMALS;
        i_.upperShiftThreshold = i_.upperShiftThreshold / THREE_DECIMALS;
        i_.lowerShiftThreshold = i_.lowerShiftThreshold / THREE_DECIMALS;

        if (
            (i_.fee > FIVE_DECIMALS) || // fee cannot be more than 10%
            (i_.revenueCut > TWO_DECIMALS) ||
            (i_.upperPercent > (SIX_DECIMALS - FOUR_DECIMALS)) || // capping range to 99%.
            (i_.lowerPercent > (SIX_DECIMALS - FOUR_DECIMALS)) || // capping range to 99%.
            (i_.upperPercent == 0) ||
            (i_.lowerPercent == 0) ||
            (i_.upperShiftThreshold > THREE_DECIMALS) ||
            (i_.lowerShiftThreshold > THREE_DECIMALS) ||
            ((i_.upperShiftThreshold == 0) && (i_.lowerShiftThreshold > 0)) ||
            ((i_.upperShiftThreshold > 0) && (i_.lowerShiftThreshold == 0)) ||
            (i_.thresholdShiftTime == 0) ||
            (i_.thresholdShiftTime > X24) ||
            (i_.centerPriceAddress > X30) ||
            (i_.hookAddress > X30) ||
            (i_.centerPrice <= i_.minCenterPrice) ||
            (i_.centerPrice >= i_.maxCenterPrice) ||
            (i_.minCenterPrice == 0)
        ) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
        }

        v_.dexVariables2 |= 1;
        v_.token0Decimals = IERC20WithDecimals(i_.dexKey.token0).decimals();
        v_.token1Decimals = IERC20WithDecimals(i_.dexKey.token1).decimals();
        _lockInitialAmount(i_.dexKey, v_.dexId, i_.token0DebtAmt, i_.centerPrice, v_.token0Decimals, v_.token1Decimals);

        i_.centerPrice = i_.centerPrice.toBigNumber(32, 8, BigMathMinified.ROUND_DOWN);
        // setting up initial dexVariables
        _dexVariables[DEX_TYPE][v_.dexId] =
            (i_.centerPrice << 1) |
            (i_.centerPrice << 41) |
            (i_.centerPrice << 81) |
            (block.timestamp << 121) |
            (60 << 154) | // just setting 60 seconds, no particular reason for it why "60"
            (7 << 176);

        _dexVariables2[DEX_TYPE][v_.dexId] =
            v_.dexVariables2 |
            (i_.fee << 2) |
            (i_.revenueCut << 19) |
            (i_.upperPercent << 27) |
            (i_.lowerPercent << 47) |
            (i_.upperShiftThreshold << 68) |
            (i_.lowerShiftThreshold << 78) |
            (i_.thresholdShiftTime << 88) |
            (i_.centerPriceAddress << 112) |
            (i_.hookAddress << 142) |
            (i_.maxCenterPrice.toBigNumber(20, 8, BigMathMinified.ROUND_UP) << 172) |
            (i_.minCenterPrice.toBigNumber(20, 8, BigMathMinified.ROUND_DOWN) << 200) |
            (v_.token0Decimals << 228) |
            (v_.token1Decimals << 233);

        emit LogInitializePoolConfig(DEX_TYPE, v_.dexId, i_.token0DebtAmt, i_.fee, i_.revenueCut * FOUR_DECIMALS, i_.centerPriceAddress, i_.hookAddress);

        emit LogInitializePriceParams(
            DEX_TYPE,
            v_.dexId,
            i_.upperPercent,
            i_.lowerPercent,
            i_.upperShiftThreshold * THREE_DECIMALS,
            i_.lowerShiftThreshold * THREE_DECIMALS,
            i_.thresholdShiftTime,
            i_.maxCenterPrice,
            i_.minCenterPrice
        );
    }

    function pauseSwap(DexKey memory dexKey_) public _onlyDelegateCall {
        bytes32 dexId_ = keccak256(abi.encode(dexKey_));
        _check(dexId_);

        uint dexVariables2_ = _dexVariables2[DEX_TYPE][dexId_];
        if ((dexVariables2_ >> 255) == 1) {
            // already paused
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
        }
        _dexVariables2[DEX_TYPE][dexId_] = dexVariables2_ | (uint(1) << 255);

        emit LogPauseSwap(DEX_TYPE, dexId_);
    }

    function unpauseSwap(DexKey memory dexKey_) public _onlyDelegateCall {
        bytes32 dexId_ = keccak256(abi.encode(dexKey_));
        _check(dexId_);

        uint dexVariables2_ = _dexVariables2[DEX_TYPE][dexId_];
        if ((dexVariables2_ >> 255) == 0) {
            // already unpaused
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
        }
        _dexVariables2[DEX_TYPE][dexId_] = (dexVariables2_ << 1) >> 1;

        emit LogUnpauseSwap(DEX_TYPE, dexId_);
    }

    function updateMaxBorrowShares(DexKey memory dexKey_, uint maxBorrowShares_) external _onlyDelegateCall {
        bytes32 dexId_ = keccak256(abi.encode(dexKey_));
        _check(dexId_);

        uint totalBorrowShares_ = _totalBorrowShares[DEX_TYPE][dexId_];

        // totalBorrowShares_ can only be 0 when smart debt pool is not initialized
        if ((maxBorrowShares_ > X128) || (totalBorrowShares_ == 0)) {
            revert(); // FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
        }
        _totalBorrowShares[DEX_TYPE][dexId_] = (totalBorrowShares_ & X128) | (maxBorrowShares_ << 128);

        emit LogUpdateMaxBorrowShares(DEX_TYPE, dexId_, maxBorrowShares_);
    }
}
