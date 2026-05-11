// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

contract MockOracleMM {
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Mapping to store token prices (token address => price)
    mapping(address => uint256) public tokenPrices;

    /// @notice Set the price for a specific token
    /// @param token_ The token address
    /// @param price_ The price in 18 decimals (e.g., $4000 = 4000 * 1e18)
    function setPrice(address token_, uint256 price_) external {
        tokenPrices[token_] = price_;
    }

    /// @notice Get the price for a token
    /// @param token0_ The token address
    /// @return price_ The token price in 18 decimals
    function getPrice(address token0_, uint256 /* emode_ */, bool /* isOperate_ */, bool /* isCollateral_ */) external view returns (uint256 price_) {
        price_ = tokenPrices[token0_];
        require(price_ > 0, "MockOracleMM: Price not set for token");
        return price_;
    }
}