# Lattice Hedera Template

An upgradeable HTS token sale on a [Lattice](https://github.com/dadadave80/lattice) diamond, priced by Chainlink and customizable in [Lattice Studio](https://lattice-studio-topaz.vercel.app/). A template for [Scaffold-HBAR](https://docs.hedera.com/solutions/tools/scaffold-hbar/index).

```bash
npm create scaffold-hbar@latest -- --template dadadave80/lattice-hedera-template
```

One contract address does all of this:

- **Creates an HTS token** through the Hedera Token Service and holds it as treasury.
- **Sells it for HBAR at a USD price**, converting with the Chainlink HBAR/USD feed on every purchase.
- **Upgrades while it runs.** The contract is an [EIP-2535 diamond](https://eips.ethereum.org/EIPS/eip-2535): you swap the code behind its functions with one transaction, and the address, the token and the balances stay.
- **Is composed, not hand-wired.** The diamond's base is a list of Lattice facets in one JSON file. Open that file in Lattice Studio, change it on a canvas, export it back.

## Live on Hedera testnet

The app you scaffold talks to this deployment until you deploy your own.

| What | Where |
| --- | --- |
| Diamond | [`0x4Eb94355872aB90ab258B940eE98B706dC9B2aa9`](https://hashscan.io/testnet/contract/0x4Eb94355872aB90ab258B940eE98B706dC9B2aa9) |
| Deploy transaction | [`0x2f19856bb704bbd940e9415ea31423e87fb4e53d3a70c7d106400d5071642ca2`](https://hashscan.io/testnet/transaction/0x2f19856bb704bbd940e9415ea31423e87fb4e53d3a70c7d106400d5071642ca2) |
| HTS token created by the diamond | [`0x0000000000000000000000000000000000A59b36`](https://hashscan.io/testnet/token/0x0000000000000000000000000000000000A59b36) |
| A purchase priced by Chainlink | [`0xa3e016063a4eefafb6773540c1f5b6efb898abd3eab72bac92356b6bb9e62cc9`](https://hashscan.io/testnet/transaction/0xa3e016063a4eefafb6773540c1f5b6efb898abd3eab72bac92356b6bb9e62cc9) |
| The upgrade to `TokenSaleV2` (`diamondCut`) | [`0xe0720ff59f10e754f01e34c5633b6e31d9fef2e9028c7f1568a2a40a0b4cfd1f`](https://hashscan.io/testnet/transaction/0xe0720ff59f10e754f01e34c5633b6e31d9fef2e9028c7f1568a2a40a0b4cfd1f) |

This diamond has already been through the upgrade described below, so it runs `TokenSaleV2`. Every contract behind it, the diamond, its facets and initializers, and Lattice's factory and registry, is verified on Sourcify with an exact match, so HashScan shows the source of each one.

## Prerequisites

- [Node.js](https://nodejs.org/) 20.18.3 or newer, [Yarn](https://yarnpkg.com/) and [Git](https://git-scm.com/)
- [Foundry](https://getfoundry.sh/) (`forge`, `cast`)
- To deploy: a Hedera testnet account with HBAR. The [Hedera Portal faucet](https://portal.hedera.com/faucet) funds any EVM address.

**Deploying needs Foundry 1.7.1 for now.** Foundry 1.8 asks Hedera's JSON-RPC relay a question the relay does not answer yet ([relay issue 5826](https://github.com/hiero-ledger/hiero-json-rpc-relay/issues/5826)), so `forge script` stops with `-32602 Invalid parameter 1`. Building and testing work on any recent Foundry. To switch:

```bash
foundryup --install v1.7.1
```

## Quick start

```bash
npm create scaffold-hbar@latest -- --template dadadave80/lattice-hedera-template
cd <your-project>
yarn foundry:test   # contracts and scripts, against mocks: no chain needed
yarn next:dev       # http://localhost:3000
```

The app opens on the sale. Connect a wallet on Hedera Testnet, get HBAR from the faucet link, then:

1. **Associate.** On Hedera an account must opt in to a token before it can receive it. The button sends that one transaction. An account created by sending HBAR to an EVM address, as MetaMask and burner accounts are, has unlimited automatic associations ([HIP-904](https://hips.hedera.com/hip/hip-904)), so its first purchase associates it and this step is optional.
2. **Buy.** Type an HBAR amount, read the quote, confirm.

The **Diamond** page lists every facet behind the address and the functions each one serves. **Debug Contracts** lets you call any of them.

## Deploy your own diamond

```bash
yarn foundry:account:generate                # creates an encrypted keystore and prints its address
# fund that address at https://portal.hedera.com/faucet
yarn foundry:deploy --network hedera_testnet
```

Have about 60 testnet HBAR in the account. A first deployment sends up to 18 transactions. Lattice facets land on deterministic addresses, so a facet that is already on the network is reused and later deployments send fewer. Creating the token in the next step sends 20 HBAR to cover the network's creation fee. Hedera deducts only the fee ([HIP-358](https://hips.hedera.com/hip/hip-358)). The rest stays in the diamond, and the admin can withdraw it.

The deploy command:

1. reads `packages/foundry/diamond.recipe.json` and deploys each facet it names;
2. adds the Hedera layer, `HTSAdapter` and this project's `TokenSale`;
3. creates and initializes the diamond in one transaction, with your account as admin;
4. registers the Chainlink HBAR/USD feed;
5. rewrites `packages/nextjs/contracts/deployedContracts.ts`, so the app now points at your diamond;
6. verifies every contract it created on Sourcify, so HashScan shows the source. A contract that is already verified is skipped.

Then create the token. Either import the deployer key into your wallet (`yarn foundry:account:reveal-pk`) and use the **Admin** card on the sale page, or send it from the terminal:

```bash
cast send <your diamond> \
  "launchSale(string,string,string,int32,int64,uint256)" \
  "My Token" MTK "" 8 100000000000000 50000000000000000 \
  --value 20ether --gas-limit 1000000 --legacy \
  --rpc-url https://testnet.hashio.io/api --account <your keystore>
```

That creates 1,000,000 MTK with 8 decimals, priced at $0.05 each. The token is created in its own transaction because Foundry simulates a deploy script locally first, and no local EVM can run the Hedera Token Service.

Verification runs as part of the deploy. If a contract fails to verify, the deploy still succeeds and prints the command to retry that contract.

## How it works

```
                        one address
                 ┌──────────────────────┐
  buy() ───────► │       Diamond        │  every call is routed by selector
                 └──────────┬───────────┘
        ┌──────────────┬────┴─────────┬────────────────┐
        ▼              ▼              ▼                ▼
   TokenSale      HTSAdapter   ChainlinkAdapter   AccessControl, AccessControlDiamondCut,
   (this repo)    (Lattice)    (Lattice)          EmergencyStop, Receive, DiamondLoupeFacet,
        │              │              │           ERC165Facet (Lattice)
        │              ▼              ▼
        │       HTS system      Chainlink HBAR/USD
        └─────► contract 0x167  price feed
```

| File | What it is |
| --- | --- |
| `packages/foundry/diamond.recipe.json` | The Lattice base of the diamond, in Lattice Studio's recipe format. |
| `packages/foundry/script/DeployDiamond.s.sol` | Builds the diamond from the recipe and adds the Hedera layer. |
| `packages/foundry/contracts/LatticeFacets.sol` | The Lattice facets this project compiles. A facet must be imported here before a recipe can name it. |
| `packages/foundry/contracts/TokenSale.sol` | The sale facet. Stateless: it forwards to `TokenSaleLib`. |
| `packages/foundry/contracts/libraries/TokenSaleLib.sol` | The sale's logic and its storage, at a fixed [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) slot. |
| `packages/foundry/contracts/TokenSaleV2.sol` | The facet used in the upgrade walkthrough. |
| `packages/foundry/scripts-js/generateTsAbis.js` | Gives the frontend one `Diamond` contract whose ABI is the union of its facets. |
| `packages/nextjs/app/page.tsx` | The sale page. |
| `packages/nextjs/app/diamond/page.tsx` | The facet table and the upgrade tool. |

A facet holds no state. Each Lattice module is three files: an interface, a library with all the logic and a storage struct at its own slot, and a facet that forwards to the library. That split is why an upgrade can replace a facet without touching what the diamond remembers.

### Hedera details this template handles

- **Two units of HBAR.** Inside the EVM, `msg.value` is in tinybars (8 decimals). Over JSON-RPC, a transaction's `value` is in weibars (18 decimals), and the relay converts. The contracts work in tinybars. The app converts in one place, `packages/nextjs/utils/sale/units.ts`.
- **HTS answers with response codes, not reverts.** `22` is success. `TokenSaleLib` checks the code after every HTS call and reverts with a named error.
- **Association.** A buyer associates with the token once, through the token's own address ([HIP-719](https://hips.hedera.com/hip/hip-719)), or automatically on its first purchase if the account has a free automatic association slot ([HIP-904](https://hips.hedera.com/hip/hip-904)), as every account created from an EVM address does. A buyer with neither gets `TokenSaleBuyerNotAssociated`.
- **Token keys on a diamond.** A facet runs inside a `delegatecall`, so HTS only honours `delegatableContractId` keys for it. Lattice's `HTSAdapterLib` sets the admin and supply keys that way when the diamond creates the token.
- **Oracle freshness.** `ChainlinkAdapter` rejects an answer older than the limit set when the feed was registered. Testnet feeds are not kept on a production heartbeat, so the testnet default is 365 days. On mainnet the default is 25 hours. Set `HBAR_USD_MAX_STALENESS` (seconds) before deploying to choose your own.

## Upgrade your diamond

This upgrades the diamond you deployed in "Deploy your own diamond". Only a diamond's admin can cut it, and the admin of the reference diamond is the template author. Step 1 regenerates `packages/nextjs/contracts/deployedContracts.ts` from `packages/foundry/deployments/`, which is git-ignored. Without the record your own deployment wrote there, the file loses its `Diamond` and the app stops finding it.

`TokenSaleV2` is `TokenSale` with a 5% bonus and one new function, `bonusBps()`.

1. Deploy the facet. Nothing changes yet:
   ```bash
   yarn foundry:deploy --file DeployTokenSaleV2.s.sol --network hedera_testnet
   ```
2. Open the **Diamond** page with the admin wallet. The facet's address is already in the Upgrade box. **Preview cut** reads the facet's selectors and compares them with the diamond: six are replaced, one is added.
3. **Cut into the diamond.** One transaction.

The sale page now shows the bonus and quotes 5% more. The address, the token, the price, the totals and every holder's balance are what they were. `test/TokenSaleUpgrade.t.sol` asserts exactly that.

To ship your own change: copy `TokenSaleV2.sol`, change it, list its selectors in `exportSelectors()`, deploy it and cut it the same way. Two rules keep an upgrade safe: only add fields at the end of a storage struct, and never change the storage slot.

## Customize in Lattice Studio

The base of the diamond is not written in Solidity. It is this list in `packages/foundry/diamond.recipe.json`:

```json
"facets": ["ChainlinkAdapter", "AccessControlDiamondCut", "EmergencyStop", "AccessControl", "Receive", "DiamondLoupeFacet", "ERC165Facet"]
```

Lattice Studio is a visual composer for Lattice diamonds. It checks selectors, storage, initializers and upgrade authority as you edit.

1. `yarn diamond:studio` prints a link. Open it: your base is on the sheet. Nothing is uploaded; the recipe travels in the link.
2. Change it. For example, replace `ChainlinkAdapter` with `PythAdapter`.
3. Export `recipe.json` from Studio and save it over `packages/foundry/diamond.recipe.json`.
4. `yarn foundry:test`, then `yarn foundry:deploy --network hedera_testnet`.

What to know:

- **Step 4 deploys a new diamond.** To change a diamond that is already live, cut it (the section above).
- **The Hedera facets are not on Studio's sheet yet.** `HTSAdapter` and `TokenSale` are added by `DeployDiamond.s.sol` after the recipe. Studio's catalog does not carry them, and it rejects a recipe that names a facet it does not know.
- **An oracle swap leaves `TokenSale` untouched, but not the setup.** The sale reads the price through the diamond's own `latestAnswer(bytes32)`, which `ChainlinkAdapter` and `PythAdapter` both serve. Registering a feed differs: Pyth's `registerFeed` takes a price id and a confidence limit, and a Pyth price must be pushed with `updatePriceFeeds` before it can be read. The deploy script registers the Chainlink feed only; the app does not push Pyth updates.
- **A facet must be compiled into the project before a recipe can name it.** `ChainlinkAdapter`, `PythAdapter`, `Pausable`, `Multicall` and the base facets are. For another one, add its import to `contracts/LatticeFacets.sol`. If its initializer takes more than an `admin`, add an encoder in `_initStep` in `DeployDiamond.s.sol`.

The deploy script stops before sending anything when a recipe cannot be built, and says what to change:

| Message | Fix |
| --- | --- |
| `X is in the recipe but not compiled into this project` | Import `X` in `contracts/LatticeFacets.sol`. |
| `X is not in FacetInventory` | `X` is not a Lattice facet. Remove it from the recipe. |
| `selector 0x… is exported by both A and B` | Give the selector one owner in Studio, or exclude it. |
| `XInit takes arguments this template cannot encode yet` | Add an encoder in `_initStep`. |
| `init.kind must be 'steps' or 'none'` | Bundle initializers are not supported. Use steps. |
| `only {"$ref": "deployer"} is supported` | Replace `{"$ref": "self"}` with an address. |

## Add your own facet

1. Write the interface, the library and the facet under `packages/foundry/contracts/`, the way `ITokenSale`, `TokenSaleLib` and `TokenSale` are written. Give the library its own storage slot.
2. Return the facet's selectors from `exportSelectors()`.
3. For a new deployment, add the facet next to `TokenSale` in `build()` in `DeployDiamond.s.sol` and raise `HEDERA_FACETS` (and `HEDERA_INITS`, if the facet has an initializer). For a live diamond, deploy it and cut it from the Diamond page.
4. Test it through the diamond, as `test/SaleTestBase.sol` does.

## Commands

| Command | What it does |
| --- | --- |
| `yarn foundry:test` | Forge tests against a mock HTS and a mock feed, then the Node tests for the scripts. No chain needed. |
| `yarn next:test` | Unit tests for the frontend's unit conversion, cut planning and selector names. |
| `yarn next:dev` | The app, on `http://localhost:3000`. |
| `yarn foundry:deploy --network hedera_testnet` | Deploys the diamond from the recipe, regenerates the frontend's contract file, then verifies its contracts on Sourcify. |
| `yarn foundry:deploy --file DeployTokenSaleV2.s.sol --network hedera_testnet` | Deploys the upgrade facet and verifies it. |
| `yarn foundry:verify:testnet <address> <file>:<Contract>` | Verifies or re-verifies one contract's source on Sourcify by hand. The deploy already does this for each contract it creates. |
| `yarn diamond:studio` | Prints the Lattice Studio link for the current recipe. |
| `yarn foundry:account:generate` | Creates a deployer keystore. |
| `yarn lint` | Lints the frontend and checks Solidity and script formatting. |
| `yarn next:build` | Production build of the app. |

Environment variables are optional. `packages/foundry/.env.example` and `packages/nextjs/.env.example` list them.

## Troubleshooting

| You see | Cause and fix |
| --- | --- |
| `-32602 Invalid parameter 1` during deploy | Foundry 1.8 against Hedera's relay. `foundryup --install v1.7.1`. |
| `Requested resource not found. address '0x…'` | The deployer address does not exist on Hedera yet. Fund it from the faucet. |
| `Sender account not found` in the app | The connected wallet has never received HBAR, so Hedera has no account for it. The sale card disables its buttons until it holds some. Fund it from the faucet or another wallet; a first transfer to a new address creates the account and needs about 600,000 gas. |
| `DeployDiamond: this diamond needs Hedera` | You deployed to a local chain. This diamond needs HTS and a Chainlink feed: use `--network hedera_testnet`. |
| `TokenSaleBuyerNotAssociated` | The buyer has not associated with the token. Use the Associate button. |
| `ChainlinkStaleData` | The feed's last update is older than the registered limit. Register the feed again with a larger `maxStaleness`. |
| `HTSCallFailed` on `launchSale` | The HBAR sent did not cover the creation fee. Send more with `--value`. |
| "No diamond on Hedera Mainnet" in the app | The wallet is on a network this project has no diamond on. Switch to Hedera Testnet. |

## Limits

- Not audited. Lattice is pre-1.0 and unaudited too. Do not put real value behind this without a review.
- There is no local-chain mode. HTS and the Chainlink feed exist only on Hedera, so contract tests run against mocks and the app runs against testnet.
- A recipe can name another admin, but the deploy script also makes the deploying account admin and gives it `HTS_MANAGER_ROLE` and `HTS_OPERATOR_ROLE`. It needs admin to register the feed and the manager role to let the sale create the token. To hand over control, grant `DEFAULT_ADMIN_ROLE`, `HTS_MANAGER_ROLE` and `HTS_OPERATOR_ROLE` to the new admin, then have the deployer renounce all three after the deploy.
- The app's upgrade card plans Add and Replace only. A function the outgoing facet serves that the new facet does not export stays routed to the old facet, and the preview lists it under "Still served by the outgoing facet". Removing them is a separate Remove cut, for example from Debug Contracts or with `cast`.
- The package manager is Yarn.

## Links

- [Lattice](https://github.com/dadadave80/lattice), the diamond module library, and its [Hedera guide](https://github.com/dadadave80/lattice/blob/feat/hedera-system-contract-modules/docs/guides/hedera.md)
- [Lattice Studio](https://github.com/dadadave80/lattice-studio)
- [Scaffold-HBAR docs](https://docs.hedera.com/solutions/tools/scaffold-hbar/index) and [create-scaffold-hbar](https://github.com/hedera-dev/create-scaffold-hbar)
- [Chainlink price feeds on Hedera](https://docs.chain.link/data-feeds/price-feeds/addresses?network=hedera)
- [HashScan](https://hashscan.io/testnet)

MIT licensed. See [LICENCE](LICENCE).
