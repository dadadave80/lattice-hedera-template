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
| `test/TokenSaleUpgrade.t.sol` | Cutting `TokenSaleV2` into a diamond that is already selling, and its `exportSelectors()`. |
| `test/StealthBuy.t.sol` | `buyFor`: the stipend and the tokens reaching a new address, the exact ERC-5564 `Announcement`, pricing at `quote` (bonus included after a cut to `TokenSaleV2`), slippage, the emergency stop, an address that refuses HBAR or cannot take the token, a stealth address that buys again from its `receive()`, the sale totals, `exportSelectors()`. |
| `test/DeployStealthBuy.t.sol` | Adding the three stealth facets to a diamond built from a recipe without them: one cut, the inits on a live diamond, a delivery afterwards, the deployment record, and the stop when no diamond is recorded. |
| `test/DeployDiamond.t.sol` | Reading recipes: the default, init steps that take no arguments, an oracle swap, `owners`, `exclude`, the stop when `HTSAdapter` or its init step is missing, feed registration when the recipe names another admin, and every message a bad recipe produces. |
| `test/DeployGuardian.t.sol` | The deploy making the deployer an emergency guardian, leaving that to a recipe admin that is not the deployer, and skipping a diamond without `EmergencyStop`; the stop when `HEDERA_FACETS` counts a facet `build()` does not add, or a project facet has no artifact under its own name. |
| `scripts-js/*.test.js` | The merged `Diamond` ABI, the Lattice Studio link, the Foundry version warning, the Sourcify verification helpers. |

`yarn test:testnet` and `yarn test:mainnet` fork a live network. The suite does not need them.

## Deploy

```bash
yarn deploy --network hedera_testnet                                   # the diamond, from diamond.recipe.json
yarn deploy --file DeployTokenSaleV2.s.sol --network hedera_testnet    # the upgrade facet
yarn deploy --file DeployStealthBuy.s.sol --network hedera_testnet     # private purchases, for a diamond deployed before them
```

From the repository root the same commands are `yarn foundry:deploy ...`.

On mainnet, pass `--network hedera_mainnet`. The scripts pick the mainnet Chainlink feed and SaucerSwap V1 addresses from the chain id, and `yarn verify:mainnet` verifies one contract by hand. The [root README](../../README.md#launch-on-mainnet) walks through a mainnet launch.

- Use Foundry 1.7.1 (`foundryup --install v1.7.1`). Foundry 1.8 cannot run `forge script` against Hedera's relay yet.
- The deployer must be an account that exists on Hedera: generate a keystore with `yarn account:generate` and fund its address from the [faucet](https://portal.hedera.com/faucet).
- The Makefile passes `--slow --legacy`: one transaction at a time, with legacy gas pricing, which is what the relay expects.
- When the deploying account is the diamond's admin, `DeployDiamond.s.sol` registers the HBAR/USD feed and makes that account an emergency guardian, which can halt the sale with `emergencyStop`.
- Lattice facets (every facet the recipe names, `HTSAdapter`, `ERC6538Registry` and `ERC5564Announcer` included) are deployed at deterministic addresses, through CreateX or the deterministic deployment proxy where the chain has one, so a facet that is already on the network at its address is reused instead of deployed again. `TokenSale`, `StealthBuy` and the initializers use plain `CREATE`, so every run deploys them again.
- `DeployStealthBuy.s.sol` cuts `StealthBuy`, `ERC6538Registry` and `ERC5564Announcer` into the diamond named in `deployments/diamond/<chainId>.json`, with one `diamondCut` that runs their initializers through `UpgradeMultiInit`. The broadcasting account must hold the diamond's `DEFAULT_ADMIN_ROLE`. A diamond deployed from the current recipe already has the three facets, and the cut reverts there.
- On `hedera_testnet` and `hedera_mainnet`, once the script has run and the ABIs are written, `scripts-js/verifyDeployment.js` verifies on Sourcify every contract in `broadcast/<Script>/<chainId>/run-latest.json`, six at a time, with `forge verify-contract`. It skips a contract Sourcify already has, which is how a reused facet is passed over. A contract that fails to verify is printed with the `yarn foundry:verify:testnet` (or `:mainnet`) command to retry it, and the deploy still succeeds.

A deploy writes three things:

| File | Content |
| --- | --- |
| `broadcast/` | Forge's record of the transactions. Not committed. |
| `deployments/diamond/<chainId>.json` | The diamond's address, its facets, and the selectors cut for each. `DeployStealthBuy.s.sol` adds its three facets here after a broadcast, never on a dry run. Not committed. |
| `../nextjs/contracts/deployedContracts.ts` | What the app reads: one `Diamond` contract with the merged ABI. Committed. |

## Environment

`.env` is created from `.env.example` on install and is never committed.

| Variable | Use |
| --- | --- |
| `HBAR_USD_MAX_STALENESS` | Seconds the diamond accepts between Chainlink updates. Read at deploy time. Defaults to 365 days on testnet, where Chainlink does not guarantee a heartbeat, and 25 hours on mainnet: the mainnet feed's 24-hour heartbeat plus an hour for a late update. |
| `LOCALHOST_KEYSTORE_ACCOUNT`, `HEDERA_RPC_URL`, `ALCHEMY_API_KEY` | Scaffold-HBAR defaults. This template does not need them changed. |
