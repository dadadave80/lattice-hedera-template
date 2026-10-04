# Lattice Hedera Template

An upgradeable HTS token sale on a [Lattice](https://github.com/dadadave80/lattice) diamond, priced by Chainlink, with private purchases to ERC-5564 stealth addresses, and customizable in [Lattice Studio](https://lattice-studio-git-feat-hedera-david-dadas-projects.vercel.app/). A template for [Scaffold-HBAR](https://docs.hedera.com/solutions/tools/scaffold-hbar/index).

```bash
npm create scaffold-hbar@latest -- --template dadadave80/lattice-hedera-template
```

One contract address does all of this:

- **Creates an HTS token** through the Hedera Token Service and holds it as treasury.
- **Sells it for HBAR at a USD price.** Every purchase reads the Chainlink HBAR/USD feed, so the price holds in dollars while HBAR moves. See [Why Chainlink](#why-chainlink).
- **Upgrades while it runs.** The contract is an [EIP-2535 diamond](https://eips.ethereum.org/EIPS/eip-2535): you swap the code behind its functions with one transaction, and the address, the token and the balances stay.
- **Delivers to people who have nothing on Hedera yet.** A buyer pays for someone else, and the tokens land on a one-time [ERC-5564](https://eips.ethereum.org/EIPS/eip-5564) stealth address that nothing on chain ties to the recipient. That address has no account, no token association and no HBAR, and the purchase gives it all three in one transaction: the HBAR sent with it creates the account ([HIP-583](https://hips.hedera.com/hip/hip-583)), the account takes the token without associating first ([HIP-904](https://hips.hedera.com/hip/hip-904)), and what is left of that HBAR pays for moving the tokens on. A gift, a grant or a payroll run reaches people without asking them to set anything up. See [Private purchases](#private-purchases).
- **Is composed, not hand-wired.** Every Lattice facet in the diamond, `HTSAdapter` and the stealth-address registry and announcer included, is listed in one JSON file. Open that file in Lattice Studio, change it on a canvas, export it back.

## Live on Hedera testnet

The app you scaffold talks to this deployment until you deploy your own.

| What | Where |
| --- | --- |
| Diamond | [`0x4Eb94355872aB90ab258B940eE98B706dC9B2aa9`](https://hashscan.io/testnet/contract/0x4Eb94355872aB90ab258B940eE98B706dC9B2aa9) |
| Deploy transaction | [`0x2f19856bb704bbd940e9415ea31423e87fb4e53d3a70c7d106400d5071642ca2`](https://hashscan.io/testnet/transaction/0x2f19856bb704bbd940e9415ea31423e87fb4e53d3a70c7d106400d5071642ca2) |
| HTS token created by the diamond | [`0x0000000000000000000000000000000000A59b36`](https://hashscan.io/testnet/token/0x0000000000000000000000000000000000A59b36) |
| A purchase priced by Chainlink | [`0xa3e016063a4eefafb6773540c1f5b6efb898abd3eab72bac92356b6bb9e62cc9`](https://hashscan.io/testnet/transaction/0xa3e016063a4eefafb6773540c1f5b6efb898abd3eab72bac92356b6bb9e62cc9) |
| The upgrade to `TokenSaleV2` (`diamondCut`) | [`0xe0720ff59f10e754f01e34c5633b6e31d9fef2e9028c7f1568a2a40a0b4cfd1f`](https://hashscan.io/testnet/transaction/0xe0720ff59f10e754f01e34c5633b6e31d9fef2e9028c7f1568a2a40a0b4cfd1f) |

This diamond has already been through the upgrade described below, so it runs `TokenSaleV2`. It predates private purchases and received them by a second cut, listed with a private purchase and its sweep under [Private purchases on testnet](#private-purchases-on-testnet). Every contract behind it, the diamond, its facets and initializers, and Lattice's factory and registry, is verified on Sourcify with an exact match, so HashScan shows the source of each one. A diamond composed and deployed from Lattice Studio is listed under [Customize in Lattice Studio](#customize-in-lattice-studio).

## Prerequisites

- [Node.js](https://nodejs.org/) 20.18.3 or newer, [Yarn](https://yarnpkg.com/) and [Git](https://git-scm.com/)
- [Foundry](https://getfoundry.sh/) (`forge`, `cast`)
- Testnet HBAR. The [Hedera Portal faucet](https://portal.hedera.com/faucet) funds any EVM address: 10 testnet HBAR a day without an account, and 100 with a free Hedera Portal account. Trying the app against the reference diamond fits in 10 HBAR. Deploying your own diamond and launching its sale need about 80 HBAR.

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

The app opens on the **Private** page, which buys the sale's token for someone else without naming them on chain (see [Private purchases](#private-purchases)). To buy for yourself, open the **Sale** page at `/sale`, connect a wallet on Hedera Testnet, get HBAR from the faucet link, then:

1. **Associate.** On Hedera an account must opt in to a token before it can receive it. The button sends that one transaction. An account created by sending HBAR to an EVM address, as MetaMask and burner accounts are, has unlimited automatic associations ([HIP-904](https://hips.hedera.com/hip/hip-904)), so its first purchase associates it and this step is optional.
2. **Buy.** Type an HBAR amount, read the quote, confirm.

The **Diamond** page lists every facet behind the address and the functions each one serves. **Debug Contracts** lets you call any of them.

### Try a private purchase alone

One wallet can play both sides. The payer is public on chain, so this run shows the flow, not the privacy.

1. **Fund the wallet.** On the **Private** page, connect a wallet on Hedera Testnet and fund it from the faucet. The purchase below needs about 5 HBAR in the wallet when it is sent: 2 HBAR of payment, the 1 HBAR stipend, and the network fee's hold of 2,000,000 gas, about 1.7 HBAR, of which about 1.2 HBAR is charged.
2. **Register.** Under **Receive privately**, click **Sign to derive your keys**, then **Register**. The Inbox uses the same keys.
3. **Buy for yourself.** Under **Buy for someone privately**, enter your own wallet address as the recipient and 2 HBAR, then click **Buy privately**. The summary shows what it sends and the network fee before you confirm.
4. **Find the delivery.** The **Inbox** lists it with its token and HBAR balances within a minute. **Refresh** checks sooner.
5. **Sweep.** Enter an address that already exists on Hedera and that nothing ties to you (a new address funded from the faucet works), then click **Sweep**. A sweep to an address with no account creates it, which costs about 0.67 HBAR of the 1 HBAR stipend. The Inbox checks that cost before it enables **Sweep**.

## Deploy your own diamond

```bash
yarn foundry:account:generate                # creates an encrypted keystore and prints its address
# fund that address at https://portal.hedera.com/faucet
yarn foundry:deploy --network hedera_testnet
```

Have about 80 testnet HBAR in the account: up to 60 for the deployment and 20 for creating the token. A first deployment sends up to 23 transactions. Lattice facets land on deterministic addresses, so a facet that is already on the network is reused and later deployments send fewer. Creating the token in the next step sends 20 HBAR to cover the network's creation fee. Hedera deducts only the fee ([HIP-358](https://hips.hedera.com/hip/hip-358)). The rest stays in the diamond, and the admin can withdraw it.

The deploy command:

1. reads `packages/foundry/diamond.recipe.json` and deploys each Lattice facet it names, `HTSAdapter`, `ERC6538Registry` and `ERC5564Announcer` among them;
2. adds this project's `TokenSale` and `StealthBuy`;
3. creates and initializes the diamond in one transaction, with your account as admin (the recipe's `{"$ref": "deployer"}`);
4. registers the Chainlink HBAR/USD feed and makes your account an emergency guardian, which can halt `buy` and `buyFor` with `emergencyStop`;
5. rewrites `packages/nextjs/contracts/deployedContracts.ts`, so the app now points at your diamond;
6. verifies every contract it created on Sourcify, so HashScan shows the source. A contract that is already verified is skipped.

Then create the token. Either import the deployer key into your wallet (`yarn foundry:account:reveal-pk`) and use the **Admin** card on the **Sale** page (`/sale`), or send it from the terminal:

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
  buyFor() ────► │                      │
                 └──────────┬───────────┘
        ┌──────────────┬────┴─────────┬────────────────┐
        ▼              ▼              ▼                ▼
   TokenSale,     HTSAdapter   ChainlinkAdapter   ERC6538Registry, ERC5564Announcer,
   StealthBuy     (recipe)     (recipe)           AccessControl, AccessControlDiamondCut,
   (this repo)         │              │           EmergencyStop, Receive, DiamondLoupeFacet,
        │              ▼              ▼           ERC165Facet (recipe)
        │       HTS system      Chainlink HBAR/USD
        └─────► contract 0x167  price feed
```

A facet marked *recipe* is a Lattice facet named in `packages/foundry/diamond.recipe.json`, the file Lattice Studio composes. `TokenSale` and `StealthBuy` are this project's own facets, and the deploy script adds them.

| File | What it is |
| --- | --- |
| `packages/foundry/diamond.recipe.json` | Every Lattice facet of the diamond, `HTSAdapter`, `ERC6538Registry` and `ERC5564Announcer` included, and their initializers, in Lattice Studio's recipe format. |
| `packages/foundry/script/DeployDiamond.s.sol` | Builds the diamond from the recipe and adds `TokenSale` and `StealthBuy`. |
| `packages/foundry/script/DeployStealthBuy.s.sol` | Adds private purchases to a diamond deployed before them, in one cut. |
| `packages/foundry/contracts/LatticeFacets.sol` | The Lattice facets this project compiles. A facet must be imported here before a recipe can name it. |
| `packages/foundry/contracts/TokenSale.sol` | The sale facet. Stateless: it forwards to `TokenSaleLib`. |
| `packages/foundry/contracts/libraries/TokenSaleLib.sol` | The sale's logic and its storage, at a fixed [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) slot. |
| `packages/foundry/contracts/StealthBuy.sol`, `libraries/StealthBuyLib.sol` | The private-purchase facet and its logic. It has no storage of its own: a private purchase is a sale, so it books into the sale's storage. |
| `packages/foundry/contracts/UpgradeMultiInit.sol` | Runs Lattice initializers inside a cut on a diamond that already exists. |
| `packages/foundry/contracts/TokenSaleV2.sol` | The facet used in the upgrade walkthrough. |
| `packages/foundry/scripts-js/generateTsAbis.js` | Gives the frontend one `Diamond` contract whose ABI is the union of its facets. |
| `packages/nextjs/app/page.tsx` | The Private page, where the app opens: register, buy for someone privately, and the inbox. |
| `packages/nextjs/app/sale/page.tsx` | The Sale page, at `/sale`. |
| `packages/nextjs/utils/stealth/` | ERC-5564 stealth-address math and the announcement scan, with their tests. |
| `packages/nextjs/app/diamond/page.tsx` | The facet table, the Lattice Studio card and the upgrade tool. |

A facet holds no state. Each Lattice module is three files: an interface, a library with all the logic and a storage struct at its own slot, and a facet that forwards to the library. That split is why an upgrade can replace a facet without touching what the diamond remembers.

### Hedera details this template handles

- **Two units of HBAR.** Inside the EVM, `msg.value` is in tinybars (8 decimals). Over JSON-RPC, a transaction's `value` is in weibars (18 decimals), and the relay converts. The contracts work in tinybars. The app converts in one place, `packages/nextjs/utils/sale/units.ts`.
- **HTS answers with response codes, not reverts.** `22` is success. `TokenSaleLib` checks the code after every HTS call and reverts with a named error.
- **Association.** A buyer associates with the token once, through the token's own address ([HIP-719](https://hips.hedera.com/hip/hip-719)), or automatically on its first purchase if the account has a free automatic association slot ([HIP-904](https://hips.hedera.com/hip/hip-904)), as every account created from an EVM address does. A buyer with neither gets `TokenSaleBuyerNotAssociated`.
- **Token keys on a diamond.** A facet runs inside a `delegatecall`, so HTS only honours `delegatableContractId` keys for it. Lattice's `HTSAdapterLib` sets the admin and supply keys that way when the diamond creates the token.
- **Oracle freshness.** `ChainlinkAdapter` rejects an answer older than the limit set when the feed was registered. Testnet feeds are not kept on a production heartbeat, so the testnet default is 365 days. On mainnet the default is 25 hours. Set `HBAR_USD_MAX_STALENESS` (seconds) before deploying to choose your own.
- **Addresses that are not accounts yet.** HBAR sent to an EVM address with no account creates one, a hollow account ([HIP-583](https://hips.hedera.com/hip/hip-583)), with unlimited automatic token associations. Its first signed transaction completes it with the signer's key. `buyFor` creates the stealth account this way, which costs far more gas than a plain purchase, so give it an explicit gas limit.

## Private purchases

The **Private** page buys the sale's token for someone else without naming them on chain. The tokens go to a one-time [ERC-5564](https://eips.ethereum.org/EIPS/eip-5564) stealth address that only the recipient can recognize and spend from.

What each side does:

1. **The recipient registers once.** Under **Receive privately**, they sign one fixed message. The app derives a spending key and a viewing key from the signature and registers the stealth meta-address built from their public keys with `registerKeys(1, metaAddress)` on the diamond's [ERC-6538](https://eips.ethereum.org/EIPS/eip-6538) registry. The keys stay in the open tab, and signing again derives the same ones.
2. **The payer buys for them.** Under **Buy for someone privately**, they enter the recipient's wallet address and an HBAR amount. The app reads the recipient's meta-address from the registry; the payer can also paste the meta-address itself, bare or as `st:<chain>:0x…`, and then the recipient need not have registered at all. The app derives a fresh stealth address from it with a random ephemeral key (ERC-5564 scheme 1: secp256k1 with view tags), and calls `buyFor` with the payment plus a stipend, 0.5 HBAR by default.
3. **The recipient finds and sweeps.** The **Inbox** reads the diamond's `Announcement` events from the mirror node, checks each one against the viewing key in the browser, and lists the stealth addresses that belong to the recipient with their token and HBAR balances. **Sweep** sends the tokens to an address the recipient enters, signed in the browser with the stealth address's own key. The wallet never sees that key.

What `buyFor(stealthAddress, ephemeralPubKey, viewTag, minTokensOut, stipend)` does, in one transaction:

1. Prices `msg.value` minus the stipend with the diamond's own `quote`, so a private purchase gets the same Chainlink price as `buy`, and the bonus on a diamond that runs `TokenSaleV2`. It reverts below `minTokensOut` and adds the payment, not the stipend, to the sale's totals.
2. Sends the stipend to the stealth address with a plain call. The address has no account, so the HBAR creates one, with unlimited automatic token associations ([HIP-904](https://hips.hedera.com/hip/hip-904)).
3. Transfers the tokens from the diamond's treasury to the new account through the HTS system contract, checking the response code as `buy` does. The account associates with the token as it receives it.
4. Emits ERC-5564's `Announcement` with scheme id 1, the payer as `caller`, the ephemeral public key, and 57 bytes of metadata: the view tag, the ERC-20 `transfer` selector `0xa9059cbb`, the token's address and the amount. Then it emits `StealthDelivery` with the tokens, the payment and the stipend.

The sweep is the stealth account's first transaction. Hedera completes the hollow account with the key that signed it, and the stipend pays the gas. A sweep cost about 0.03 HBAR on testnet. The sweep moves the tokens only: the rest of the stipend stays on the stealth address.

Creating the account makes a private purchase cost more gas than `buy`: 1,433,536 gas, about 1.2 HBAR on testnet, paid by the payer. Hedera charges the gas used, but the payer must hold the whole limit's worth when sending, so the app sets a limit of 2,000,000.

### Why this is simple on Hedera

A stealth address is new by design, so nothing exists at it yet. On Hedera that would mean two steps for the recipient before a token could reach them: an address is not an account until something creates it, and an HTS token reaches only an account associated with it. HIP-583 and HIP-904 move both steps into the payer's transaction. The HBAR that creates the account also pays for its first transaction, so the recipient needs no relayer and no HBAR of their own to move the tokens. The rest is what the sale already uses: HTS for the token and the treasury transfer, and the Chainlink HBAR/USD feed for the price.

### Privacy model

- **Unlinkable: the recipient.** Nothing on chain ties a stealth address to the wallet that registered the meta-address it was derived from.
- **Public: the payer, the amount, the time, and that a stealth delivery happened.** The payer sends the transaction and is the announcement's indexed `caller`. The payment, the stipend and the tokens are in `StealthDelivery` and in the announcement's metadata.
- **The anonymity set is everyone who registered a meta-address on this diamond.** An observer can tell a delivery went to one of them, not to which one. A small set hides little.
- **Sweeping to the registering wallet re-links it to the delivery**, as does sweeping to any address tied to that wallet. The Inbox warns when the destination is the connected wallet.
- **The keys come from a signature.** Anyone who can make the wallet sign the same message can derive the same keys, find every delivery and spend it. The message says to sign it only on this site.
- **The Inbox reads every announcement.** It fetches all of the diamond's announcements and checks them in the browser, so the mirror node does not learn which deliveries are the reader's. The balance reads and the sweep that follow go through the app's JSON-RPC endpoint, and the Hedera account ID shown for each one comes through the app's own `/api/hedera/account` route. Both see the stealth addresses one browser asks about.
- **Anyone can announce.** The diamond's `ERC5564Announcer` lets any account emit an `Announcement`. The Inbox keeps the first announcement for each stealth address and uses the sale's token, not the token an announcement names.

### Private purchases on testnet

The reference diamond predates `StealthBuy`, so its admin added private purchases with `DeployStealthBuy.s.sol` (below):

| What | Where |
| --- | --- |
| The cut that added `StealthBuy`, `ERC6538Registry` and `ERC5564Announcer` and ran their initializers | [`0xd18506b3c9efbb7f9dae6fdc594cce31ed7af1cae825a1de0b6dac83df692fa3`](https://hashscan.io/testnet/transaction/0xd18506b3c9efbb7f9dae6fdc594cce31ed7af1cae825a1de0b6dac83df692fa3) |
| `StealthBuy` | [`0xC02a53F91385DA8603c18d531626b74ebe0CE859`](https://hashscan.io/testnet/contract/0xC02a53F91385DA8603c18d531626b74ebe0CE859) |
| `ERC6538Registry` | [`0xC29dA6507822a117153B77a42ACF4bE59B8C57e0`](https://hashscan.io/testnet/contract/0xC29dA6507822a117153B77a42ACF4bE59B8C57e0) |
| `ERC5564Announcer` | [`0xD0Eb7D476002c23f4AAF36344058067EA2a12492`](https://hashscan.io/testnet/contract/0xD0Eb7D476002c23f4AAF36344058067EA2a12492) |
| The recipient `0x061Af5392697EDD4BD08f326f7BeCaE1fe035b64` registers its meta-address | [`0xa4388212f333018c91fcc91a8cee97602ede279f8aa4a1337ef6ce915b1ae2be`](https://hashscan.io/testnet/transaction/0xa4388212f333018c91fcc91a8cee97602ede279f8aa4a1337ef6ce915b1ae2be) |
| Another account buys 2 HBAR of tokens for it with `buyFor` (1,433,536 gas). The recipient's address appears nowhere in it | [`0x33d9fd88062301e4607b1438c0f45e6bf731294ad6901f55d8cb2da75ae26006`](https://hashscan.io/testnet/transaction/0x33d9fd88062301e4607b1438c0f45e6bf731294ad6901f55d8cb2da75ae26006) |
| The stealth account it created | [`0xE34b6e5Ac8FEc6e07c3Fc5846E53A444CFCfC326`](https://hashscan.io/testnet/account/0xE34b6e5Ac8FEc6e07c3Fc5846E53A444CFCfC326) |
| The sweep to a fresh account, signed by the stealth account (36,892 gas) | [`0x70f7a839d211ed29ad559f13e38ed8f61283e4757385653b8c55ee15964fbbad`](https://hashscan.io/testnet/transaction/0x70f7a839d211ed29ad559f13e38ed8f61283e4757385653b8c55ee15964fbbad) |

The same flow ran through the **Private** page with the app's burner wallet: [register](https://hashscan.io/testnet/transaction/0x8854f0c12b59d2696e104945b3f979f721d50667db24c7b4cace4e404bbcb8a1), [buy privately](https://hashscan.io/testnet/transaction/0x7a48b780617ed5483847437e9c85da97c96d836a18729faea5c72ee5ec4511d4), [sweep](https://hashscan.io/testnet/transaction/0xfe92af609c889f07a393afd1ca48777a14aac3660ce99a86cf98c5feba2deae9).

Before `StealthBuy` was written, each Hedera behavior it depends on was tried on testnet:

| Step | Transaction |
| --- | --- |
| HBAR sent from a contract to a fresh address creates a hollow account with unlimited automatic associations (645,737 gas) | [`0xc3a8acf41ee5b43ed3078fef78a4fe2eb54b2b6a394a6b400ca55043bda0e3ff`](https://hashscan.io/testnet/transaction/0xc3a8acf41ee5b43ed3078fef78a4fe2eb54b2b6a394a6b400ca55043bda0e3ff) |
| An HTS transfer from a diamond to that hollow account delivers the token and associates it (756,050 gas) | [`0x698c8ac1d2dadaa0cfa6cb4d2cc0100e3aa71179c6d4b8dbf535e7eb681f42b4`](https://hashscan.io/testnet/transaction/0x698c8ac1d2dadaa0cfa6cb4d2cc0100e3aa71179c6d4b8dbf535e7eb681f42b4) |
| The hollow account's first transaction, a token transfer signed with its own key, completes the account (36,880 gas) | [`0x8ecf0d739c3011400950516a21de393d0221a61571a1f378208117431154122c`](https://hashscan.io/testnet/transaction/0x8ecf0d739c3011400950516a21de393d0221a61571a1f378208117431154122c) |

### Add private purchases to an existing diamond

A diamond deployed from the current recipe has them. One deployed before them, such as the reference diamond, gets them from its admin:

```bash
yarn foundry:deploy --file DeployStealthBuy.s.sol --network hedera_testnet
```

The script reads the diamond from `packages/foundry/deployments/diamond/<chainId>.json`, deploys `StealthBuy`, `ERC6538Registry`, `ERC5564Announcer` and their initializers, and adds the three facets with one `diamondCut`. A Lattice initializer only runs while a diamond is initializing, so the cut runs them through `UpgradeMultiInit`, which opens the diamond's next reinitializer version around them. The account that sends it must hold the diamond's `DEFAULT_ADMIN_ROLE`. After a broadcast the script adds the facets to the deployment record, so the regenerated `Diamond` ABI lists `buyFor` and the registry; a run without `--broadcast` leaves the record alone. As with every deploy, the new contracts are then verified on Sourcify. On a diamond that already has the facets, the cut reverts.

## Upgrade your diamond

This upgrades the diamond you deployed in "Deploy your own diamond". Only a diamond's admin can cut it, and the admin of the reference diamond is the template author. Step 1 regenerates `packages/nextjs/contracts/deployedContracts.ts` from `packages/foundry/deployments/`, which is git-ignored. Without the record your own deployment wrote there, the file loses its `Diamond` and the app stops finding it.

`TokenSaleV2` is `TokenSale` with a 5% bonus and one new function, `bonusBps()`.

1. Deploy the facet. Nothing changes yet:
   ```bash
   yarn foundry:deploy --file DeployTokenSaleV2.s.sol --network hedera_testnet
   ```
2. Open the **Diamond** page with the admin wallet. The facet's address is already in the Upgrade box. **Preview cut** reads the facet's selectors and compares them with the diamond: six are replaced, one is added.
3. **Cut into the diamond.** One transaction.

The sale page now shows the bonus and quotes 5% more. Private purchases get the bonus too, because `StealthBuy` prices through the diamond's own `quote`. The address, the token, the price, the totals and every holder's balance are what they were. `test/TokenSaleUpgrade.t.sol` asserts exactly that.

To ship your own change: copy `TokenSaleV2.sol`, change it, list its selectors in `exportSelectors()`, deploy it and cut it the same way. Two rules keep an upgrade safe: only add fields at the end of a storage struct, and never change the storage slot.

## Customize in Lattice Studio

The Lattice part of the diamond is not written in Solidity. It is this list in `packages/foundry/diamond.recipe.json`:

```json
"facets": ["ChainlinkAdapter", "HTSAdapter", "ERC5564Announcer", "ERC6538Registry", "AccessControlDiamondCut", "EmergencyStop", "AccessControl", "Receive", "DiamondLoupeFacet", "ERC165Facet"]
```

followed by four init steps: `ChainlinkAdapterInit` and `HTSAdapterInit`, which make the deploying account admin, and `ERC6538RegistryInit` and `ERC5564AnnouncerInit`, which take no arguments.

[Lattice Studio](https://lattice-studio-git-feat-hedera-david-dadas-projects.vercel.app/) is a visual composer for Lattice diamonds. It checks selectors, storage, initializers and upgrade authority as you edit. The build linked here is Studio's Hedera build. It has Hedera Testnet as a deploy target, and its catalog, `dev-6c8db45`, is built from the Lattice commit this template pins, with Lattice's Hedera facets in it: `HTSAdapter`, `HSSAdapter`, `HederaExchangeRateAdapter`, `HederaPrngAdapter` and `HASSignatureVerifier`. The catalog also has Lattice's `ERC6538Registry` and `ERC5564Announcer`. The whole Lattice part of the diamond, `HTSAdapter` and those two included, is composed and checked on Studio's sheet.

1. `yarn diamond:studio` prints a link. Open it: your recipe is on the sheet. Nothing is uploaded; the recipe travels in the link.
2. Change it. For example, replace `ChainlinkAdapter` with `PythAdapter` (the sale then needs a Pyth feed registered and updated; see the oracle note below).
3. Export `recipe.json` from Studio and save it over `packages/foundry/diamond.recipe.json`.
4. `yarn foundry:test`, then `yarn foundry:deploy --network hedera_testnet`. The deploy script adds `TokenSale` and `StealthBuy` to what the recipe names.

A diamond without the sale needs no Solidity at all. Choose Hedera Testnet in Studio and deploy it from the app with a wallet, or export Studio's Foundry script and run it. Either way it goes through `LatticeFactory`, Studio's default path; the CreateX path is not available because CreateX is not on Hedera. Lattice's shared contracts a recipe needs and the chain does not have yet go out first, through Arachnid's deterministic deployment proxy, and Studio verifies the diamond it deploys on Sourcify.

A diamond composed in [Studio's Hedera build](https://lattice-studio-git-feat-hedera-david-dadas-projects.vercel.app/), `HTSAdapter` on the sheet, went out on testnet through the Foundry script Studio exports, then created an HTS token through its own `HTSAdapter`:

| What | Where |
| --- | --- |
| Diamond composed in Studio | [`0xFDd6e099fF4b48a9179443A9D846AfA816997e23`](https://hashscan.io/testnet/contract/0xFDd6e099fF4b48a9179443A9D846AfA816997e23) |
| Its deploy transaction, through `LatticeFactory` | [`0x53b08097c1a742c49bc59b40311e51cd4910309cba5e361d51ad05be694dcf00`](https://hashscan.io/testnet/transaction/0x53b08097c1a742c49bc59b40311e51cd4910309cba5e361d51ad05be694dcf00) |
| HTS token it created | [`0x0000000000000000000000000000000000a5B060`](https://hashscan.io/testnet/token/0x0000000000000000000000000000000000a5B060) |

Studio's diamond and the 14 shared contracts it uses are verified on Sourcify with an exact match, like the reference diamond. The two diamonds use separate copies of Lattice's facets, at different addresses: this template compiles Lattice with its own settings (`cancun`, 200 optimizer runs) and deploys its own copies, while Studio deploys one shared release per chain from its catalog, compiled with Lattice's settings (`osaka`, 1,000,000 runs).

The live diamond opens in Studio too. The Lattice Studio card on the Diamond page reads the diamond's loupe, names each facet from Studio's catalog by the exact set of selectors it serves, and links to Studio with those facets on the sheet. For each one it shows the catalog's summary, the storage namespace the facet owns, and whether Lattice's shared release of it has code on the network. Facets the catalog does not have, such as `TokenSale`, its upgrades and `StealthBuy`, are listed as this template's own and stay out of the link. The link carries facets, not the diamond's init history: its recipe runs no init, so Studio flags each facet that takes one, even though the live diamond ran its inits when it was created. The card only reads; upgrade the diamond with a cut.

What to know:

- **Step 4 deploys a new diamond.** To change a diamond that is already live, cut it (the section above).
- **`TokenSale` and `StealthBuy` are not on Studio's sheet.** They are this project's facets, not Lattice's, so Studio's catalog does not carry them, and Studio rejects a recipe that names a facet it does not know. `DeployDiamond.s.sol` adds them after the recipe's facets.
- **Keep `HTSAdapter` and its `HTSAdapterInit` step.** `TokenSale` creates its token through `HTSAdapter`, with the roles `HTSAdapterInit` grants. The deploy script stops before sending anything when either is missing.
- **Keep `ERC6538Registry` for private purchases.** The Private page registers and looks up meta-addresses through the diamond's `ERC6538Registry`, so without it no one can register there or be found. The deploy script does not check for it. `buyFor` emits its own `Announcement`, so `ERC5564Announcer` is not needed for a delivery; it serves ERC-5564's `announce` for anyone else.
- **Place `HTSAdapter` from the catalog.** Studio's gallery lists an `HTSAdapter` recipe template as arriving in v1.1. The facet itself is in the catalog today, and the link `yarn diamond:studio` prints already has it on the sheet.
- **An oracle swap leaves `TokenSale` untouched, but not the setup.** The sale reads the price through the diamond's own `latestAnswer(bytes32)`, which `ChainlinkAdapter` and `PythAdapter` both serve. Registering a feed differs: Pyth's `registerFeed` takes a price id and a confidence limit, and a Pyth price must be pushed with `updatePriceFeeds` before it can be read. The deploy script registers the Chainlink feed only; the app does not push Pyth updates.
- **A facet must be compiled into the project before a recipe can name it.** `ChainlinkAdapter`, `HTSAdapter`, `PythAdapter`, `ERC6538Registry`, `ERC5564Announcer`, `Pausable`, `Multicall` and the base facets are. For another one, such as `HSSAdapter`, add its import (and its initializer's) to `contracts/LatticeFacets.sol`. If its initializer takes anything other than one `admin` or no argument at all, add an encoder in `_initStep` in `DeployDiamond.s.sol`.

The deploy script stops before sending anything when a recipe cannot be built, and says what to change:

| Message | Fix |
| --- | --- |
| `X is in the recipe but not compiled into this project` | Import `X` in `contracts/LatticeFacets.sol`. |
| `X is not in FacetInventory` | `X` is not a Lattice facet. Remove it from the recipe. |
| `TokenSale creates its token through HTSAdapter` | Add `HTSAdapter` and its `HTSAdapterInit` step in Studio. |
| `selector 0x… is exported by both A and B` | Give the selector one owner in Studio, or exclude it. |
| `XInit takes arguments this template cannot encode yet` | Add an encoder in `_initStep`. |
| `init.kind must be 'steps' or 'none'` | Bundle initializers are not supported. Use steps. |
| `only {"$ref": "deployer"} is supported` | Replace `{"$ref": "self"}` with an address. |

## Add your own facet

1. Write the interface, the library and the facet under `packages/foundry/contracts/`, the way `ITokenSale`, `TokenSaleLib` and `TokenSale` are written. Give the library its own storage slot.
2. Return the facet's selectors from `exportSelectors()`.
3. For a new deployment, add the facet next to `TokenSale` and `StealthBuy` in `build()` in `DeployDiamond.s.sol` and raise `HEDERA_FACETS`, 2 today (and `HEDERA_INITS`, also 2, if the facet has an initializer). For a live diamond, deploy it and cut it from the Diamond page. A facet whose initializer must run goes in with a script instead, as `DeployStealthBuy.s.sol` does: on a live diamond a Lattice initializer runs only through `UpgradeMultiInit`.
4. Test it through the diamond, as `test/SaleTestBase.sol` does.

## Commands

| Command | What it does |
| --- | --- |
| `yarn foundry:test` | Forge tests against a mock HTS and a mock feed, then the Node tests for the scripts. No chain needed. |
| `yarn next:test` | Unit tests for the frontend's unit conversion, cut planning, selector names, Studio catalog matching, stealth-address math and announcement scanning. |
| `yarn next:dev` | The app, on `http://localhost:3000`. |
| `yarn foundry:deploy --network hedera_testnet` | Deploys the diamond from the recipe, regenerates the frontend's contract file, then verifies its contracts on Sourcify. |
| `yarn foundry:deploy --file DeployTokenSaleV2.s.sol --network hedera_testnet` | Deploys the upgrade facet and verifies it. |
| `yarn foundry:deploy --file DeployStealthBuy.s.sol --network hedera_testnet` | Adds private purchases to a diamond deployed before them, in one cut. Run it from the diamond's admin account. |
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
| `INSUFFICIENT_GAS` on `buyFor` | `buyFor` creates the stealth account and associates it with the token, which takes far more gas than a plain purchase. The **Private** page sets 2,000,000; it used 1,433,536 on testnet. From a script or another app, set the limit yourself with `--gas-limit 2000000`. Hedera charges only the gas used, but the payer must hold the limit's worth when sending. |
| "This diamond does not sell privately yet" on the Private page | No facet serves `buyFor`: the diamond was deployed before private purchases. Its admin runs `yarn foundry:deploy --file DeployStealthBuy.s.sol --network hedera_testnet`. |
| "No diamond on Hedera Mainnet" in the app | The wallet is on a network this project has no diamond on. Switch to Hedera Testnet. |

## Limits

- Not audited. Lattice is pre-1.0 and unaudited too. Do not put real value behind this without a review.
- There is no local-chain mode. HTS and the Chainlink feed exist only on Hedera, so contract tests run against mocks and the app runs against testnet.
- The deploy script finishes the setup only when the deploying account is the diamond's admin. A recipe can name another admin, such as a Safe, in place of `{"$ref": "deployer"}`. The diamond still deploys, but registering the Chainlink feed needs `DEFAULT_ADMIN_ROLE`, so the script skips it and prints the `registerFeed` call for that admin to send. `launchSale` must come from that admin too: it needs `DEFAULT_ADMIN_ROLE` and the `HTS_MANAGER_ROLE` that `HTSAdapterInit` grants.
- Lattice Studio's Hedera support is a preview build of its `feat/hedera` branch, and its catalog is provisional: built from Lattice commit `6c8db45`, not from a tagged release. `TokenSale` and `StealthBuy` are never on its sheet (see "Customize in Lattice Studio").
- Private purchases hide the recipient and nothing else. Read the privacy model under "Private purchases" before relying on them.
- The Inbox reads every announcement the diamond has made since it was created, one week of history per mirror node search, so a scan takes longer as the diamond ages.
- The app's upgrade card plans Add and Replace only. A function the outgoing facet serves that the new facet does not export stays routed to the old facet, and the preview lists it under "Still served by the outgoing facet". Removing them is a separate Remove cut, for example from Debug Contracts or with `cast`.
- The package manager is Yarn.

## Links

- [Lattice](https://github.com/dadadave80/lattice), the diamond module library, and its [Hedera guide](https://github.com/dadadave80/lattice/blob/feat/hedera-system-contract-modules/docs/guides/hedera.md)
- [Lattice Studio](https://github.com/dadadave80/lattice-studio), its Hedera work on [`feat/hedera`](https://github.com/dadadave80/lattice-studio/tree/feat/hedera), and [its Hedera build](https://lattice-studio-git-feat-hedera-david-dadas-projects.vercel.app/)
- [Scaffold-HBAR docs](https://docs.hedera.com/solutions/tools/scaffold-hbar/index) and [create-scaffold-hbar](https://github.com/hedera-dev/create-scaffold-hbar)
- [Chainlink price feeds on Hedera](https://docs.chain.link/data-feeds/price-feeds/addresses?network=hedera)
- [ERC-5564](https://eips.ethereum.org/EIPS/eip-5564) stealth addresses, the [ERC-6538](https://eips.ethereum.org/EIPS/eip-6538) registry, and Hedera's [HIP-583](https://hips.hedera.com/hip/hip-583) and [HIP-904](https://hips.hedera.com/hip/hip-904)
- [HashScan](https://hashscan.io/testnet)

MIT licensed. See [LICENCE](LICENCE).
