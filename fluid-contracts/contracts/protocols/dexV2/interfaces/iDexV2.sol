// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

interface IFluidDexV2 {
    function startOperation(bytes calldata data_) external returns (bytes memory result_);

    function operate(
        uint256 dexType_,
        uint256 implementationId_,
        bytes memory data_
    ) external returns (bytes memory returnData_);

    function operateAdmin(
        uint256 dexType_,
        uint256 implementationId_,
        bytes memory data_
    ) external returns (bytes memory returnData_);

    function settle(
        address token_,
        int256 supplyAmount_,
        int256 borrowAmount_,
        int256 storeAmount_,
        address to_,
        bool isCallback_
    ) external payable;

    /// @notice Withdraws a token balance previously stored for the caller by DexV2 settlement fallback.
    /// @dev High-priority integration warning: if an integrating contract is used as `settle()` recipient, it must
    ///      expose a recovery path that calls this function and forwards recovered tokens to the
    ///      intended receiver. Otherwise a stored fallback payout can be blocked in that contract.
    function withdrawStoredTokens(address token_, uint256 amount_, address to_) external;

    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);    

    function readFromTransientStorage(bytes32 slot_) external view returns (uint256 result_);
}