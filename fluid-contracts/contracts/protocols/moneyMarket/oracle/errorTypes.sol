// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

library ErrorTypes {
    uint256 internal constant MMOracle__AddressZero = 310001;
    uint256 internal constant MMOracle__Unauthorized = 310002;
    uint256 internal constant MMOracle__InvalidMultiplier = 310003;
    uint256 internal constant MMOracle__InvalidSource = 310004;
    uint256 internal constant MMOracle__InvalidEMode = 310005;
    uint256 internal constant MMOracle__NoConfig = 310006;
    uint256 internal constant MMOracle__InvalidSourceType = 310007;
    uint256 internal constant MMOracle__RateZero = 310008;
    uint256 internal constant MMOracle__ChainlinkStale = 310009;
    uint256 internal constant MMOracle__InvalidParams = 310010;
    uint256 internal constant MMOracle__RateInvalid = 310011;
    uint256 internal constant MMOracle__ConfigDoesNotExist = 310012;
}
