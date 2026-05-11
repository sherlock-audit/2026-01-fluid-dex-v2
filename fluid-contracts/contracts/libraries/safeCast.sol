// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

/// @title SafeCast
/// @notice Minimal safe casting library for uint256 to int256 conversion
library SafeCast {
    /// @notice Safely casts uint256 to int256, reverting on overflow
    /// @param value The uint256 value to cast
    /// @return The value as int256
    function toInt256(uint256 value) internal pure returns (int256) {
        if (value > uint256(type(int256).max)) revert();
        return int256(value);
    }
}
