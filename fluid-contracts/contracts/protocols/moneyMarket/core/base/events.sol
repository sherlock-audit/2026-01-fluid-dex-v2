// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./interfaces.sol";

/*//////////////////////////////////////////////////////////////
                            NFT EVENTS
//////////////////////////////////////////////////////////////*/

event Transfer(address indexed from, address indexed to, uint256 indexed id);

event Approval(address indexed owner, address indexed spender, uint256 indexed id);

event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

/*//////////////////////////////////////////////////////////////
                    SECONDARY FUNCTIONS EVENTS
//////////////////////////////////////////////////////////////*/

/// @notice Emitted when an NFT's emode is changed
/// @param nftId The NFT ID
/// @param oldEmode The previous emode
/// @param newEmode The new emode
event EmodeChanged(uint256 indexed nftId, uint256 indexed oldEmode, uint256 indexed newEmode);
