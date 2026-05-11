// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import "./immutableVariables.sol";

abstract contract CommonVariables is CommonImmutableVariables {
    // First 1 bit  => 0       => left blank (@dev dex v1 stored reentrancy flag in this bit)
    // Next 40 bits => 1-40    => last to last stored price. BigNumber (32 bits precision, 8 bits exponent)
    // Next 40 bits => 41-80   => last stored price of pool. BigNumber (32 bits precision, 8 bits exponent)
    // Next 40 bits => 81-120  => center price. Center price from where the ranges will be calculated. BigNumber (32 bits precision, 8 bits exponent)
    // Next 33 bits => 121-153 => last interaction time stamp
    // Next 22 bits => 154-175 => max 4194303 seconds (~1165 hrs, ~48.5 days), time difference between last to last and last price stored
    // Next 3 bits  => 176-178 => oracle checkpoint, if 0 then first slot, if 7 then last slot
    // Next 16 bits => 179-194 => current mapping or oracle, after every 8 transaction it will increase by 1. Max capacity is 65535 but it can be lower than that check dexVariables2
    // Next 1 bit   => 195     => is oracle active?
    /// @dev type => pool id => dex variables 1
    mapping(uint256 => mapping(bytes32 => uint256)) internal _dexVariables;

    // First 1 bits => 0       => is pool initialized? (@dev dex v1 stored smart collateral flag in this bit)
    // Next 1 bit   => 1       => left blank (@dev dex v1 stored smart debt flag in this bit)
    // Next 17 bits => 2-18    => fee (1% = 10000, max value: 100000 = 10%, fee should not be more than 10%)
    // Next  7 bits => 19-25   => revenue cut from fee (1 = 1%, 100 = 100%). If fee is 1000 = 0.1% and revenue cut is 10 = 10% then governance get 0.01% of every swap
    // Next  1 bit  => 26      => percent active change going on or not, 0 = false, 1 = true, if true than that means governance has updated the below percents and the update should happen with a specified time.
    // Next 20 bits => 27-46   => upperPercent (1% = 10000, max value: 104.8575%) upperRange - upperRange * upperPercent = centerPrice. Hence, upperRange = centerPrice / (1 - upperPercent)
    // Next 20 bits => 47-66   => lowerPercent. lowerRange = centerPrice - centerPrice * lowerPercent.
    // Next  1 bit  => 67      => threshold percent active change going on or not, 0 = false, 1 = true, if true than that means governance has updated the below percents and the update should happen with a specified time.
    // Next 10 bits => 68-77   => upper shift threshold percent, 1 = 0.1%. 1000 = 100%. if currentPrice > (centerPrice + (upperRange - centerPrice) * (1000 - upperShiftThresholdPercent) / 1000) then trigger shift
    // Next 10 bits => 78-87   => lower shift threshold percent, 1 = 0.1%. 1000 = 100%. if currentPrice < (centerPrice - (centerPrice - lowerRange) * (1000 - lowerShiftThresholdPercent) / 1000) then trigger shift
    // Next 24 bits => 88-111  => Shifting time (~194 days) (rate = (% up + % down) / time ?)
    // Next 30 bits => 112-131 => Deployment Factory Nonce for center price contract address
    /// Center price should be fetched externally, for example, for wstETH <> ETH pool, fetch wstETH exchange rate into stETH from wstETH contract.
    /// Why fetch it externally? Because let's say pool width is 0.1% and wstETH temporarily got depeg of 0.5% then pool will start to shift to newer pricing
    /// but we don't want pool to shift to 0.5% because we know the depeg will recover so to avoid the loss for users.
    // Next 30 bits => 142-171 => Deployment Factory Nonce for hook contract address
    // Next 28 bits => 172-199 => max center price. BigNumber (20 bits precision, 8 bits exponent)
    // Next 28 bits => 200-227 => min center price. BigNumber (20 bits precision, 8 bits exponent)
    // Next 5  bits => 228-232 => token 0 decimals
    // Next 5  bits => 233-237 => token 1 decimals (@dev dex v1 stored utlization limit of token0 in these 10 bits (228-237))
    // Next 10 bits => 238-247 => left blank (@dev dex v1 stored utlization limit of token1 in these bits)
    // Next 1  bit  => 248     => is center price shift active
    // Last 1  bit  => 255     => Pause swap (only user operations will be usable), if we need to pause entire DEX then that can be done through pausing DEX on Liquidity Layer <- TODO: this won't apply we can only pause all of dexV2 at LL level. need to check impact / if we need some other forms of pausing
    /// @dev type => pool id => dex variables 2
    mapping(uint256 => mapping(bytes32 => uint256)) internal _dexVariables2;

    /// @dev this was 2 separate u128 variables in same storage slot in dexV1
    /// Range Shift (first 128 bits)
    // First 20 bits => 0 -19   => old upper shift
    // Next  20 bits => 20-39   => old lower shift
    // Next  20 bits => 40-59   => in seconds, ~12 days max, shift can last for max ~12 days
    // Next  33 bits => 60-92   => timestamp of when the shift has started.
    // Next  35 bits => 93-127  => empty for future use
    /// Threshold Shift (next 128 bits)
    // Next  10 bits => 0  - 9  => old upper shift
    // Next  10 bits => 10 -19  => empty so we can use same helper function
    // Next  10 bits => 20 -29  => old lower shift
    // Next  10 bits => 30 -39  => empty so we can use same helper function
    // Next  20 bits => 40 -59  => in seconds, ~12 days max, shift can last for max ~12 days
    // Next  33 bits => 60 -92  => timestamp of when the shift has started.
    // Next  24 bits => 93 -116 => old threshold time
    // Next  11 bits => 117-127 => empty for future use
    /// @dev type => pool id => range and threshold shift
    mapping(uint256 => mapping(bytes32 => uint256)) internal _rangeAndThresholdShift;

    /// Shifting is fuzzy and with time it'll keep on getting closer and then eventually get over
    // First 33 bits => 0 -32 => starting timestamp
    // Next  20 bits => 33-52 => % shift
    // Next  20 bits => 53-72 => time to shift that percent
    /// @dev type => pool id => center price shift
    mapping(uint256 => mapping(bytes32 => uint256)) internal _centerPriceShift;
}
