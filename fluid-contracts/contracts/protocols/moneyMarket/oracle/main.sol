// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { IMMOracle } from "./iMMOracle.sol";
import { Variables } from "./variables.sol";
import { Error } from "./error.sol";
import { ErrorTypes } from "./errorTypes.sol";
import { Events } from "./events.sol";
import { IFluidOracle, IERC20, IFluidCappedRate, IChainlinkAggregatorV3 } from "./interfaces.sol";

interface IReadFromStorage {
    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);
}

abstract contract FluidMoneyMarketOracleCore is Variables, Error {
    /// @dev validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidMMOracleError(ErrorTypes.MMOracle__AddressZero);
        }
        _;
    }

    /// @dev gets the governance address at Liquidity
    function _getGovernanceAddr() internal view returns (address governance_) {
        governance_ = address(uint160(IReadFromStorage(LIQUIDITY).readFromStorage(LIQUIDITY_GOVERNANCE_SLOT)));
    }

    /// @dev Validates that an address is governance (at Liquidity)
    modifier onlyGovernance() {
        if (msg.sender != _getGovernanceAddr()) {
            revert FluidMMOracleError(ErrorTypes.MMOracle__Unauthorized);
        }
        _;
    }
}

abstract contract FluidMoneyMarketOracleUpgradeable is FluidMoneyMarketOracleCore, UUPSUpgradeable {
    function _authorizeUpgrade(address) internal override onlyGovernance {}
}

