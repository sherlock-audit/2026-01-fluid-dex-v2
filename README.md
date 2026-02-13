# Fluid DEX v2 contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the **Issues** page in your private contest repo (label issues as **Medium** or **High**)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
Ethereum, Plasma, Arbitrum, Base, and Polygon. The code requires cancun and transient storage supported before deployment.
___

### Q: If you are integrating tokens, are you allowing only whitelisted tokens to work with the codebase or any complying with the standard? Are they assumed to have certain properties, e.g. be non-reentrant? Are there any types of [weird tokens](https://github.com/d-xo/weird-erc20) you want to integrate?
The initial launch will be permissioned, with token and pool listings restricted to the team. Only standard ERC-20 tokens are intended to be integrated, and no “weird” tokens are planned. The codebase assumes tokens fully comply with the ERC-20 standard. Supported token decimals are between 6 and 18; further, the DEX contracts explicitly disallow tokens with 15, 16, or 17 decimals.

After we make things permissionless, any tokens can be permissionlessly supported on DEX V2 as long as they abide by the limitations on the codebase (refers only to D3 pools (smart collateral), while D4 pools (smart debt) will remain permissioned). However, the use of these tokens will be limited to the specific pool and will not affect the other pools. It's expected that contracts will work with standard tokens only (without weird traits and excluding tokens with 15, 16 and 17 decimals), and using weird tokens leading to issues is considered an acceptable risk. But, if a malicious actor can create a pool with a malicious token and harm other pools, then it can be a valid issue.
___

### Q: Are there any limitations on values set by admins (or other roles) in the codebase, including restrictions on array lengths?
All protocol roles are trusted.
___

### Q: Are there any limitations on values set by admins (or other roles) in protocols you integrate with, including restrictions on array lengths?
All external protocol roles are also trusted.
___

### Q: Is the codebase expected to comply with any specific EIPs?
1. The FluidDexV2Proxy contract complies with ERC1967Proxy. The intent is to make the Dex upgradeable.
2. The FluidDexV2 contract is the implementation which the FluidDexV2Proxy will point to, and hence has functions like upgradeTo and upgradeToAndCall in the DexV2AdminModule.
3. The FluidMoneyMarketProxy contract complies with ERC1967Proxy. The intent is to make the Money Market upgradeable.
4. The FluidMoneyMarket contract is the implementation which the FluidMoneyMarketProxy will point to, and hence has functions like upgradeTo and upgradeToAndCall in the FluidMoneyMarketAdminModuleImplementation.
5. The FluidMoneyMarket contract also acts as the NFT manager, and it complies with the ERC721 standard, and the contract ERC721 is based on the ERC721 Solmate implementation.

EIP violations can be considered valid only if they qualify for Medium and High severity definitions.
___

### Q: Are there any off-chain mechanisms involved in the protocol (e.g., keeper bots, arbitrage bots, etc.)? We assume these mechanisms will not misbehave, delay, or go offline unless otherwise specified.
The rebalance function is an offchain mechanism in the DexV2 contracts. We can assume that it won't misbehave, delay, or go offline unless otherwise specified.

Revenue (protocol fee and interest revenue) tracking will also happen off-chain. 

Additionally, the oracle used by the Money Market contracts may rely on off-chain mechanisms, is considered trusted, and operates outside the scope of this audit.

___

### Q: What properties/invariants do you want to hold even if breaking them has a low/unknown impact?
No
___

### Q: Please discuss any design choices you made.
1. Precision trade-offs in protocol limits
In the Money Market contracts, protocol-level limits such as supply caps, debt caps, and isolated debt caps intentionally use reduced precision and rounding. These values are therefore approximations rather than exact limits, which simplifies calculations and reduces gas costs at the expense of perfect accuracy.

2. Timestamp compression in Dex V2
In the Dex V2 contracts, only the least significant 15 bits of the timestamp are stored. This is a deliberate gas optimization choice but may result in users being charged slightly higher fees than intended if a pool experiences no swaps for an extended period of time.

