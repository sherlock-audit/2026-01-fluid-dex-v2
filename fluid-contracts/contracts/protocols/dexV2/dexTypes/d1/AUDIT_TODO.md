# Audit Findings — D1 (review when D1 is implemented)

> **TODO**: These findings were identified during the Sherlock contest triage but D1/D2 are not yet
> finished. Review this file once D1/D2 implementation is complete and production-ready.
>
> Full details in: `docs/sherlock-triage/handoff_d1_d2_future.md`

## Summary of D1/D2 Issues to Review

### [HIGH] Swapped exchange price indices in D1 `coreInternals.sol`
- **Lines**: `contracts/protocols/dexV2/dexTypes/d1/core/coreInternals.sol:151-152`
- **Claim**: When `swap0To1_ = false`, `token0TotalSupplyRawChange_` incorrectly uses `token1SupplyExchangePrice`
  and `token1TotalSupplyRawChange_` incorrectly uses `token0SupplyExchangePrice`. Prices are crossed,
  causing systematic raw accounting errors proportional to the token0/token1 price divergence.
- **IDs**: 50, 879, 880

### [MEDIUM] D2 `swapOut` uses uninitialized `amountIn_` in reserve verification
- **Lines**: `contracts/protocols/dexV2/dexTypes/d2/core/coreInternals.sol`
- **Claim**: `swapOut()` uses `amountIn_` before it's assigned in a reserve verification check.
- **IDs**: 84, 431, 504, 513, 519, 520

### [LOW] D1/D2 `centerPrice` oracle bypass / static anchor
- **Claim**: D2 doesn't call `_updateOracle` (only has TODO), causing static center price.
  D1/D2 center price oracle revert causes pool-wide DoS if oracle is unhealthy.
- **IDs**: 88, 271, 322, 655, 656, 663, 1063, 1064

## Deduplicated IDs (all Sherlock contest findings referencing D1/D2)

50, 84, 88, 271, 322, 431, 504, 513, 519, 520, 626, 655, 656, 663, 879, 880, 1063, 1064
