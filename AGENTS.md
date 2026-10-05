# Agent instructions

Briefing for coding agents in this project (Claude Code, Cursor, Codex). Claude Code loads it through `CLAUDE.md`.

This is a Scaffold-HBAR dApp built from the Lattice Hedera Template. One [Lattice](https://github.com/dadadave80/lattice) diamond (EIP-2535) on Hedera creates an HTS token, sells it for HBAR at a USD price read from Chainlink, seeds a SaucerSwap V1 pool for it at the sale's own Chainlink price (`seedPool`), delivers it privately to ERC-5564 stealth addresses (`buyFor`), and is upgraded with `diamondCut`. Contracts are Foundry, the app is Next.js App Router, the package manager is Yarn.

## Rules that are easy to get wrong

1. **Change the diamond's base in `packages/foundry/diamond.recipe.json`, not in Solidity.** `script/DeployDiamond.s.sol` reads that file. Never hand-write `FacetCut` arrays or selector lists for Lattice facets.
2. **A facet a recipe names must be compiled into the project.** If a build stops with `X is in the recipe but not compiled into this project`, add the import of `X` (and of `XInit`, if it has one) to `packages/foundry/contracts/LatticeFacets.sol`.
3. **`HTSAdapter`, `ERC6538Registry` and `ERC5564Announcer` are in the recipe. `TokenSale`, `StealthBuy` and `SaucerSwapPool` are not.** Lattice Studio's catalog `dev-6c8db45` carries those three Lattice facets, so they and their init steps (`HTSAdapterInit`, `ERC6538RegistryInit`, `ERC5564AnnouncerInit`) sit in the recipe like any other Lattice facet. `TokenSale`, `StealthBuy` and `SaucerSwapPool` are this project's facets: `DeployDiamond.s.sol` appends them after the recipe's facets, and Studio rejects a recipe that names a facet it does not know. Do not add them to the recipe. Do not remove `HTSAdapter` or `HTSAdapterInit`: the sale creates its token with the roles `HTSAdapterInit` grants, and the deploy stops without them. Do not remove `ERC6538Registry`: the Private page registers and reads meta-addresses through it, and the deploy does not check for it.
4. **Facets hold no state.** Logic and storage live in a library with its own ERC-7201 slot (`contracts/libraries/TokenSaleLib.sol`). Append fields to a storage struct. Never reorder or remove fields, and never change a slot constant. `StealthBuyLib` has no slot: a private purchase books into `TokenSaleStorage`. `SaucerSwapPoolLib` has its own slot for SaucerSwap's addresses and the pool.
5. **Every facet lists its selectors in `exportSelectors()`** (ERC-8153): 4 bytes each, never `exportSelectors()` itself. Add a function, add its selector. `test/TokenSale.t.sol`, `test/StealthBuy.t.sol`, `test/SaucerSwapPool.t.sol` and `test/TokenSaleUpgrade.t.sol` fail when the list and the ABI disagree.
6. **HBAR has two units.** Contracts see tinybars (8 decimals) in `msg.value` and in every amount they take or return. A transaction's `value` over JSON-RPC is weibars (18 decimals), and the relay converts. In the app, convert only through `packages/nextjs/utils/sale/units.ts`. With `cast send`, `--value 20ether` sends 20 HBAR. For `buyFor`, `msg.value` is payment plus stipend, and the `stipend` argument is tinybars too.
7. **HTS answers with response codes. It does not revert.** `22` is success. Check the code after every call to `0x167` and revert with a named error, as `TokenSaleLib._transferFromTreasury` does.
8. **There is no local chain.** HTS and the Chainlink feed exist only on Hedera. Contract tests run against Lattice's `MockHederaTokenService`, `test/mocks/MockAggregatorV3.sol` and, for the pool, `test/mocks/MockSaucerSwapV1.sol`. The app runs against Hedera testnet. `forge script` cannot simulate an HTS call, so the token is created by a separate transaction (`launchSale`) after the deploy. The project has no `chain`, `fork` or `test:local` yarn script, and `scaffold.config.ts` targets Hedera testnet and mainnet only.
9. **Deploy with Foundry 1.7.1.** Foundry 1.8 fails against Hedera's relay with `-32602 Invalid parameter 1`. Building and testing work on any recent Foundry.
10. **The frontend knows one contract, `Diamond`.** Its ABI is the union of what the facets serve. `scripts-js/generateTsAbis.js` writes it to `packages/nextjs/contracts/deployedContracts.ts` on every deploy. Never edit that file by hand.
11. **`buyFor` creates an account.** HBAR sent to an address with no account lazy-creates it (HIP-583) with unlimited automatic token associations (HIP-904). `StealthBuyLib` sends the stipend before the token for that reason: keep that order. Give `buyFor` an explicit gas limit: it used 1,433,536, and `BuyPrivatelyCard` sets 2,000,000. Hedera charges the gas used, but the payer must hold the limit's worth up front, so do not inflate it. The card shows the network fee, about 1.2 HBAR, and enables Buy privately only when the wallet holds the payment, the stipend and the limit's worth of gas.
12. **A Lattice initializer runs only while a diamond is initializing.** To run one in a cut on a live diamond, go through `UpgradeMultiInit`, as `DeployStealthBuy.s.sol` and `DeploySaucerSwapPool.s.sol` do.
13. **The stipend pays the recipient's sweep.** `BuyPrivatelyCard` sends 1 HBAR by default. The sweep is the stealth account's first transaction: about 0.035 HBAR to an existing account, and about 0.67 HBAR to an address with no account, because the token transfer creates that account. `InboxCard` estimates the sweep's cost from the stealth address and disables Sweep when the stealth address holds less HBAR than the sweep costs. The sweep moves the tokens only, so the rest of the stipend stays on the stealth address. `buyFor` enforces no minimum stipend, so do not lower the default below what a sweep to a new address costs.
14. **`seedPool` needs an explicit gas limit, positive minimums and a fee margin.** Creating a pool used 7,579,582 gas on testnet; `PoolSeedForm` sets 12,000,000 for a new pool and 2,500,000 for an existing one. The relay refuses a limit over 15,000,000 and its estimate is not reliable for HTS calls. Set `minTokens` and `minTinybars` near the amounts (the form uses 1% slippage) even for a new pool: anyone can create the pool first at any price, and only the minimums stop the call from adding at theirs. Zero minimums revert `SaucerSwapPoolInvalidAmount`. SaucerSwap sets the creation fee in USD and the diamond converts it through the exchange-rate system contract (`0x168`) when the call runs, so pass `maxCreationFee` about 5% over `poolInfo().creationFee` (`CREATION_FEE_MARGIN_BPS` in `utils/saucerswap/pool.ts`). HBAR comes from the diamond's balance first; `msg.value` tops it up.

## Commands

```bash
yarn foundry:test      # Forge tests (mock HTS, mock feed) and the Node tests for scripts-js. No chain needed.
yarn next:test         # Vitest unit tests for packages/nextjs/utils
yarn next:dev          # the app on http://localhost:3000, against Hedera testnet
yarn lint              # next lint, forge fmt --check, prettier --check on scripts-js
yarn format            # fix what yarn lint reports
yarn next:check-types
yarn next:build

yarn foundry:account:generate                                                  # create a deployer keystore
yarn foundry:deploy --network hedera_testnet                                   # deploy the diamond from the recipe, then verify each contract on Sourcify
yarn foundry:deploy --file DeployTokenSaleV2.s.sol --network hedera_testnet    # deploy the upgrade facet and verify it
yarn foundry:deploy --file DeployStealthBuy.s.sol --network hedera_testnet     # admin only: cut StealthBuy, ERC6538Registry, ERC5564Announcer into a diamond deployed before them
yarn foundry:deploy --file DeploySaucerSwapPool.s.sol --network hedera_testnet # admin only: cut SaucerSwapPool (and run SaucerSwapPoolInit) into a diamond deployed before it
yarn foundry:verify:testnet <address> <file>:<Contract>                        # verify or re-verify one contract by hand (a failed verification does not fail the deploy)
yarn diamond:studio                                                            # print the Lattice Studio link for the recipe
```

Run one Forge test from `packages/foundry`: `forge test --match-test test_buy_sendsTokensToTheBuyerAndKeepsTheHbar -vvv`.

## Layout

| Path | What it is |
| --- | --- |
| `packages/foundry/diamond.recipe.json` | Every Lattice facet of the diamond, `HTSAdapter`, `ERC6538Registry` and `ERC5564Announcer` included, and their init steps, in Lattice Studio's recipe format. |
| `packages/foundry/script/DeployDiamond.s.sol` | Reads the recipe, appends `TokenSale`, `StealthBuy` and `SaucerSwapPool` (`HEDERA_FACETS` = 3, `HEDERA_INITS` = 3), deploys, registers the Chainlink feed, makes the admin an emergency guardian, records the deployment. Its `SaucerSwapV1` library holds SaucerSwap V1's router, factory and WHBAR for testnet and mainnet. |
| `packages/foundry/script/Deploy.s.sol` | What `yarn foundry:deploy` runs by default. It is `DeployDiamond`. |
| `packages/foundry/script/DeployTokenSaleV2.s.sol` | Deploys the upgrade facet on its own. |
| `packages/foundry/script/DeployStealthBuy.s.sol` | Cuts `StealthBuy`, `ERC6538Registry` and `ERC5564Announcer` into the recorded diamond in one `diamondCut`, inits through `UpgradeMultiInit`. Broadcast by the diamond's admin. Writes `deployments/diamond/<chainId>.json` only on a real broadcast. |
| `packages/foundry/contracts/LatticeFacets.sol` | Imports that compile Lattice facets and inits into this project. |
| `packages/foundry/contracts/interfaces/ITokenSale.sol` | The sale's functions, events and errors. |
| `packages/foundry/contracts/libraries/TokenSaleLib.sol` | The sale's logic and storage. |
| `packages/foundry/contracts/TokenSale.sol`, `TokenSaleV2.sol` | The sale facet and its upgrade. |
| `packages/foundry/contracts/TokenSaleInit.sol` | The sale's initializer, run once while the diamond is created. |
| `packages/foundry/contracts/interfaces/IStealthBuy.sol` | `buyFor`, `StealthDelivery` and the stealth errors. |
| `packages/foundry/contracts/StealthBuy.sol`, `libraries/StealthBuyLib.sol` | The private-purchase facet and its logic: price with the diamond's `quote`, stipend, treasury transfer, ERC-5564 `Announcement`. |
| `packages/foundry/script/DeploySaucerSwapPool.s.sol` | Cuts `SaucerSwapPool` into the recorded diamond in one `diamondCut` that runs `SaucerSwapPoolInit` through `UpgradeMultiInit`. Broadcast by the diamond's admin. Writes the record only on a real broadcast. |
| `packages/foundry/contracts/interfaces/ISaucerSwapPool.sol` | `seedPool`, `transferLiquidity`, `poolInfo`, `PoolSeeded`, `LiquidityTransferred` and the pool errors. |
| `packages/foundry/contracts/interfaces/ISaucerSwapV1.sol` | The parts of SaucerSwap V1's router, factory and pair the pool calls. |
| `packages/foundry/contracts/SaucerSwapPool.sol`, `libraries/SaucerSwapPoolLib.sol` | The pool facet and its logic: HTS approve to the router (withdrawn after), LP association, creation fee via `0x168`, add liquidity, keep the LP tokens. Its own ERC-7201 slot. |
| `packages/foundry/contracts/SaucerSwapPoolInit.sol` | Sets the router, factory and WHBAR the pool uses. Run while the diamond is created, or through `UpgradeMultiInit` on a live diamond. |
| `packages/foundry/contracts/UpgradeMultiInit.sol` | Runs Lattice initializers from a `diamondCut` on a live diamond. |
| `packages/foundry/test/SaleTestBase.sol` | Test base: builds the diamond through the deploy script, with HTS and the feed mocked. |
| `packages/foundry/test/fixtures/` | Recipes frozen for tests. Tests do not depend on the project's own recipe, except one. |
| `packages/foundry/scripts-js/diamondAbi.js` | Merges facet ABIs into the `Diamond` ABI. |
| `packages/foundry/scripts-js/verifyDeployment.js` | Runs after a Hedera deploy: verifies on Sourcify every contract the broadcast record lists. |
| `packages/foundry/lib/lattice` | Lattice, pinned by tag in `foundry.lock`. Do not edit. |
| `packages/nextjs/app/page.tsx` | Private page, at `/`, where the app opens: `components/private/PrivatePurchases.tsx`, which holds the derived keys and renders `ReceiveCard.tsx`, `BuyPrivatelyCard.tsx` and `InboxCard.tsx`. |
| `packages/nextjs/app/sale/page.tsx` | Sale page, at `/sale`: `components/sale/SaleCard.tsx`, `AdminCard.tsx` and `PoolCard.tsx` (the SaucerSwap pool's reserves against the sale price, the diamond's LP tokens, links), which renders `PoolSeedForm.tsx` for the admin. |
| `packages/nextjs/app/diamond/page.tsx` | Diamond page: `components/diamond/FacetTable.tsx`, `StudioCard.tsx` and `UpgradeCard.tsx`. |
| `packages/nextjs/utils/sale/units.ts` | Tinybar and weibar conversion. |
| `packages/nextjs/utils/diamond/planCut.ts` | Turns a facet's exported selectors into Add and Replace cuts. |
| `packages/nextjs/utils/studio/` | Reads Lattice Studio's catalog, names a diamond's facets by their selectors, and builds the Studio link. `studioLink.ts` encodes as `scripts-js/studioLink.js` does. |
| `packages/nextjs/utils/saucerswap/` | The pool facet's inline ABI (`abi.ts`), pool and sale price, minimums, fee margin and HBAR-to-send math (`pool.ts`), and SaucerSwap, HashScan and entity-id helpers (`links.ts`). |
| `packages/nextjs/utils/stealth/` | ERC-5564 scheme 1 math (`stealthAddress.ts`, tested against ScopeLift's stealth-address-sdk), the mirror-node announcement scan (`announcements.ts`), and inline ABIs for `buyFor` and the registry (`abi.ts`). |

## How to change things

| Goal | Do this |
| --- | --- |
| Swap or add a Lattice facet in a new deployment | Edit `diamond.recipe.json` (or export over it from Lattice Studio), run `yarn foundry:test`, deploy. |
| Use a Lattice facet that is not compiled in | Add its import to `contracts/LatticeFacets.sol`. If its init takes more than `admin`, add an encoder in `_initStep` in `DeployDiamond.s.sol`. |
| Change the sale's behaviour on a live diamond | Write a new facet (copy `TokenSaleV2.sol`), deploy it with its own script, cut it in from the Diamond page. |
| Add your own facet to new deployments | Interface, library with its own slot, facet with `exportSelectors()`. Add it next to `TokenSale`, `StealthBuy` and `SaucerSwapPool` in `build()` in `DeployDiamond.s.sol` and raise `HEDERA_FACETS` (3 now) and, if it has an initializer, `HEDERA_INITS` (3 now). |
| Add a facet with an initializer to a live diamond | Copy `DeploySaucerSwapPool.s.sol` (one facet) or `DeployStealthBuy.s.sol` (several): one `diamondCut` whose init is `UpgradeMultiInit.upgradeInit`. |
| Add private purchases to a diamond deployed before them | `yarn foundry:deploy --file DeployStealthBuy.s.sol --network hedera_testnet` from the admin account. A diamond from the current recipe has them already, and the cut reverts there. |
| Add the SaucerSwap pool to a diamond deployed before it | `yarn foundry:deploy --file DeploySaucerSwapPool.s.sol --network hedera_testnet` from the admin account. A diamond from the current deploy script has it already. |
| Add sale storage | Append a field to `TokenSaleStorage`. |
| Change the oracle | Put `PythAdapter` in the recipe instead of `ChainlinkAdapter`. `TokenSale` does not change: it reads `latestAnswer(bytes32)` on the diamond. Registering and updating a Pyth feed is yours to add. |
| Stop the sale in an emergency | A guardian calls `emergencyStop(reason)` on the diamond, and `buy`, `buyFor` and `seedPool` revert until the admin calls `emergencyResume()`. `withdrawProceeds` and `transferLiquidity` still work. The deploy makes the deploying admin a guardian; the admin adds others with `addGuardian`. |

Before a new facet goes in:

- Compute its library's slot with `cast index-erc7201 "<namespace>"` and tag the struct `@custom:storage-location erc7201:<namespace>`, as `TokenSaleLib` does.
- List its selectors from `forge inspect <Facet> methodIdentifiers` in `exportSelectors()`.
- Price a payment through the diamond, `ITokenSale(address(this)).quote(tinybars)`, as `StealthBuyLib` does, so an upgraded sale's price and bonus apply.
- Pay tokens out with `TokenSaleLib._transferFromTreasury`, which checks the HTS response code.
- Name the file after the contract (`MyFacet` in `contracts/MyFacet.sol`). After a deploy, `scripts-js/generateTsAbis.js` reads each facet's ABI from `out/<Name>.sol/<Name>.json` and fails on a facet it cannot find there.

## Frontend contract interaction

Use the Scaffold-HBAR hooks in `packages/nextjs/hooks/scaffold-hbar` with `contractName: "Diamond"`. Every function of every facet is on that one contract.

```typescript
const { data: saleInfo } = useScaffoldReadContract({
  contractName: "Diamond",
  functionName: "saleInfo",
});

const { writeContractAsync } = useScaffoldWriteContract({ contractName: "Diamond" });

await writeContractAsync({
  functionName: "buy",
  args: [minTokensOut(quote, 100n)],
  value: tinybarsToWeibars(tinybars), // the contract receives tinybars
});
```

The hook names are `useScaffoldReadContract` and `useScaffoldWriteContract`, not `useScaffoldContractRead` or `useScaffoldContractWrite`. Also available: `useScaffoldWatchContractEvent`, `useScaffoldEventHistory`, `useDeployedContractInfo`, `useScaffoldContract`, `useTransactor`.

An HTS token answers ERC-20 reads (`name`, `symbol`, `balanceOf`) and the HIP-719 calls `associate()` and `isAssociated()` at its own address. Call those with wagmi's `useReadContract` and `useWriteContract`, as `SaleCard.tsx` does. An account must associate with the token before it can receive it, unless it has a free automatic association slot (HIP-904). Accounts created from an EVM address have unlimited slots, so their first purchase associates them.

A function added by a cut (for example `bonusBps()` after the upgrade to `TokenSaleV2`) is not in the generated `Diamond` ABI. That ABI is built from the facets the deploy script cuts in when it creates the diamond, and a full deploy still cuts `TokenSale`. Read it with an inline ABI, as `SaleCard.tsx` does. The Private page calls `buyFor` and the registry through the inline ABIs in `utils/stealth/abi.ts` for the same reason. The SaucerSwap pool card calls `seedPool` and `poolInfo` through `utils/saucerswap/abi.ts`, because the reference diamond gained them by a cut.

UI: `HederaAddress` from `~~/components/scaffold-hbar` shows an address with its HashScan link. `HbarInput` and `HederaPortalFaucet` come from `@scaffold-hbar-ui/components`. Use DaisyUI classes (`btn btn-primary`, `badge`, `table`) before raw Tailwind.

## Tests

- Contract tests extend `SaleTestBase` and call everything through the diamond, the way a wallet does.
- Test behaviour, including the revert a caller would see. Lattice errors come from `@lattice/interfaces/...`, the sale's from `ITokenSale`.
- Script helpers in `scripts-js` are tested with the Node test runner: put a `*.test.js` beside the file and `yarn foundry:test` runs it.
- Frontend logic that can be wrong (units, cut planning, catalog matching, stealth-address math, announcement scanning, sweep cost, error messages, pool price and seeding math) lives in `packages/nextjs/utils` with a `*.test.ts` beside it.

## Networks

- Foundry: `packages/foundry/foundry.toml` (`hedera_testnet` 296, `hedera_mainnet` 295).
- Next.js: `packages/nextjs/scaffold.config.ts` (Hedera testnet and mainnet).
- Chainlink HBAR/USD feed addresses are constants in `DeployDiamond.s.sol`.
- Mirror node URLs, which the Inbox reads announcements from, are in `packages/nextjs/utils/stealth/announcements.ts`.
- Mainnet: the README's "Launch on mainnet" lists every change from testnet, the deploy and seeding commands, the costs and the risks. The deploy picks the Chainlink feed and the SaucerSwap V1 addresses (`SaucerSwapV1` in `DeployDiamond.s.sol`) from the chain id. The app needs `targetNetworks` in `scaffold.config.ts` and the hard-coded `initialChain` in `components/ScaffoldHbarAppWithProviders.tsx` changed.

## Style

| Style | Use |
| --- | --- |
| `UpperCamelCase` | types, components, contracts |
| `lowerCamelCase` | variables, functions |
| `CONSTANT_CASE` | constants |

Solidity is formatted by `forge fmt` (120 columns, double quotes, spaces inside braces). Scripts in `scripts-js` use Prettier 2 defaults; keep that folder flat. Next.js imports use the `~~` alias. Add `"use client"` to a component that uses hooks. Prefer `type` over `interface`. Comments say what the code cannot.
