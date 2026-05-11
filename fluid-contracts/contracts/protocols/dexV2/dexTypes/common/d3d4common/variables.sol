// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;
import "./constantVariables.sol";

abstract contract CommonVariables is CommonConstantVariables {
    // First 1  bits => 0         => Current Tick Sign (0 => negative, 1 => positive)
    // Next  19 bits => 1   - 19  => Absolute Current Tick
    // Next  72 bits => 20  - 91  => Current Sqrt Price (X96) (64|8 big number)
    // Next  82 bits => 92  - 173 => Fee Growth Global Per Liquidity Token 0 (X102) (74|8 big number)
    // Next  82 bits => 174 - 255 => Fee Growth Global Per Liquidity Token 1 (X102) (74|8 big number)
    /// @dev dex type => dex id => dex variables
    mapping(uint256 => mapping(bytes32 => uint256)) internal _dexVariables;

    // First 12  bits => 0   - 11  => Protocol Fee 0->1 (1e6 = 100%) (Max 0.4095%) (This is protocol fee which will be cut directly from unspecified amount (amountOut for swapIn, amountIn for swapOut))
    // Next  12  bits => 12  - 23  => Protocol Fee 1->0 (1e6 = 100%) (Max 0.4095%) (This is protocol fee which will be cut directly from unspecified amount (amountIn for swapIn, amountOut for swapOut))
    // Next  6   bits => 24  - 29  => Protocol Cut Fee (1 = 1%) (Max 63%) (This is protocol cut from the lp fee)
    // Next  4   bits => 30  - 33  => Token 0 decimals (Token decimals 15, 16 and 17 can't exist, and if this is 15, then it means token decimals are 18)
    // Next  4   bits => 34  - 37  => Token 1 decimals (Token decimals 15, 16 and 17 can't exist, and if this is 15, then it means token decimals are 18)
    // Next  102 bits => 38  - 139 => Active Liquidity
    // Next  1   bit  => 140       => Pool Accounting Flag // 0 => per pool accounting is ON; 1 => per pool accounting is OFF (This will always be ON initially, and can only be turned OFF once)
    // Next  1   bit  => 141       => Fetch Dynamic Fee Flag // This flag can only be ON if its a dynamic fee pool
    // Next  10  bits => 142 - 151 => Left Empty for future use

    // FEE VARIABLES
    // Next  4   bit  => 152 - 155 => Fee Version // This can only be non zero if its a dynamic fee pool // Right now this can only be 0 and 1, the remaining bits are left for future

    /// Fee Version 0: Static Fee
    // Next  16  bits => 156 - 171 => LP Fee (1e6 = 100%) (Max 6.5535%) // This will store the static lp fee if its a static fee pool, or the current dynamic lp fee if its a dynamic fee pool
    // Next  84  bits left empty

    /// Fee Version 1: Pool Inbuilt Dynamic Fee
    /// Dynamic Fee Configs in below 52 bits (156 - 207)
    // Next  12  bit  => 156 - 167 => Max Decay Time (seconds) (Max 4095 seconds, i.e, 1 hour 8 mins 15 seconds)
    // Next  8   bits => 168 - 175 => Price Impact to Fee Division Factor (Max 255) (Fee = Net Price Impact / Division Factor)
    // Next  16  bits => 176 - 191 => Min Fee (1e6 = 100%) (Max 6.5535%)
    // Next  16  bits => 192 - 207 => Max Fee (1e6 = 100%) (Max 6.5535%)
    /// Dynamic Fee Variables below 48 bits (208 - 255)
    // Next  1   bit  => 208       => Net Price Impact sign (0 => negative, 1 => positive)
    // Next  20  bits => 209 - 228 => Absolute Net Price Impact (Max 1e6 = 100% // More swaps are not allowed if this is crossed)
    // Next  15  bits => 229 - 243 => Last Update Timestamp (seconds) (We only store the least significant 15 bits of the timestamp)
    // Next  12  bits => 244 - 255 => Decay Time Remaining (seconds) (Max 4095 seconds, i.e, 1 hour 8 mins 15 seconds)
    /// @dev dex type => dex id => dex variables 2
    mapping(uint256 => mapping(bytes32 => uint256)) internal _dexVariables2;

    /// Tick Bitmap
    /// Bitmap stores whether a tick is initialized or not
    /// @dev dex type => dex id => tick parent => bitmap
    mapping(uint256 => mapping(bytes32 => mapping(int256 => uint256))) internal _tickBitmap;

    /// Tick Liquidity Gross
    /// @dev dex type => dex id => tick => tick liquidity gross (only needs 91 bits, currently we gave it full variable, later we can use the extra bits if needed)
    mapping(uint256 => mapping(bytes32 => mapping(int256 => uint256))) internal _tickLiquidityGross;

    /// Tick Data
    /// @dev dex type => dex id => tick => Tick Data Struct
    mapping(uint256 => mapping(bytes32 => mapping(int256 => TickData))) internal _tickData;

    /// Position Data
    /// @dev dex type => dex id => position id => Position Data Struct
    mapping(uint256 => mapping(bytes32 => mapping(bytes32 => PositionData))) internal _positionData;

    /// Token Reserves
    /// @dev dex type => dex id => token reserves
    /// First 128 bits => 0   - 127 => token 0 reserves
    /// Last  128 bits => 128 - 255 => token 1 reserves
    mapping(uint256 => mapping(bytes32 => uint256)) internal _tokenReserves;

    // dex type => user => is whitelisted
    mapping(uint256 => mapping(address => uint256)) internal _whitelistedUsers;

    /// @dev dex type => dex id => Dex Key
    mapping(uint256 => mapping(bytes32 => DexKey)) internal _dexKey;
}