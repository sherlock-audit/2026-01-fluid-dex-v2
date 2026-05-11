// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

abstract contract Structs {
    struct OracleConfig {
        // -------------- slot 1 ---------------
        address source1;
        int8 multiplier1; // decimals multiplier: positive = multiply, negative = divide. to get to 1e27 decimals. 0 = keep same, 1 = * 10, 2 = * 100 etc, -1 = /10, -2 = /100 etc.
        uint8 sourceType1; // 0 = NOT SET (invalid), 1 = FluidCappedRate, 2 = Chainlink
        // ----- 176 bits above ---------
        uint64 __placeholder1; // reserved placeholder so additional info can be added to first slot if needed in an upgrade.
        // ordered with sourceType2 next so it is still in first slot. second slot only loaded when sourceType2 != 0
        uint8 sourceType2; // 0 = NOT SET, 1 = FluidCappedRate, 2 = Chainlink
        uint8 sourceType3; // 0 = NOT SET, 1 = FluidCappedRate, 2 = Chainlink
        // -------------- slot 2 ---------------
        int8 multiplier2; // positive = multiply, negative = divide. to get to 1e27 decimals
        address source2;
        uint88 __placeholder2; // reserved placeholder so additional info can be added to first slot if needed in an upgrade.
        // -------------- slot 3 ---------------
        int8 multiplier3; // positive = multiply, negative = divide. to get to 1e27 decimals
        address source3;
        uint88 __placeholder3; // reserved placeholder so additional info can be added to first slot if needed in an upgrade.
    }

    struct ConfigMap {
        uint240 eMode;
        bool isOperate;
        bool isCollateral;
    }

    struct ConfiguredTokenOracle {
        address token;
        string symbol;
        uint256 eMode;
        bool isOperate;
        bool isCollateral;
        uint8 sourceType1;
        address source1;
        int8 multiplier1;
        uint8 sourceType2;
        address source2;
        int8 multiplier2;
        uint8 sourceType3;
        address source3;
        int8 multiplier3;
        uint256 rate1;
        uint256 rate2;
        uint256 rate3;
        uint256 price;
    }

    struct SetSourceConfig {
        uint8 sourceType;
        address source;
        int8 multiplier;
    }
}
