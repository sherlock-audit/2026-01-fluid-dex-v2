// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./helpers.sol";

/// @title DexV2AdminModule
/// @notice Admin module for DexV2 governance and configuration
/// @dev Handles auth management, UUPS upgrades, admin implementation routing, token management, and rebalancing
abstract contract DexV2AdminModule is Helpers {
    /// @notice Modifier to ensure function is called only by governance
    modifier onlyGovernance() {
        if (_getGovernanceAddr() != msg.sender) {
            revert FluidDexV2Error(ErrorTypes.DexV2AdminModule__Unauthorized);
        }
        _;
    }

    /// @notice Modifier to ensure function is called only by an auth
    modifier onlyAuths() {
        if (_isAuth[BASE_SLOT][msg.sender] == 0 && _getGovernanceAddr() != msg.sender) {
            revert FluidDexV2Error(ErrorTypes.DexV2AdminModule__Unauthorized);
        }
        _;
    }

    /// @notice Updates the authorization status for an address
    /// @dev Only callable by governance
    /// @param auth_ The address to update authorization for
    /// @param isAuth_ True to grant auth, false to revoke
    function updateAuth(address auth_, bool isAuth_) external onlyGovernance {
        _isAuth[BASE_SLOT][auth_] = isAuth_ ? 1 : 0;
        emit LogUpdateAuth(auth_, isAuth_);
    }

    /// @dev Internal function to upgrade implementation with UUPS safety checks
    function _authorizeAndUpgrade(address newImplementation_, bytes memory data_) private {
        // Verify new implementation is a contract
        uint256 size_;
        assembly {
            size_ := extcodesize(newImplementation_)
        }
        if (size_ == 0) {
            revert FluidDexV2Error(ErrorTypes.DexV2AdminModule__NewImplementationNotAContract);
        }

        // UUPS safety check: verify new implementation supports proxiableUUID
        try IERC1822Proxiable(newImplementation_).proxiableUUID() returns (bytes32 slot) {
            if (slot != IMPLEMENTATION_SLOT) {
                revert FluidDexV2Error(ErrorTypes.DexV2AdminModule__UnsupportedProxiableUUID);
            }
        } catch {
            revert FluidDexV2Error(ErrorTypes.DexV2AdminModule__NotUUPSCompatible);
        }

        // Store new implementation address in EIP-1967 slot
        assembly {
            sstore(IMPLEMENTATION_SLOT, newImplementation_)
        }
        emit LogUpgraded(newImplementation_);

        // Call initialization function if data provided
        if (data_.length > 0) {
            (bool success_, bytes memory returndata_) = newImplementation_.delegatecall(data_);
            if (!success_) {
                if (returndata_.length > 0) {
                    assembly {
                        revert(add(returndata_, 32), mload(returndata_))
                    }
                } else {
                    revert FluidDexV2Error(ErrorTypes.DexV2AdminModule__UpgradeCallFailed);
                }
            }
        }
    }

    /// @notice Upgrades the proxy to a new implementation
    /// @param newImplementation_ Address of the new implementation contract
    function upgradeTo(address newImplementation_) external onlyGovernance {
        _authorizeAndUpgrade(newImplementation_, "");
    }

    /// @notice Upgrades the proxy to a new implementation and calls a function on it
    /// @param newImplementation_ Address of the new implementation contract
    /// @param data_ Data to pass to the new implementation via delegatecall
    function upgradeToAndCall(address newImplementation_, bytes calldata data_) external payable onlyGovernance {
        _authorizeAndUpgrade(newImplementation_, data_);
    }

    /// @dev Returns the proxiableUUID for UUPS compatibility
    /// @return The EIP-1967 implementation slot
    function proxiableUUID() external pure returns (bytes32) {
        return IMPLEMENTATION_SLOT;
    }

    /// @notice Registers or updates an admin implementation for a DEX type
    /// @dev Validates that the implementation's DEX type and Liquidity address match
    /// @param dexType_ The DEX type (e.g., 3 for D3, 4 for D4)
    /// @param adminImplementationId_ The admin module implementation ID
    /// @param adminImplementation_ The admin implementation contract address (address(0) to remove)
    function updateDexTypeToAdminImplementation(uint256 dexType_, uint256 adminImplementationId_, address adminImplementation_) external onlyGovernance {
        address exisitingImplementation_ = _dexTypeToAdminImplementation[BASE_SLOT][dexType_][adminImplementationId_];
        if (exisitingImplementation_ == adminImplementation_) {
            revert FluidDexV2Error(ErrorTypes.DexV2AdminModule__ImplementationAlreadySet);
        }

        if (adminImplementation_ != address(0)) {
            (uint256 dexTypeFetched_, address liquidityAddrFetched_) = IDexV2Implementation(adminImplementation_).getDexTypeAndLiquidityAddr();
            if (dexTypeFetched_ != dexType_) {
                revert FluidDexV2Error(ErrorTypes.DexV2AdminModule__ImplementationDexTypeMismatch);
            }
            if (liquidityAddrFetched_ != address(LIQUIDITY)) {
                revert FluidDexV2Error(ErrorTypes.DexV2AdminModule__ImplementationLiquidityMismatch);
            }
        }

        _dexTypeToAdminImplementation[BASE_SLOT][dexType_][adminImplementationId_] = adminImplementation_;
        emit LogUpdateDexTypeToAdminImplementation(dexType_, adminImplementationId_, adminImplementation_);
    }

    /// @notice Adds or removes tokens from the DexV2 contract balance
    /// @dev Only callable by authorized addresses. Used to seed initial liquidity or withdraw excess.
    /// @param token_ The token address (use NATIVE_TOKEN constant for ETH)
    /// @param amount_ Positive to add tokens, negative to remove tokens
    function addOrRemoveTokens(address token_, int256 amount_) external payable onlyAuths {
        // there should not be msg.value if the token is not the native token
        if (token_ != NATIVE_TOKEN && msg.value > 0) {
            revert FluidDexV2Error(ErrorTypes.DexV2AdminModule__MsgValueForNonNativeToken);
        }
        
        if (amount_ > 0) {
            if (token_ == NATIVE_TOKEN) {
                if (msg.value > uint256(amount_)) SafeTransfer.safeTransferNative(msg.sender, msg.value - uint256(amount_));
                else if (msg.value < uint256(amount_)) {
                    revert FluidDexV2Error(ErrorTypes.DexV2AdminModule__MsgValueMismatch);
                }
            } else {
                SafeTransfer.safeTransferFrom(token_, msg.sender, address(this), uint256(amount_));
            }
            _totalAuthAddedAmount[BASE_SLOT][token_] += uint256(amount_);
        } else {
            _totalAuthAddedAmount[BASE_SLOT][token_] -= uint256(-amount_);
            if (token_ == NATIVE_TOKEN) {
                SafeTransfer.safeTransferNative(msg.sender, uint256(-amount_) + msg.value);
            } else {
                SafeTransfer.safeTransfer(token_, msg.sender, uint256(-amount_));
            }
        }
        
        emit LogAddOrRemoveTokens(token_, amount_);
    }

    /// @notice Rebalances a token's supply/borrow positions with the Liquidity layer
    /// @dev Syncs unaccounted borrow amounts and contract balance with Liquidity layer.
    ///      Called periodically to maintain accurate accounting between DexV2 and Liquidity.
    /// @param token_ The token address to rebalance
    function rebalance(address token_) external onlyAuths {
        uint256 totalAuthAddedAmount_ = _totalAuthAddedAmount[BASE_SLOT][token_];
        int256 unaccountedBorrowAmount_ = _unaccountedBorrowAmount[BASE_SLOT][token_];

        uint256 tokenBalance_ = token_ == NATIVE_TOKEN ? address(this).balance : IERC20(token_).balanceOf(address(this));

        int256 supplyAmount_ = int256(tokenBalance_) + unaccountedBorrowAmount_ - int256(totalAuthAddedAmount_);
        int256 borrowAmount_ = unaccountedBorrowAmount_;

        uint256 ethToSend_;
        if (token_ == NATIVE_TOKEN) {
            if (supplyAmount_ > 0) ethToSend_ += uint256(supplyAmount_);
            if (borrowAmount_ < 0) ethToSend_ += uint256(-borrowAmount_);
        }
        LIQUIDITY.operate{value: ethToSend_}(
            token_,
            supplyAmount_,
            borrowAmount_,
            address(this),
            address(this),
            abi.encode(DEXV2_IDENTIFIER, REBALANCE_ACTION_IDENTIFIER)
        );
        
        delete _unaccountedBorrowAmount[BASE_SLOT][token_];
        
        emit LogRebalance(token_, supplyAmount_, borrowAmount_);
    }
}
