// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./helpers.sol";

/// @notice Fluid Money Market ERC721 base contract. Implements the ERC721 standard, based on Solmate.
/// In addition, implements ERC721 Enumerable.
/// Modern, minimalist, and gas efficient ERC-721 with Enumerable implementation.
///
/// @author Instadapp
/// @author Modified Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract ERC721 is Helpers {
    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/
    
    function name() public pure returns (string memory) {
        return NFT_NAME;
    }

    function symbol() public pure returns (string memory) {
        return NFT_SYMBOL;
    }

    function tokenURI(uint256) public pure returns (string memory) {
        return "";
    }

    /// @notice returns `owner_` of NFT with `nftId_`
    function ownerOf(uint256 nftId_) public view returns (address owner_) {
        if ((owner_ = address(uint160(_nftConfigs[nftId_]))) == address(0))
            revert FluidMoneyMarketError(ErrorTypes.ERC721__InvalidParams);
    }

    /// @notice returns total count of NFTs owned by `owner_`
    function balanceOf(address owner_) public view returns (uint256) {
        if (owner_ == address(0)) revert FluidMoneyMarketError(ErrorTypes.ERC721__InvalidParams);

        return _nftOwnerConfig[owner_][0] & X32;
    }

    function totalSupply() public view returns (uint256) {
        return (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_NFTS) & X32;
    }

    function getApproved(uint256 nftId_) public view returns (address) {
        return _nftApproved[nftId_];
    }

    function isApprovedForAll(address owner_, address operator_) public view returns (bool) {
        return _nftApprovedForAll[owner_][operator_];
    }

    /// @notice approves an NFT with `nftId_` to be spent (transferred) by `spender_`
    function approve(address spender_, uint256 nftId_) public {
        address owner_ = address(uint160(_nftConfigs[nftId_]));
        if (!(msg.sender == owner_ || _nftApprovedForAll[owner_][msg.sender]))
            revert FluidMoneyMarketError(ErrorTypes.ERC721__Unauthorized);

        _nftApproved[nftId_] = spender_;

        emit Approval(owner_, spender_, nftId_);
    }

    /// @notice approves all NFTs owned by msg.sender to be spent (transferred) by `operator_`
    function setApprovalForAll(address operator_, bool approved_) public {
        _nftApprovedForAll[msg.sender][operator_] = approved_;

        emit ApprovalForAll(msg.sender, operator_, approved_);
    }

    /// @notice transfers an NFT with `nftId_` `from_` address `to_` address without safe check
    function transferFrom(address from_, address to_, uint256 nftId_) public {
        uint256 nftConfig_ = _nftConfigs[nftId_];
        if (from_ != address(uint160(nftConfig_))) revert FluidMoneyMarketError(ErrorTypes.ERC721__InvalidParams);

        if (!(msg.sender == from_ || _nftApprovedForAll[from_][msg.sender] || msg.sender == _nftApproved[nftId_]))
            revert FluidMoneyMarketError(ErrorTypes.ERC721__Unauthorized);

        // call _transfer with vaultId extracted from tokenConfig_
        _transfer(from_, to_, nftId_, (nftConfig_ >> MSL.BITS_NFT_CONFIGS_EMODE)); // Removed First 192 bits from nftConfig_ which are NFT owner and NFT index

        delete _nftApproved[nftId_];

        emit Transfer(from_, to_, nftId_);
    }

    /// @notice transfers an NFT with `nftId_` `from_` address `to_` address
    function safeTransferFrom(address from_, address to_, uint256 nftId_) public {
        transferFrom(from_, to_, nftId_);

        if (
            !(to_.code.length == 0 ||
                IERC721TokenReceiver(to_).onERC721Received(msg.sender, from_, nftId_, "") ==
                IERC721TokenReceiver.onERC721Received.selector)
        ) revert FluidMoneyMarketError(ErrorTypes.ERC721__UnsafeRecipient);
    }

    /// @notice transfers an NFT with `nftId_` `from_` address `to_` address, passing `data_` to `onERC721Received` callback
    function safeTransferFrom(address from_, address to_, uint256 nftId_, bytes calldata data_) public {
        transferFrom(from_, to_, nftId_);

        if (
            !((to_.code.length == 0) ||
                IERC721TokenReceiver(to_).onERC721Received(msg.sender, from_, nftId_, data_) ==
                IERC721TokenReceiver.onERC721Received.selector)
        ) revert FluidMoneyMarketError(ErrorTypes.ERC721__UnsafeRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721Enumerable LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns a token ID at a given `index_` of all the tokens stored by the contract.
    /// Use along with {totalSupply} to enumerate all tokens.
    function tokenByIndex(uint256 index_) external view returns (uint256) {
        if (index_ >= totalSupply()) {
            revert FluidMoneyMarketError(ErrorTypes.ERC721__OutOfBoundsIndex);
        }
        return index_ + 1;
    }

    /// @notice Returns a token ID owned by `owner_` at a given `index_` of its token list.
    /// Use along with {balanceOf} to enumerate all of `owner_`'s tokens.
    function tokenOfOwnerByIndex(address owner_, uint256 index_) external view returns (uint256) {
        if (index_ >= balanceOf(owner_)) {
            revert FluidMoneyMarketError(ErrorTypes.ERC721__OutOfBoundsIndex);
        }

        index_ = index_ + 1;
        return (_nftOwnerConfig[owner_][index_ / 8] >> ((index_ % 8) * 32)) & X32;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId_) public pure returns (bool) {
        return
            interfaceId_ == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId_ == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId_ == 0x5b5e139f || // ERC165 Interface ID for ERC721Metadata
            interfaceId_ == 0x780e9d63; // ERC165 Interface ID for ERC721Enumberable
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

     function _transfer(address from_, address to_, uint256 id_, uint256 nftData_) internal {
        if (to_ == address(0)) {
            revert FluidMoneyMarketError(ErrorTypes.ERC721__InvalidOperation);
        } else if (from_ == address(0)) {
            _add(to_, id_, nftData_);
        } else if (to_ != from_) {
            _remove(from_, id_);
            _add(to_, id_, nftData_);
        }
    }

    function _add(address user_, uint256 id_, uint256 nftData_) private {
        uint256 nftOwnerConfig_ = _nftOwnerConfig[user_][0];
        unchecked {
            // index starts from `1`
            uint256 balanceOf_ = (nftOwnerConfig_ & X32) + 1;

            _nftConfigs[id_] = (uint160(user_) | (balanceOf_ << MSL.BITS_NFT_CONFIGS_NFT_INDEX) | (nftData_ << MSL.BITS_NFT_CONFIGS_EMODE));

            _nftOwnerConfig[user_][0] = (nftOwnerConfig_ & ~X32) | (balanceOf_);

            uint256 wordIndex_ = (balanceOf_ / 8);
            _nftOwnerConfig[user_][wordIndex_] = _nftOwnerConfig[user_][wordIndex_] | (id_ << ((balanceOf_ % 8) * 32));
        }
    }

    function _remove(address user_, uint256 id_) private {
        uint256 temp_ = _nftConfigs[id_];

        // fetching `id_` details and deleting it.
        uint256 tokenIndex_ = (temp_ >> MSL.BITS_NFT_CONFIGS_NFT_INDEX) & X32;
        _nftConfigs[id_] = 0;

        // fetching & updating balance
        temp_ = _nftOwnerConfig[user_][0];
        uint256 lastTokenIndex_ = (temp_ & X32); // (lastTokenIndex_ = balanceOf)
        _nftOwnerConfig[user_][0] = (temp_ & ~X32) | (lastTokenIndex_ - 1);

        {
            unchecked {
                uint256 lastTokenWordIndex_ = (lastTokenIndex_ / 8);
                uint256 lastTokenBitShift_ = (lastTokenIndex_ % 8) * 32;
                temp_ = _nftOwnerConfig[user_][lastTokenWordIndex_];

                // replace `id_` tokenId with `last` tokenId.
                if (lastTokenIndex_ != tokenIndex_) {
                    uint256 wordIndex_ = (tokenIndex_ / 8);
                    uint256 bitShift_ = (tokenIndex_ % 8) * 32;

                    // temp_ here is _ownerConfig[user_][lastTokenWordIndex_];
                    uint256 lastTokenId_ = uint256((temp_ >> lastTokenBitShift_) & X32);
                    if (wordIndex_ == lastTokenWordIndex_) {
                        // this case, when lastToken and currentToken are in same slot.
                        // updating temp_ as we will remove the lastToken from this slot itself
                        temp_ = (temp_ & ~(X32 << bitShift_)) | (lastTokenId_ << bitShift_);
                    } else {
                        _nftOwnerConfig[user_][wordIndex_] =
                            (_nftOwnerConfig[user_][wordIndex_] & ~(X32 << bitShift_)) |
                            (lastTokenId_ << bitShift_);
                    }
                    _nftConfigs[lastTokenId_] =
                        (_nftConfigs[lastTokenId_] & ~(X32 << MSL.BITS_NFT_CONFIGS_NFT_INDEX)) |
                        (tokenIndex_ << MSL.BITS_NFT_CONFIGS_NFT_INDEX);
                }

                // temp_ here is _ownerConfig[user_][lastTokenWordIndex_];
                _nftOwnerConfig[user_][lastTokenWordIndex_] = temp_ & ~(X32 << lastTokenBitShift_);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to_, uint256 nftData_) internal virtual returns (uint256 nftId_) {
        // Mint a new NFT
        uint256 moneyMarketVariables_ = _moneyMarketVariables;
        // Assigning the new NFT ID
        nftId_ = ((moneyMarketVariables_ >> MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_NFTS) & X32) + 1;
        if (nftId_ >= X32) revert FluidMoneyMarketError(ErrorTypes.ERC721__MaxNftsReached);

        // Updating the total NFTs in the money market variables
        _moneyMarketVariables = (moneyMarketVariables_ & ~(X32 << MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_NFTS)) | 
            (nftId_ << MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_NFTS);

        _transfer(address(0), to_, nftId_, nftData_);

        emit Transfer(address(0), to_, nftId_);
    }
}
