// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./structs.sol";

/// @notice Error types for FluidMoneyMarket
/// @dev Error IDs are organized by module, starting from 300001
/// @dev Within each module, errors are consolidated to minimize bytecode
library ErrorTypes {

    /***********************************|
    |      Admin Module Errors          | 
    |__________________________________*/

    /// @notice thrown when caller is not authorized
    uint256 internal constant AdminModule__Unauthorized = 300001;

    /// @notice thrown when invalid parameters are provided
    uint256 internal constant AdminModule__InvalidParams = 300002;

    /// @notice thrown when a cap or limit is exceeded
    uint256 internal constant AdminModule__CapExceeded = 300003;

    /// @notice thrown when upgrade fails
    uint256 internal constant AdminModule__UpgradeFailed = 300004;

    /// @notice thrown when emode token config becomes identical to NO_EMODE config (use removeTokenConfigFromEmode instead)
    uint256 internal constant AdminModule__EmodeConfigIdenticalToNoEmode = 300005;

    /***********************************|
    |     Liquidate Module Errors       | 
    |__________________________________*/

    /// @notice thrown when caller is not authorized
    uint256 internal constant LiquidateModule__Unauthorized = 301001;

    /// @notice thrown when position is not liquidatable
    uint256 internal constant LiquidateModule__NotLiquidatable = 301002;

    /// @notice thrown when position is invalid
    uint256 internal constant LiquidateModule__InvalidParams = 301003;

    /// @notice thrown when health factor limit exceeded after liquidation
    uint256 internal constant LiquidateModule__HfLimitExceeded = 301004;

    /***********************************|
    |         Base Module Errors        | 
    |__________________________________*/

    /// @notice thrown when caller is not authorized
    uint256 internal constant Base__Unauthorized = 302001;

    /// @notice thrown when validation fails
    uint256 internal constant Base__ValidationFailed = 302002;

    /// @notice thrown when invalid parameters are provided
    uint256 internal constant Base__InvalidParams = 302003;

    /***********************************|
    |         Helper Errors             | 
    |__________________________________*/

    /// @notice thrown when health factor check fails
    uint256 internal constant Helpers__HealthFactorFailed = 303001;

    /***********************************|
    |         ERC721 Errors             | 
    |__________________________________*/

    /// @notice thrown when invalid parameters are provided (e.g., zero address, invalid NFT ID)
    uint256 internal constant ERC721__InvalidParams = 304001;

    /// @notice thrown when caller is not authorized
    uint256 internal constant ERC721__Unauthorized = 304002;

    /// @notice thrown when recipient cannot receive ERC721 tokens
    uint256 internal constant ERC721__UnsafeRecipient = 304003;

    /// @notice thrown when index is out of bounds
    uint256 internal constant ERC721__OutOfBoundsIndex = 304004;

    /// @notice thrown when operation is invalid (e.g., transfer to zero address)
    uint256 internal constant ERC721__InvalidOperation = 304005;

    /// @notice thrown when max NFTs limit is reached
    uint256 internal constant ERC721__MaxNftsReached = 304006;
}