abstract contract FluidMoneyMarketOracleAdmin is FluidMoneyMarketOracleUpgradeable, Events {
    /// @dev Validates that an address is either governance (at Liquidity) or TEAM_MULTISIG
    modifier onlyGovernanceOrMultisig() {
        if (msg.sender != _getGovernanceAddr() && msg.sender != TEAM_MULTISIG) {
            revert FluidMMOracleError(ErrorTypes.MMOracle__Unauthorized);
        }
        _;
    }

    /// @notice Sets a single Oracle configuration entry.
    /// @dev Only callable by governance or the multisig, multisig can only add new configs but not modify existing ones.
    /// @param token_ The address of the token for which to set the oracle configuration.
    /// @param eMode_ The identifier of the eMode for the asset.
    /// @param isOperate_ The operation type: 0 = liquidate, 1 = operate.
    /// @param isCollateral_ The collateral role: 0 = debt, 1 = collateral.
    /// @param sourceCfg1_ The configuration struct for the first oracle source.
    /// @param sourceCfg2_ The configuration struct for the second oracle source.
    /// @param sourceCfg3_ The configuration struct for the third oracle source.
    function setConfigSingle(
        address token_,
        uint256 eMode_,
        uint8 isOperate_,
        uint8 isCollateral_,
        SetSourceConfig memory sourceCfg1_,
        SetSourceConfig memory sourceCfg2_,
        SetSourceConfig memory sourceCfg3_
    ) external onlyGovernanceOrMultisig validAddress(token_) {
        if (isOperate_ > 1 || isCollateral_ > 1) {
            revert FluidMMOracleError(ErrorTypes.MMOracle__InvalidParams);
        }

        _validateEMode(eMode_);

        OracleConfig memory oracleCfg_ = _parseAndValidateOracleConfig(sourceCfg1_, sourceCfg2_, sourceCfg3_);

        _setConfigSingle(token_, eMode_, isOperate_, isCollateral_, oracleCfg_);
    }

    /// @notice Sets multiple oracle configs for a token and eMode.
    /// governance is allowed to set any config, Multisig is allowed to add new configs only.
    /// @dev To configure only a single price source, set `sourceCfg2_` and `sourceCfg3_` to default values
    /// ({sourceType: 0, source: address(0), multiplier: 0}).
    /// @param token_ The token address
    /// @param eMode_ The eMode identifier. Note emode 0 is used as default fallback pricing.
    /// @param isOperate_ 0 = liquidate rates; 1= operate rates; 2 = both liquidate and operate
    /// @param isCollateral_ 0 = debt rates; 1= collateral rates; 2 = both debt and collateral
    /// @param sourceCfg1_ The configuration for the first price source (required)
    /// @param sourceCfg2_ The configuration for the second price source (optional, set to {0, address(0), 0} to skip)
    /// @param sourceCfg3_ The configuration for the third price source (optional, set to {0, address(0), 0} to skip)
    function setConfigMultiple(
        address token_,
        uint256 eMode_,
        uint8 isOperate_,
        uint8 isCollateral_,
        SetSourceConfig memory sourceCfg1_,
        SetSourceConfig memory sourceCfg2_,
        SetSourceConfig memory sourceCfg3_
    ) external onlyGovernanceOrMultisig validAddress(token_) {
        if (isOperate_ > 2 || isCollateral_ > 2 || (isOperate_ != 2 && isCollateral_ != 2)) {
            // for setting a single config, should use single method.
            revert FluidMMOracleError(ErrorTypes.MMOracle__InvalidParams);
        }

        _validateEMode(eMode_);

        OracleConfig memory oracleCfg_ = _parseAndValidateOracleConfig(sourceCfg1_, sourceCfg2_, sourceCfg3_);

        if (isOperate_ == 2 && isCollateral_ == 2) {
            _setConfigSingle(token_, eMode_, 0, 0, oracleCfg_);
            _setConfigSingle(token_, eMode_, 0, 1, oracleCfg_);
            _setConfigSingle(token_, eMode_, 1, 0, oracleCfg_);
            _setConfigSingle(token_, eMode_, 1, 1, oracleCfg_);
        } else if (isOperate_ == 2) {
            _setConfigSingle(token_, eMode_, 0, isCollateral_, oracleCfg_);
            _setConfigSingle(token_, eMode_, 1, isCollateral_, oracleCfg_);
        } else if (isCollateral_ == 2) {
            _setConfigSingle(token_, eMode_, isOperate_, 0, oracleCfg_);
            _setConfigSingle(token_, eMode_, isOperate_, 1, oracleCfg_);
        } else {
            // case should not be possible, reverting just to be sure.
            revert FluidMMOracleError(ErrorTypes.MMOracle__InvalidParams);
        }
    }

    /// @notice Removes a single oracle config for a token, eMode, isOperate, and isCollateral.
    /// Only governance can remove a config.
    /// @param token_ The token address
    /// @param eMode_ The eMode identifier
    /// @param isOperate_ 0 = liquidate, 1 = operate
    /// @param isCollateral_ 0 = debt, 1 = collateral
    function removeConfigSingle(address token_, uint256 eMode_, uint8 isOperate_, uint8 isCollateral_) external onlyGovernance validAddress(token_) {
        if (isOperate_ > 1 || isCollateral_ > 1) {
            revert FluidMMOracleError(ErrorTypes.MMOracle__InvalidParams);
        }

        if (!_configExists(token_, eMode_, isOperate_, isCollateral_)) {
            revert FluidMMOracleError(ErrorTypes.MMOracle__ConfigDoesNotExist);
        }

        // Reset the config to default
        delete config[token_][eMode_][isOperate_][isCollateral_];

        // Remove the config entry from configsMap[token_] array
        ConfigMap[] storage arr_ = configsMap[token_];
        for (uint i = 0; i < arr_.length; i++) {
            if (arr_[i].eMode == eMode_ && arr_[i].isOperate == (isOperate_ == 0 ? false : true) && arr_[i].isCollateral == (isCollateral_ == 0 ? false : true)) {
                // Remove by swapping last with current and popping.
                arr_[i] = arr_[arr_.length - 1];
                arr_.pop();
                break;
            }
        }

        emit OracleConfigRemoved(token_, eMode_, isOperate_, isCollateral_);
    }

    /// ----------------- INTERNAL METHODS -----------------

    /// @dev Checks if a configuration exists for the given token, eMode, operate, and collateral flags.
    /// @param token_ The token address
    /// @param eMode_ The eMode identifier
    /// @param isOperate_ 0 = liquidate, 1 = operate
    /// @param isCollateral_ 0 = debt, 1 = collateral
    /// @return exists_ True if at least one config exists for the specified parameters
    function _configExists(address token_, uint256 eMode_, uint8 isOperate_, uint8 isCollateral_) internal view returns (bool exists_) {
        return (config[token_][eMode_][isOperate_][isCollateral_].sourceType1 > 0);
    }

    /// @dev Prepares and verifies OracleConfig from source configs, combining source verification and struct construction.
    function _parseAndValidateOracleConfig(
        SetSourceConfig memory sourceCfg1_,
        SetSourceConfig memory sourceCfg2_,
        SetSourceConfig memory sourceCfg3_
    ) internal returns (OracleConfig memory oracleCfg_) {
        _verifySourceConfig(sourceCfg1_.sourceType, sourceCfg1_.source, sourceCfg1_.multiplier);
        oracleCfg_.sourceType1 = sourceCfg1_.sourceType;
        oracleCfg_.source1 = sourceCfg1_.source;
        oracleCfg_.multiplier1 = sourceCfg1_.multiplier;

        if (sourceCfg2_.sourceType != 0) {
            _verifySourceConfig(sourceCfg2_.sourceType, sourceCfg2_.source, sourceCfg2_.multiplier);
            oracleCfg_.sourceType2 = sourceCfg2_.sourceType;
            oracleCfg_.source2 = sourceCfg2_.source;
            oracleCfg_.multiplier2 = sourceCfg2_.multiplier;
        }
        if (sourceCfg3_.sourceType != 0) {
            if (sourceCfg2_.sourceType == 0) {
                revert FluidMMOracleError(ErrorTypes.MMOracle__InvalidSource);
            }
            _verifySourceConfig(sourceCfg3_.sourceType, sourceCfg3_.source, sourceCfg3_.multiplier);
            oracleCfg_.sourceType3 = sourceCfg3_.sourceType;
            oracleCfg_.source3 = sourceCfg3_.source;
            oracleCfg_.multiplier3 = sourceCfg3_.multiplier;
        }
    }

    /// @dev Set a single configuration entry for a specific operate/collateral combination.
    ///      Stores the provided OracleConfig at [token_][eMode_][isOperate_][isCollateral_].
    ///      If the configuration does not exist yet, adds it to configsMap.
    ///      Reverts if TEAM_MULTISIG tries to modify an existing config.
    /// @param token_ The token address
    /// @param eMode_ The eMode identifier
    /// @param isOperate_ 0 = liquidate, 1 = operate
    /// @param isCollateral_ 0 = debt, 1 = collateral
    /// @param oracleCfg_ The OracleConfig struct to set
    function _setConfigSingle(address token_, uint256 eMode_, uint8 isOperate_, uint8 isCollateral_, OracleConfig memory oracleCfg_) internal {
        bool configExists_ = _configExists(token_, eMode_, isOperate_, isCollateral_);
        if (configExists_ && msg.sender == TEAM_MULTISIG) {
            revert FluidMMOracleError(ErrorTypes.MMOracle__Unauthorized);
        }

        // Write config to storage
        config[token_][eMode_][isOperate_][isCollateral_] = oracleCfg_;
        if (!configExists_) {
            configsMap[token_].push(
                ConfigMap({ eMode: uint240(eMode_), isOperate: isOperate_ == 0 ? false : true, isCollateral: isCollateral_ == 0 ? false : true })
            );
        }

        emit OracleConfigSet(
            token_,
            eMode_,
            isOperate_,
            isCollateral_,
            oracleCfg_.sourceType1,
            oracleCfg_.source1,
            oracleCfg_.multiplier1,
            oracleCfg_.sourceType2,
            oracleCfg_.source2,
            oracleCfg_.multiplier2,
            oracleCfg_.sourceType3,
            oracleCfg_.source3,
            oracleCfg_.multiplier3
        );
    }

    /// @dev Validates that the eMode is valid by checking against total emodes listed at Money Market
    function _validateEMode(uint256 eMode_) internal view {
        uint256 totalEmodesListed_ = IReadFromStorage(MONEY_MARKET).readFromStorage(bytes32(uint256(MM_SLOT_TOTAL_EMODES)));
        totalEmodesListed_ = (totalEmodesListed_ >> MM_BITPOS_TOTAL_EMODES) & MM_MASK_TOTAL_EMODES;
        if (eMode_ > totalEmodesListed_) {
            revert FluidMMOracleError(ErrorTypes.MMOracle__InvalidEMode);
        }
    }

    /// @dev Verifies that the source configuration is valid for the given source type, address, and multiplier.
    function _verifySourceConfig(uint8 sourceType_, address source_, int8 multiplier_) internal {
        if (source_ == address(0)) {
            revert FluidMMOracleError(ErrorTypes.MMOracle__AddressZero);
        }
        if (multiplier_ > MAX_MULTIPLIER || multiplier_ < MIN_MULTIPLIER) {
            revert FluidMMOracleError(ErrorTypes.MMOracle__InvalidMultiplier);
        }

        if (sourceType_ == 1 && !_isCappedRate(source_)) {
            revert FluidMMOracleError(ErrorTypes.MMOracle__InvalidSource);
        } else if (sourceType_ == 2 && !_isChainlinkFeed(source_)) {
            revert FluidMMOracleError(ErrorTypes.MMOracle__InvalidSource);
        } else if (sourceType_ > 2 || sourceType_ == 0) {
            revert FluidMMOracleError(ErrorTypes.MMOracle__InvalidSource);
        }
    }

    /// @dev Checks if the provided address is a valid Chainlink feed by calling latestRoundData.
    function _isChainlinkFeed(address contract_) internal view returns (bool) {
        try IChainlinkAggregatorV3(contract_).latestRoundData() returns (uint80 roundId, int256, uint256, uint256, uint80) {
            if (roundId > 0) {
                return true;
            }
        } catch {}
        return false;
    }

    /// @dev Checks if the provided address implements the FluidCappedRate interface with required methods.
    function _isCappedRate(address contract_) internal returns (bool) {
        try IFluidCappedRate(contract_).centerPrice() returns (uint256 value) {
            if (value == 0) {
                return false;
            }
        } catch {
            return false;
        }
        try IFluidCappedRate(contract_).getExchangeRateOperateDebt() returns (uint256 value) {
            if (value == 0) {
                return false;
            }
        } catch {
            return false;
        }
        return true;
    }
}

