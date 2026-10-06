# Infinite Money Glitch (IMB)

A fixed-supply ERC-20. The constructor mints the entire supply once to its
immediate caller (`msg.sender`). The name is branding; the supply cannot grow.

| Parameter | Value |
| --- | --- |
| Contract | `src/InfiniteMoneyGlitch.sol:InfiniteMoneyGlitch` |
| Name | `Infinite Money Glitch` |
| Symbol | `IMB` |
| Decimals | `18` |
| Human-readable supply | `1,000,000,000 IMB` |
| Supply in minor units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Deployment value | `0` |

## Build and test

With Foundry and Solidity **0.8.26** available locally:

```sh
forge build
forge test
forge fmt --check
```

All Solidity dependencies are ordinary vendored files in `lib/`; no package
installation, submodules, network, RPC, keys, or environment variables are needed
by the build or tests once the pinned compiler is installed. Foundry may download
the compiler if it is not already installed. The compiler binary is deliberately
not part of this project. Configuration pins Cancun, optimizer enabled with 200
runs, and `bytecode_hash = "none"`. FFI and filesystem cheatcode permissions are
disabled.

Tests cover metadata and the initial mint event, direct and CREATE2 factory
deployment, whole/zero/self transfers, contract recipients, approvals and
revocation, finite and unlimited allowances, insufficient balances/allowances,
zero addresses, rollback after failed delegated transfers, and rejection of
minting, burning, administrative calls, and ordinary ETH deposits. They check
the runtime for forbidden execution opcodes. Four fuzz tests run 512 cases each;
the stateful invariant runs 128 sequences of 64 calls and checks supply, the
complete balance sum, exact transfers, and allowance accounting. Each test uses
fresh local deployments and is independent of execution order and environment.

The launch-flow fixture verifies full-value token movements from a factory to a
distributor and pool address, claims, and transfers both ways with a trader.
It is a token accounting test, not a Uniswap integration test. The supplied
protected harness additionally needs network-owned `LaunchLiquidity`,
`PoolInitializationGuard`, `HookFlags`, Uniswap v4 dependencies, and launch
parameters that were not supplied in this assignment. Its end-to-end pool seed
and swap checks remain the launch verifier's responsibility.

## Behavior and assumptions

- Transfers move the exact amount. There are no taxes, reflections, rebases,
  vesting rules, transfer limits, or address exemptions.
- Zero-value transfers between nonzero addresses are valid and emit `Transfer`.
  Transfers to the zero address and approvals of the zero spender revert.
- `approve` replaces an allowance. `transferFrom` spends the caller's allowance;
  even the original deployer needs approval to spend another holder's tokens.
  `type(uint256).max` allowances remain unchanged until the holder replaces or
  revokes them. Prefer bounded approvals, and revoke an existing allowance before
  setting a new one when coordinating spender activity. A spender may use the
  old allowance before a revocation is mined.
- Minting emits `Transfer` from zero. Explicit approvals emit `Approval`. This
  OpenZeppelin version does not emit `Approval` when `transferFrom` consumes an
  allowance; query `allowance` for the current value.
- There is no owner, external mint or burn function, pause, blacklist, seizure,
  upgrade mechanism, proxy, or initialization step. Internal library mint/burn
  helpers are not externally callable. There are no recipient callbacks,
  external calls, or oracle dependencies in the token's transaction paths.
- Tokens sent to the token contract or an incompatible recipient can be stuck;
  there is no recovery administrator. Ordinary ETH transfers revert, and any
  forcibly delivered ETH or other assets cannot be recovered through this token.

## Deployment and operational responsibilities

Deploy the artifact above with no constructor arguments and zero native value
on a chain supporting the configured Cancun EVM. A direct deployment gives the
entire supply to the deploying account. With `CREATE` or `CREATE2` from a factory,
the factory receives the entire supply, **not** the transaction origin or the
person who called the factory. The factory must implement any later distribution.
The constructor needs no factory, PoolManager, distributor, or launch-number
arguments because all token transfers use the same rules.

Creation bytecode can be inspected locally without sending a transaction:

```sh
forge inspect src/InfiniteMoneyGlitch.sol:InfiniteMoneyGlitch bytecode
```

For the separate launch manifest, use the contract identifier and values in the
table, empty constructor arguments, and no application contracts. The launch
operator supplies the target chain, factory and pool addresses, paired currency,
pool allocation, initial capitalization/price, fee, tick spacing, and remainder
recipient from the authorized job. None of those economic parameters were given
here, so this project does not invent a launch manifest. The factory, rather than
the token, handles the network's 10% distribution and other launch allocations.

The deployment operator must confirm the artifact and compiler settings, verify
source/runtime on the selected chain, check the deployed name, symbol, decimals,
supply and initial factory balance, run the protected launch integration checks,
and perform the authorized distribution. Holders control their own transfers and
approvals; no maintenance transactions or administrator keys are required by the
token. Supply is initially concentrated in the deployer until it is distributed.

This assignment performs no broadcasts and uses no wallet keys. Local tests and
code review do not constitute an independent security audit; arrange independent
adversarial review before release. Slither and Mythril were not run.

## Vendored dependencies

- OpenZeppelin Contracts **v5.0.2**, commit
  `dbb6104ce834628e473d2173bbc9d47f81a9eec3`: only the ERC-20 source dependency
  closure and MIT license are vendored.
- Forge Standard Library **v1.9.7**, commit
  `77041d2ce690e692d6e03cc812b57d1ddaa4d505`: its `src/` tree and MIT/Apache
  licenses are vendored for tests.

`dependencies.lock.json` records the upstream repositories, exact commits, and
SHA-256 of every vendored file. Those files are unmodified upstream sources.
