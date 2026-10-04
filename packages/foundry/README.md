# Foundry package

The contracts, deploy scripts and tests behind the diamond. The [root README](../../README.md) is the guide; this page is the reference for working inside `packages/foundry`.

## Dependencies

Forge libraries are git submodules under `lib/`, pinned by tag in `foundry.lock`:

| Library | Why |
| --- | --- |
| `lib/lattice` | The diamond, its facets, the deploy base (`BaseDeploy`) and the HTS mock used in tests. |
| `lib/forge-std` | Forge's test and script library. |

`create-scaffold-hbar` installs them when it scaffolds the project. In a plain clone, run `git submodule update --init --recursive` from the repository root.

## Tests

```bash
yarn test            # forge test, then the Node tests for scripts-js
forge test -vvv --match-contract TokenSaleTest
yarn test:scripts    # only the Node tests
```

Tests need no chain. `test/SaleTestBase.sol` builds the diamond through the deploy script, puts Lattice's `MockHederaTokenService` at the HTS address `0x167`, and registers `test/mocks/MockAggregatorV3.sol` as the HBAR/USD feed.

| File | Covers |
| --- | --- |
| `test/TokenSale.t.sol` | Launching the sale, quoting, buying, association, slippage, HTS response codes, admin functions, the storage slot, `exportSelectors()`. |
| `test/TokenSaleUpgrade.t.sol` | Cutting `TokenSaleV2` into a diamond that is already selling. |
| `test/DeployDiamond.t.sol` | Reading recipes: the default, an oracle swap, `owners`, `exclude`, and every message a bad recipe produces. |
| `scripts-js/*.test.js` | The merged `Diamond` ABI, the Lattice Studio link, the Foundry version warning. |

`yarn test:testnet` and `yarn test:mainnet` fork a live network. The suite does not need them.

## Deploy

```bash
yarn deploy --network hedera_testnet                                   # the diamond, from diamond.recipe.json
yarn deploy --file DeployTokenSaleV2.s.sol --network hedera_testnet    # the upgrade facet
```

From the repository root the same commands are `yarn foundry:deploy ...`.

- Use Foundry 1.7.1 (`foundryup --install v1.7.1`). Foundry 1.8 cannot run `forge script` against Hedera's relay yet.
- The deployer must be an account that exists on Hedera: generate a keystore with `yarn account:generate` and fund its address from the [faucet](https://portal.hedera.com/faucet).
- The Makefile passes `--slow --legacy`: one transaction at a time, with legacy gas pricing, which is what the relay expects.
- Lattice facets (the recipe's, and `HTSAdapter`) are deployed at deterministic addresses, through CreateX or the deterministic deployment proxy where the chain has one, so a facet that is already on the network at its address is reused instead of deployed again. `TokenSale` and the initializers use plain `CREATE`, so every run deploys them again.

A deploy writes three things:

| File | Content |
| --- | --- |
| `broadcast/` | Forge's record of the transactions. Not committed. |
| `deployments/diamond/<chainId>.json` | The diamond's address, its facets, and the selectors cut for each. Not committed. |
| `../nextjs/contracts/deployedContracts.ts` | What the app reads: one `Diamond` contract with the merged ABI. Committed. |

## Environment

`.env` is created from `.env.example` on install and is never committed.

| Variable | Use |
| --- | --- |
| `HBAR_USD_MAX_STALENESS` | Seconds the diamond accepts between Chainlink updates. Read at deploy time. Defaults to 365 days on testnet and 25 hours on mainnet. |
| `LOCALHOST_KEYSTORE_ACCOUNT`, `HEDERA_RPC_URL`, `ALCHEMY_API_KEY` | Scaffold-HBAR defaults. This template does not need them changed. |