abstract contract FluidMoneyMarketOracleSourceRead is FluidMoneyMarketOracleCore {
    /// @dev Reads the latest price from a Chainlink aggregator, reverting if feed is stale.
    function _readChainlinkSource(address feed_, bool isOperate_) internal view returns (uint256 rate_) {
        try IChainlinkAggregatorV3(feed_).latestRoundData() returns (uint80, int256 exchangeRate_, uint256, uint256 updatedAt_, uint80) {
            if (isOperate_) {
                if (updatedAt_ + MAX_UPDATE_TIMESPAN_OPERATE < block.timestamp) {
                    revert FluidMMOracleError(ErrorTypes.MMOracle__ChainlinkStale);
                }
            } else {
                if (updatedAt_ + MAX_UPDATE_TIMESPAN_LIQUIDATE < block.timestamp) {
                    revert FluidMMOracleError(ErrorTypes.MMOracle__ChainlinkStale);
                }
            }
            if (exchangeRate_ < 0) {
                revert FluidMMOracleError(ErrorTypes.MMOracle__RateInvalid);
            }
            return uint256(exchangeRate_);
        } catch {}
    }

    /// @dev Reads the latest exchange rate from a Fluid source, depending on operate and collateral flags.
    function _readFluidSource(address oracle_, bool isOperate_, bool isCollateral_) internal view returns (uint256 rate_) {
        if (isOperate_) {
            if (isCollateral_) {
                try IFluidOracle(oracle_).getExchangeRateOperate() returns (uint256 exchangeRate_) {
                    return exchangeRate_;
                } catch {}
            } else {
                try IFluidCappedRate(oracle_).getExchangeRateOperateDebt() returns (uint256 exchangeRate_) {
                    return exchangeRate_;
                } catch {}
            }
        } else {
            if (isCollateral_) {
                try IFluidOracle(oracle_).getExchangeRateLiquidate() returns (uint256 exchangeRate_) {
                    return exchangeRate_;
                } catch {}
            } else {
                try IFluidCappedRate(oracle_).getExchangeRateLiquidateDebt() returns (uint256 exchangeRate_) {
                    return exchangeRate_;
                } catch {}
            }
        }
    }

    /// @dev Reads the price from the given source and applies multiplier based on configuration.
    function _readSource(address source_, int8 multiplier_, uint8 sourceType_, bool isOperate_, bool isCollateral_) internal view returns (uint256 value_) {
        if (sourceType_ == 1) {
            // FluidCappedRate
            value_ = _readFluidSource(source_, isOperate_, isCollateral_);
        } else if (sourceType_ == 2) {
            // Chainlink
            value_ = _readChainlinkSource(source_, isOperate_);
        } else {
            revert FluidMMOracleError(ErrorTypes.MMOracle__InvalidSourceType);
        }

        if (multiplier_ > 0) {
            value_ = value_ * uint256(10 ** uint8(multiplier_));
        } else if (multiplier_ < 0) {
            unchecked {
                value_ = value_ / uint256(10 ** uint8(-multiplier_));
            }
        } // else when multiplier is 0, no scaling is needed

        if (value_ == 0) {
            revert FluidMMOracleError(ErrorTypes.MMOracle__RateZero);
        }

        return value_;
    }

    /// @dev for try catch in view configs method
    function readSource(address source_, int8 multiplier_, uint8 sourceType_, bool isOperate_, bool isCollateral_) external view returns (uint256 value_) {
        return _readSource(source_, multiplier_, sourceType_, isOperate_, isCollateral_);
    }
}

