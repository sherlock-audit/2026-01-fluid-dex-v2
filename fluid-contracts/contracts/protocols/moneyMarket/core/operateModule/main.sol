// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./helpers.sol";

/// @title FluidMoneyMarketOperateModule
/// @notice Implementation module for Money Market operate functionality
/// @dev Called via delegatecall from the main FluidMoneyMarket contract
contract FluidMoneyMarketOperateModule is Helpers {

    address internal immutable THIS_ADDRESS;

    /// @dev Ensures function is called via delegatecall, not directly
    modifier _onlyDelegateCall() {
        if (address(this) == THIS_ADDRESS) revert();
        _;
    }

    /// @notice Initializes the Operate Module with Liquidity and DexV2 addresses
    /// @param liquidity_ The FluidLiquidity contract address
    /// @param dexV2_ The FluidDexV2 contract address
    constructor(address liquidity_, address dexV2_) {
        THIS_ADDRESS = address(this);
        LIQUIDITY = IFluidLiquidity(liquidity_);
        DEX_V2 = IFluidDexV2(dexV2_);
    }

    /// @notice Executes position operations: create/modify NFTs and positions
    /// @dev Handles four flows:
    ///      1. nftId=0: Create new NFT and first position
    ///      2. nftId>0, positionIndex=0: Add new position to existing NFT
    ///      3. nftId>0, positionIndex>0, type 1/2: Modify normal supply/borrow position
    ///      4. nftId>0, positionIndex>0, type 3/4: Modify D3/D4 position via DexV2
    /// @param nftId_ NFT ID (0 to create new NFT)
    /// @param positionIndex_ Position index within NFT (0 to create new position)
    /// @param actionData_ Encoded action parameters specific to position type
    /// @return The resulting (nftId, positionIndex) tuple
    function operate(
        uint256 nftId_, 
        uint256 positionIndex_, 
        bytes calldata actionData_
    ) _onlyDelegateCall external payable returns (uint256, uint256) {
        if (nftId_ == 0) {
            // This means that the user wants to create a new NFT
            nftId_ = IExternalCallForMint(address(this)).mint();
            positionIndex_ = _createPosition(nftId_, _nftConfigs[nftId_], NO_EMODE, actionData_); // A new NFT starts with no emode, i.e. 0
        } else {
            uint256 nftConfig_ = _nftConfigs[nftId_];
            if (address(uint160(nftConfig_)) != msg.sender) revert(); // Either the caller is not the owner of the NFT or this NFT doesn't exist
            
            uint256 emode_ = (nftConfig_ >> MSL.BITS_NFT_CONFIGS_EMODE) & X12;

            if (positionIndex_ == 0) {
                // This means that the user wants to create a new position in an exisiting NFT
                positionIndex_ = _createPosition(nftId_, nftConfig_, emode_, actionData_);
            } else {
                // This means the user wants to interact with an exisiting position
                if (positionIndex_ > (nftConfig_ >> MSL.BITS_NFT_CONFIGS_NUMBER_OF_POSITIONS) & X10) revert();

                uint256 positionData_ = _positionData[nftId_][positionIndex_];
                uint256 positionType_ = (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE) & X5;

                if (positionType_ == NORMAL_SUPPLY_POSITION_TYPE) _processNormalSupplyAction(nftId_, nftConfig_, positionIndex_, positionData_, emode_, actionData_);
                else if (positionType_ == NORMAL_BORROW_POSITION_TYPE) _processNormalBorrowAction(nftId_, nftConfig_, positionIndex_, positionData_, emode_, actionData_);
                else if (positionType_ == D3_POSITION_TYPE || positionType_ == D4_POSITION_TYPE) {
                    DexKey memory dexKey_;
                    StartOperationParams memory s_ =  StartOperationParams({
                        isOperate: IS_OPERATE,
                        positionType: positionType_,
                        nftId: nftId_,
                        nftConfig: nftConfig_,
                        token0Index: (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_0_INDEX) & X12,
                        token1Index: (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_1_INDEX) & X12,
                        positionIndex: positionIndex_,
                        tickLower: 0,
                        tickUpper: 0,
                        positionSalt: keccak256(abi.encode(nftId_)),
                        emode: emode_,
                        permissionlessTokens: false,
                        actionData: actionData_
                    });

                    {
                        uint256 token0Configs_ = _getTokenConfigs(emode_, s_.token0Index);
                        uint256 token1Configs_ = _getTokenConfigs(emode_, s_.token1Index);

                        if (positionType_ == D3_POSITION_TYPE) {
                            if (
                                (token0Configs_ >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) & X3 == COLLATERAL_CLASS_PERMISSIONLESS && 
                                (token1Configs_ >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) & X3 == COLLATERAL_CLASS_PERMISSIONLESS
                                ) {
                                s_.permissionlessTokens = true;
                            }
                        } else if (positionType_ == D4_POSITION_TYPE) {
                            if (
                                (token0Configs_ >> MSL.BITS_TOKEN_CONFIGS_DEBT_CLASS) & X3 == DEBT_CLASS_PERMISSIONLESS && 
                                (token1Configs_ >> MSL.BITS_TOKEN_CONFIGS_DEBT_CLASS) & X3 == DEBT_CLASS_PERMISSIONLESS
                                ) {
                                s_.permissionlessTokens = true;
                            }
                        }

                        (dexKey_, s_.tickLower, s_.tickUpper) = _decodeD3D4PositionData(positionData_, token0Configs_, token1Configs_);
                    }

                    // NOTE: No need to check these here because this must be checked while creating the position
                    // if (dexKey_.tickSpacing > MAX_TICK_SPACING ||
                    //     s_.tickLower >= s_.tickUpper ||
                    //     s_.tickLower < MIN_TICK ||
                    //     s_.tickUpper > MAX_TICK
                    // ) revert();

                    DEX_V2.startOperation(abi.encode(dexKey_, s_));
                } else revert(); // This shouldn't ever happen
            }
        }

        emit LogOperate(nftId_, positionIndex_, msg.sender, actionData_);
        
        return (nftId_, positionIndex_);
    }
}
