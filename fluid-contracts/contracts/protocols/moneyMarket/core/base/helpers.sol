// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./events.sol";

abstract contract Helpers is CommonImport {
    // Single modifier to handle eth sent, from address and reentrancy guard
    modifier _handleMsgDetails() {
        if (_msgSender != address(0)) revert FluidMoneyMarketError(ErrorTypes.Base__ValidationFailed); // because of this, this modifier also acts as a reentrancy guard
        _msgSender = msg.sender;
        _msgValue = msg.value;

        _;

        if (_msgValue > 0) SafeTransfer.safeTransferNative(_msgSender, _msgValue);
        delete _msgValue;
        delete _msgSender;
    }

    /// @dev            do any arbitrary call
    /// @param target_  Address to which the call needs to be delegated
    /// @param data_    Data to execute at the delegated address
    function _spell(address target_, bytes memory data_) internal returns (bytes memory response_) {
        assembly {
            let succeeded := delegatecall(gas(), target_, add(data_, 0x20), mload(data_), 0, 0)
            let size := returndatasize()

            response_ := mload(0x40)
            mstore(0x40, add(response_, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            mstore(response_, size)
            returndatacopy(add(response_, 0x20), 0, size)

            if iszero(succeeded) {
                // throw if delegatecall failed
                returndatacopy(0x00, 0x00, size)
                revert(0x00, size)
            }
        }
    }
}