/// @title FluidMoneyMarketOracle
/// @notice Core implementation of the Fluid Money Market Oracle, mapping token => USD value in 1e27 decimals.
contract FluidMoneyMarketOracle is IMMOracle, FluidMoneyMarketOracleAdmin, FluidMoneyMarketOracleSourceRead {
    constructor(address liquidity_, address moneyMarket_) validAddress(liquidity_) validAddress(moneyMarket_) {
        LIQUIDITY = liquidity_;
        MONEY_MARKET = moneyMarket_;
    }

    /// @notice Returns the price for a given token, emode, operate, and collateral state.
    ///         If pricing config for given emode is not available, the method will fallback to pricing for emode 0.
    /// @param token0_ Address of the token to fetch price for
    /// @param emode_ eMode for pricing
    /// @param isOperate_ Flag indicating operate or liquidate mode
    /// @param isCollateral_ Flag indicating collateral or debt price logic
    /// @return price_ Quoted price (scaled to ORACLE_PRECISION)
    function getPrice(address token0_, uint256 emode_, bool isOperate_, bool isCollateral_) external view returns (uint256 price_) {
        // Read only slot 1 (single storage read) by accessing a storage pointer to the struct
        OracleConfig storage config_ = config[token0_][emode_][isOperate_ ? 1 : 0][isCollateral_ ? 1 : 0];
        uint8 sourceType_ = config_.sourceType1;
        if (sourceType_ == 0) {
            // fallback to default pricing for emode 0
            // if(emode_ == 0){ revert FluidMMOracleError(ErrorTypes.MMOracle__NoConfig); } // skip: not optimizing gas for failure case
            config_ = config[token0_][0][isOperate_ ? 1 : 0][isCollateral_ ? 1 : 0];
            sourceType_ = config_.sourceType1;
            if (sourceType_ == 0) {
                revert FluidMMOracleError(ErrorTypes.MMOracle__NoConfig);
            }
        }

        address source_ = config_.source1;
        int8 multiplier_ = config_.multiplier1;

        price_ = _readSource(source_, multiplier_, sourceType_, isOperate_, isCollateral_);

        sourceType_ = config_.sourceType2;
        if (sourceType_ == 0) {
            return price_;
        }

        source_ = config_.source2;
        multiplier_ = config_.multiplier2;
        price_ = (price_ * _readSource(source_, multiplier_, sourceType_, isOperate_, isCollateral_)) / ORACLE_PRECISION;

        sourceType_ = config_.sourceType3;
        if (sourceType_ == 0) {
            return price_;
        }

        source_ = config_.source3;
        multiplier_ = config_.multiplier3;
        price_ = (price_ * _readSource(source_, multiplier_, sourceType_, isOperate_, isCollateral_)) / ORACLE_PRECISION;

        if (price_ == 0) {
            revert FluidMMOracleError(ErrorTypes.MMOracle__RateZero);
        }
        return price_;
    }

    /// @notice Gets all configured oracle sources for a token, including their effective rates.
    /// @dev    Individual rate reads are wrapped in try/catch. If any rate source reverts (e.g. stale Chainlink feed),
    ///         that rate defaults to 0, which propagates into the final `price` as 0. Consumers should treat
    ///         a `price` of 0 (or any individual `rate` of 0 when its `sourceType` is configured) as an error / stale state.
    /// @param token_ The address of the token to query
    /// @return infos_ Array of ConfiguredTokenOracle showing how each eMode/operate/collateral config is set up
    function getConfiguredTokenOracles(address token_) external view returns (ConfiguredTokenOracle[] memory infos_) {
        ConfigMap[] memory modes_ = configsMap[token_];
        uint256 len_ = modes_.length;
        infos_ = new ConfiguredTokenOracle[](len_);

        string memory tokenSymbol_;
        // Try/catch in case the token does not implement symbol() correctly
        try IERC20(token_).symbol() returns (string memory sym_) {
            tokenSymbol_ = sym_;
        } catch {
            tokenSymbol_ = "NATIVE";
        }
        OracleConfig memory cfg_;
        for (uint256 i = 0; i < len_; ++i) {
            cfg_ = config[token_][modes_[i].eMode][modes_[i].isOperate ? 1 : 0][modes_[i].isCollateral ? 1 : 0];

            uint256 rate1_;
            uint256 rate2_;
            uint256 rate3_;

            try this.readSource(cfg_.source1, cfg_.multiplier1, cfg_.sourceType1, modes_[i].isOperate, modes_[i].isCollateral) returns (uint256 val) {
                rate1_ = val;
            } catch {}
            if (cfg_.sourceType2 > 0) {
                try this.readSource(cfg_.source2, cfg_.multiplier2, cfg_.sourceType2, modes_[i].isOperate, modes_[i].isCollateral) returns (uint256 val) {
                    rate2_ = val;
                } catch {}
            }
            if (cfg_.sourceType3 > 0) {
                try this.readSource(cfg_.source3, cfg_.multiplier3, cfg_.sourceType3, modes_[i].isOperate, modes_[i].isCollateral) returns (uint256 val) {
                    rate3_ = val;
                } catch {}
            }

            uint256 price_ = rate1_;
            if (cfg_.sourceType2 > 0) {
                price_ = (price_ * rate2_) / ORACLE_PRECISION;
            }
            if (cfg_.sourceType3 > 0) {
                price_ = (price_ * rate3_) / ORACLE_PRECISION;
            }

            infos_[i] = ConfiguredTokenOracle({
                token: token_,
                symbol: tokenSymbol_,
                eMode: modes_[i].eMode,
                isOperate: modes_[i].isOperate,
                isCollateral: modes_[i].isCollateral,
                sourceType1: cfg_.sourceType1,
                source1: cfg_.source1,
                multiplier1: cfg_.multiplier1,
                sourceType2: cfg_.sourceType2,
                source2: cfg_.source2,
                multiplier2: cfg_.multiplier2,
                sourceType3: cfg_.sourceType3,
                source3: cfg_.source3,
                multiplier3: cfg_.multiplier3,
                rate1: rate1_,
                rate2: rate2_,
                rate3: rate3_,
                price: price_
            });
        }
    }
}