3. Flow limits and UX trade offs
Additional constraints have been introduced across various protocol flows (e.g., minimum and maximum amount checks). These are defensive checks designed to eliminate low probability edge cases and improve overall protocol safety, but they may negatively impact user experience in certain scenarios.

4. Rebalance execution constraints
The rebalance function may fail under specific conditions if one of the amounts passed to the Liquidity Layer’s operate function is below the required minimum. This is an accepted limitation and does not affect core protocol functionality.

5. Rounding during liquidation
In the Money Market contracts, during liquidation, there are cases where a portion of the amount intended to be received by the liquidator may be skipped if it is small. This is a deliberate rounding decision.

6. Unsupported token decimals in Dex contracts
Tokens with 15, 16, or 17 decimals are intentionally not supported in the Dex contracts.

7. Protocol fee and interest revenue accounting in Dex contracts
The Dex contracts do not currently account for, or provide an on chain mechanism to collect, accrued protocol fees. This is a deliberate design choice made to reduce the gas cost of swaps. Additionally, in certain cases, eg interest accrued on LP fees that have not yet been collected, or interest on stored balances held by the DEX, is revenue to the protocol. This interest revenue is also not explicitly accounted for on-chain. Both protocol fees and interest related revenues can be calculated retrospectively using historical on-chain data and off-chain accounting mechanisms when required.

8. Conservative rounding in favor of the protocol
There are multiple places in the codebase where explicit rounding is applied to consistently keep the protocol on the conservative (winning) side. This may result in users paying slightly more or receiving slightly fewer tokens in certain operations, with these residual amounts effectively remaining within the protocol. The amounts involved are minimal and non-material, making this an acceptable design choice.

9. Reduced precision storage of sqrtPriceX96
The sqrtPriceX96 value is stored using the BigMath library, with only the most significant 64 bits retained. This can result in the actual price being slightly above a tick but rounded down to just below it. To account for this, additional checks have been introduced during swaps, which may lead to minor rounding in favor of the user in this specific path. However, due to the protocol’s overall explicit and conservative rounding strategy, the protocol remains net profitable.

10. Reduced precision storage of global fee growth
The global fee growth variables are stored using the BigMath library, retaining only the most significant 74 bits. In extreme edge cases where this value becomes very large, incremental swap fees may not affect these most significant bits, potentially resulting in LPs missing the accrued swap fees. This scenario is highly unlikely and considered acceptable.

11. Conservative fee updates during tick crossing
During swaps, when a tick is crossed, the associated tick fee variables are updated conservatively to account for the fact that global fee variables are rounded down when stored. This approach prioritizes protocol safety but may result in LPs earning slightly lower fees under certain conditions.

12. User favorable rounding in isolated code paths
There are isolated instances in the codebase where rounding may be skipped or applied in favor of the user within specific code paths. Despite this, the protocol’s overall explicit and conservative rounding approach ensures that it remains net profitable.

13. Precision loss between global and per user accounting
Due to the use of BigMath, there are parts of the codebase where precision loss and rounding can cause discrepancies between global accounting values (aggregated across all users) and the sum of per user accounting. Since global values are larger in magnitude, they would lose proportionally more precision. In extreme edge cases, this could result in scenarios where, if all users attempt to withdraw simultaneously, a small residual amount becomes temporarily stuck because the global accounting reaches zero before all per user balances are fully settled. This scenario is unlikely. If it were to occur, the team would intervene by creating an internal position to allow affected users to withdraw their funds without loss.

14. Interest accrual assumptions during DEX rebalancing
Some interest earning tokens may remain in the DEX if rebalancing is not performed frequently. In such cases, these tokens may temporarily not earn interest, even though the accounting and mathematical models assume that they do. The protocol assumes that rebalancing will be performed frequently enough such that only a small portion of tokens remain unproductive at any given time. Any resulting shortfall in interest is expected and will be borne by the protocol through off-chain accounting and operational mechanisms.

