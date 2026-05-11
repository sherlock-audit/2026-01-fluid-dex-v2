// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;
import "./events.sol";

abstract contract ConstantVariables is CommonImportD1D2Common {
    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant DEX_TYPE = 2;
}

abstract contract Variables is ConstantVariables {
    /// @dev @Samyak this was not present in dexV1
    // First 64 bits => 0-63 => token 0 total borrow raw (56|8 big number)
    // Next 64 bits => 64-127 => token 1 total borrow raw (56|8 big number)
    // Last 128 bits => 128-255 => empty for future use
    /// @dev type => pool id => total borrow
    mapping(uint256 => mapping(bytes32 => uint256)) internal _totalBorrow;

    // First 128 bits => 0-127 => total borrow shares
    // Last 128 bits => 128-255 => max borrow shares
    /// @dev type => pool id => total borrow shares
    mapping(uint256 => mapping(bytes32 => uint256)) internal _totalBorrowShares;

    /// @dev user borrow data: user -> data
    /// Aside from 1st bit, entire bits here are same as liquidity layer _userBorrowData. Hence exact same supply & borrow limit library function can be used
    // First  1 bit  =>       0 => is user allowed to borrow? 0 = not allowed, 1 = allowed
    // Next  64 bits =>   1- 64 => user debt amount/shares; BigMath: 56 | 8
    // Next  64 bits =>  65-128 => previous user debt ceiling; BigMath: 56 | 8
    // Next  33 bits => 129-161 => last triggered process timestamp (enough until 16 March 2242 -> max value 8589934591)
    // Next  14 bits => 162-175 => expand debt ceiling percentage (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383)
    ///                            @dev shrinking is instant
    // Next  24 bits => 176-199 => debt ceiling expand duration in seconds (Max value 16_777_215; ~4_660 hours, ~194 days)
    // Next  18 bits => 200-217 => base debt ceiling: below this, there's no debt ceiling limits; BigMath: 10 | 8
    // Next  18 bits => 218-235 => max debt ceiling: absolute maximum debt ceiling can expand to; BigMath: 10 | 8
    // Next  20 bits => 236-255 => empty for future use
    /// @dev type => pool id => user address => borrow data
    mapping(uint256 => mapping(bytes32 => mapping(address => uint256))) internal _userBorrowData;
}