15. Auths or Governance configuration changes
Authorized roles can update protocol parameters in ways that may cause existing positions to become liquidatable, restrict certain operations, or positions can become invalid in general. These authorized actors are assumed to be trusted and are expected to manage such changes responsibly, with appropriate consideration for their impact on existing positions.

16. Precision loss in BigMath accounting
The BigMath library is used for storing some amounts and it can result in precision loss. These precision losses are considered acceptable, and all rounding has been intentionally designed to ensure the protocol remains on the conservative (winning) side.
___

### Q: Please provide links to previous audits (if any) and all the known issues or acceptable risks.
1. Reentrancy considerations in Dex contracts
Some functions in the Dex contracts do not include explicit reentrancy guards. The codebase is designed such that standard reentrancy attacks are not possible; however, read-only reentrancy remains possible and is considered an acceptable risk.

2. No bad debt absorption mechanism
The Money Market contracts currently do not include any mechanism to absorb bad debt.

3. No bad debt socialization mechanism
The Money Market contracts also do not include any functionality to socialize bad debt across users or the protocol.

4. Inability to Close Undercollateralized Positions
The Money Market contracts also do not include any functionality to close undercollateralized positions.

5. Small amount liquidation edge cases
In certain edge cases, if the withdrawal amount or the payback amount during liquidations is very small, the operation may fail due to the protocol’s security checks. The team is aware that this behavior can, in rare situations, result in residual bad debt.

In general, if bad debt happens and the protocol cannot handle, or socialise bad debt, that's an acceptable risk and a known issue.

6. A token’s liquidity can be split between the DEX and the liquidity layer. As a result, certain operations, such as withdrawals or liquidations, may fail even when sufficient total liquidity exists, if the required liquidity is not available on the specific side needed to execute the transaction. This is a known and acceptable design risk. The rebalance function is expected to manage and mitigate this risk through regular rebalancing and should be considered trusted. Issues arising from this behaviour are therefore not considered valid findings.

7. All lending protocols inherently carry the risk of high utilization, which can lead to situations where withdrawals are temporarily unavailable and liquidations may become stuck. The protocol’s risk management framework is assumed to be trusted in handling such scenarios, and issues arising from these conditions are considered known and acceptable and will not be treated as valid findings

8. Any issues caused by bugs in Solidity versions 0.8.27-0.8.33 (i.e., caused by inherent Solidity bugs, not by the contract implementation) are considered known and OOS.
___

### Q: Please list any relevant protocol resources.
https://docs.fluid.instadapp.io/
https://blog.instadapp.io/fluid-dex-v2/
https://docs.fluid.instadapp.io/integrate/dex-v2-swaps.html
___

### Q: Additional audit information.
1. Smart Debt Math
The Smart Debt Math logic is critical to the protocol’s correctness and should be reviewed thoroughly. It introduces a novel paradigm and may exhibit non obvious behavior, so special care should be taken to ensure it does not result in losses.

2. Reentrancy considerations in Dex contracts
Some functions in the Dex contracts do not use explicit reentrancy guards and rely on internal invariants for safety. These paths should be reviewed carefully.

3. Extensive use of unchecked blocks
The codebase makes extensive use of unchecked arithmetic for gas optimization. These sections should be reviewed to ensure that all assumptions around overflow and underflow safety hold.


# Audit scope

[fluid-contracts @ 904c2989aa404ecb9cf75eb1efa1a5fa526007b0](https://github.com/Instadapp/fluid-contracts/tree/904c2989aa404ecb9cf75eb1efa1a5fa526007b0)
- [fluid-contracts/contracts/libraries/bigMathMinified.sol](fluid-contracts/contracts/libraries/bigMathMinified.sol)
- [fluid-contracts/contracts/libraries/dexV2BaseSlotsLink.sol](fluid-contracts/contracts/libraries/dexV2BaseSlotsLink.sol)
- [fluid-contracts/contracts/libraries/dexV2D3D4CommonSlotsLink.sol](fluid-contracts/contracts/libraries/dexV2D3D4CommonSlotsLink.sol)
- [fluid-contracts/contracts/libraries/dexV2PoolLock.sol](fluid-contracts/contracts/libraries/dexV2PoolLock.sol)
- [fluid-contracts/contracts/libraries/liquiditySlotsLink.sol](fluid-contracts/contracts/libraries/liquiditySlotsLink.sol)
- [fluid-contracts/contracts/libraries/moneyMarketSlotsLink.sol](fluid-contracts/contracts/libraries/moneyMarketSlotsLink.sol)
- [fluid-contracts/contracts/libraries/operationControl.sol](fluid-contracts/contracts/libraries/operationControl.sol)
- [fluid-contracts/contracts/libraries/pendingTransfers.sol](fluid-contracts/contracts/libraries/pendingTransfers.sol)
- [fluid-contracts/contracts/libraries/reentrancyLock.sol](fluid-contracts/contracts/libraries/reentrancyLock.sol)
- [fluid-contracts/contracts/protocols/dexV2/base/core/adminModule.sol](fluid-contracts/contracts/protocols/dexV2/base/core/adminModule.sol)
- [fluid-contracts/contracts/protocols/dexV2/base/core/helpers.sol](fluid-contracts/contracts/protocols/dexV2/base/core/helpers.sol)
- [fluid-contracts/contracts/protocols/dexV2/base/core/main.sol](fluid-contracts/contracts/protocols/dexV2/base/core/main.sol)
- [fluid-contracts/contracts/protocols/dexV2/base/other/commonImport.sol](fluid-contracts/contracts/protocols/dexV2/base/other/commonImport.sol)
- [fluid-contracts/contracts/protocols/dexV2/base/other/error.sol](fluid-contracts/contracts/protocols/dexV2/base/other/error.sol)
- [fluid-contracts/contracts/protocols/dexV2/base/other/errorTypes.sol](fluid-contracts/contracts/protocols/dexV2/base/other/errorTypes.sol)
- [fluid-contracts/contracts/protocols/dexV2/base/other/events.sol](fluid-contracts/contracts/protocols/dexV2/base/other/events.sol)
- [fluid-contracts/contracts/protocols/dexV2/base/other/interfaces.sol](fluid-contracts/contracts/protocols/dexV2/base/other/interfaces.sol)
- [fluid-contracts/contracts/protocols/dexV2/base/other/variables.sol](fluid-contracts/contracts/protocols/dexV2/base/other/variables.sol)
- [fluid-contracts/contracts/protocols/dexV2/base/proxy.sol](fluid-contracts/contracts/protocols/dexV2/base/proxy.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/adminModuleInternals.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/adminModuleInternals.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/commonImport.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/commonImport.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/constantVariables.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/constantVariables.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/controllerModuleInternals.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/controllerModuleInternals.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/error.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/error.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/errorTypes.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/errorTypes.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/events.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/events.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/helpers.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/helpers.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/interfaces.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/interfaces.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/structs.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/structs.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/swapModuleInternals.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/swapModuleInternals.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/userModuleInternals.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/userModuleInternals.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/variables.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/common/d3d4common/variables.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/d3/admin/main.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/d3/admin/main.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/d3/core/controllerModule.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/d3/core/controllerModule.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/d3/core/swapModule.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/d3/core/swapModule.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/d3/core/userModule.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/d3/core/userModule.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/d3/other/commonImport.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/d3/other/commonImport.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/d3/other/helpers.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/d3/other/helpers.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/d3/other/structs.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/d3/other/structs.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/d3/other/variables.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/d3/other/variables.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/d4/admin/main.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/d4/admin/main.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/d4/core/controllerModule.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/d4/core/controllerModule.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/d4/core/swapModule.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/d4/core/swapModule.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/d4/core/userModule.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/d4/core/userModule.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/d4/other/commonImport.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/d4/other/commonImport.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/d4/other/helpers.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/d4/other/helpers.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/d4/other/structs.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/d4/other/structs.sol)
- [fluid-contracts/contracts/protocols/dexV2/dexTypes/d4/other/variables.sol](fluid-contracts/contracts/protocols/dexV2/dexTypes/d4/other/variables.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/adminModule/events.sol](fluid-contracts/contracts/protocols/moneyMarket/core/adminModule/events.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/adminModule/interfaces.sol](fluid-contracts/contracts/protocols/moneyMarket/core/adminModule/interfaces.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/adminModule/main.sol](fluid-contracts/contracts/protocols/moneyMarket/core/adminModule/main.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/adminModule/structs.sol](fluid-contracts/contracts/protocols/moneyMarket/core/adminModule/structs.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/base/erc721.sol](fluid-contracts/contracts/protocols/moneyMarket/core/base/erc721.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/base/events.sol](fluid-contracts/contracts/protocols/moneyMarket/core/base/events.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/base/helpers.sol](fluid-contracts/contracts/protocols/moneyMarket/core/base/helpers.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/base/interfaces.sol](fluid-contracts/contracts/protocols/moneyMarket/core/base/interfaces.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/base/main.sol](fluid-contracts/contracts/protocols/moneyMarket/core/base/main.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/callbackModule/helpers.sol](fluid-contracts/contracts/protocols/moneyMarket/core/callbackModule/helpers.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/callbackModule/main.sol](fluid-contracts/contracts/protocols/moneyMarket/core/callbackModule/main.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/callbackModule/structs.sol](fluid-contracts/contracts/protocols/moneyMarket/core/callbackModule/structs.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/liquidateModule/events.sol](fluid-contracts/contracts/protocols/moneyMarket/core/liquidateModule/events.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/liquidateModule/helpers.sol](fluid-contracts/contracts/protocols/moneyMarket/core/liquidateModule/helpers.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/liquidateModule/main.sol](fluid-contracts/contracts/protocols/moneyMarket/core/liquidateModule/main.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/liquidateModule/structs.sol](fluid-contracts/contracts/protocols/moneyMarket/core/liquidateModule/structs.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/operateModule/events.sol](fluid-contracts/contracts/protocols/moneyMarket/core/operateModule/events.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/operateModule/helpers.sol](fluid-contracts/contracts/protocols/moneyMarket/core/operateModule/helpers.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/operateModule/interfaces.sol](fluid-contracts/contracts/protocols/moneyMarket/core/operateModule/interfaces.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/operateModule/main.sol](fluid-contracts/contracts/protocols/moneyMarket/core/operateModule/main.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/operateModule/structs.sol](fluid-contracts/contracts/protocols/moneyMarket/core/operateModule/structs.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/other/commonImport.sol](fluid-contracts/contracts/protocols/moneyMarket/core/other/commonImport.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/other/error.sol](fluid-contracts/contracts/protocols/moneyMarket/core/other/error.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/other/errorTypes.sol](fluid-contracts/contracts/protocols/moneyMarket/core/other/errorTypes.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/other/helpers.sol](fluid-contracts/contracts/protocols/moneyMarket/core/other/helpers.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/other/interfaces.sol](fluid-contracts/contracts/protocols/moneyMarket/core/other/interfaces.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/other/structs.sol](fluid-contracts/contracts/protocols/moneyMarket/core/other/structs.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/other/variables.sol](fluid-contracts/contracts/protocols/moneyMarket/core/other/variables.sol)
- [fluid-contracts/contracts/protocols/moneyMarket/core/proxy.sol](fluid-contracts/contracts/protocols/moneyMarket/core/proxy.sol)


