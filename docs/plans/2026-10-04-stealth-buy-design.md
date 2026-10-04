# Stealth Buy: design

**Decided with David on 4 October 2026, about 17:20 UTC.** The showcase moves past "a token sale that can be upgraded": a buyer pays HBAR at the Chainlink price and the tokens land on a one-time ERC-5564 stealth address that nothing on chain ties to the recipient. Hedera makes this work with no setup: HBAR sent to an unknown address lazy-creates the account (HIP-583) with unlimited automatic token associations (HIP-904), so it can receive the HTS token in the same transaction. In parallel, Lattice Studio approach A, trimmed: "Open in Studio" from the Diamond page and catalog-driven checks. Paste-back and in-app upgrade from Studio are deferred.

**Kill time 19:30 UTC:** a delivery to a fresh stealth address and a sweep from it, both broadcast on testnet. If not, fall back to option 3 (dual-oracle guard facet). The current template stays green throughout: everything merges only when it works.

## Proven live before building (4 October, testnet)

| Step | Transaction | Result |
| --- | --- | --- |
| HBAR from a contract to a fresh address (Multicall3 `aggregate3Value`) | `0xc3a8acf41ee5b43ed3078fef78a4fe2eb54b2b6a394a6b400ca55043bda0e3ff` | Hollow account `0.0.10859944`, `max_automatic_token_associations = -1`, 645,737 gas |
| HTS transfer from a diamond (`HTSAdapter.transferToken`) to that hollow account | `0x698c8ac1d2dadaa0cfa6cb4d2cc0100e3aa71179c6d4b8dbf535e7eb681f42b4` | Delivered, auto-associated, 756,050 gas |
| The hollow account's first transaction: ERC-20 `transfer` of the token, signed with its own key | `0x8ecf0d739c3011400950516a21de393d0221a61571a1f378208117431154122c` | Swept, account completed (ECDSA key set), 36,880 gas; 0.47 of 0.5 HBAR left |

Hedera charged gas used, not a share of the limit (the reference diamond's purchase was charged gas used × 84 tinybars).

## Contracts (track C)

`contracts/interfaces/IStealthBuy.sol`, `contracts/StealthBuy.sol`, logic in a library or in `TokenSaleLib` (make `_tokensFor` and `_transferFromTreasury` `internal` if needed; library internals are inlined, so the live `TokenSale` bytecode does not depend on it).

```solidity
/// msg.value = payment + stipend, both in tinybars inside the EVM.
function buyFor(address stealthAddress, bytes calldata ephemeralPubKey, bytes1 viewTag, int64 minTokensOut, uint256 stipend)
    external payable returns (int64 tokens);
event StealthDelivery(address indexed stealthAddress, int64 tokens, uint256 paidTinybars, uint256 stipendTinybars);
error StealthBuyZeroAddress();
error StealthBuyStipendTooHigh(uint256 stipend, uint256 value);
error StealthBuyStipendFailed(address stealthAddress);
```

Order inside `buyFor`: checks (sale launched, emergency stop, nonzero address, stipend below value) → price with the sale's `_tokensFor` on `msg.value - stipend` and the slippage check → update the sale's sold/raised totals → send the stipend with `call{value: stipend}` (lazy-creates the account) → transfer the tokens from the diamond's treasury through `0x167` with the sale's response-code handling → `ERC5564AnnouncerLib.announce(1, stealthAddress, ephemeralPubKey, metadata)` with `metadata = viewTag ‖ 0xa9059cbb ‖ token (20 bytes) ‖ amount (uint256)`, the ERC-5564 token layout → `StealthDelivery`. `exportSelectors()` per ERC-8153.

Composition: the recipe gains Lattice's `ERC6538Registry` and `ERC5564Announcer` (both in Studio's catalog `dev-6c8db45`, inits `init()`), written with Studio's core so the file is what Studio exports. `DeployDiamond.s.sol` appends `StealthBuy` next to `TokenSale` (`HEDERA_FACETS` 1 → 2) and `_initStep` gains the zero-argument branch. A standalone script deploys the three facets for the live reference diamond, which receives them as one `diamondCut` Add with their inits through `MultiInit`.

Tests: `test/StealthBuy.t.sol` on `SaleTestBase` with the mocked HTS and feed: delivery to a new address (stipend and tokens), the exact `Announcement` (topics and metadata bytes), price equals `quote(payment)`, slippage, stopped, not launched, stipend too high, zero address, sold/raised totals, `exportSelectors` equals the ABI. Recipe and deploy tests for the new facets.

## Frontend (track F)

`/private` page, linked from the header.

- **Receive privately:** sign one fixed message; keys derive from the signature (spending and viewing private keys = keccak256 of the signature with distinct domain tags, reduced into the secp256k1 order); the stealth meta-address (`spendingPub ‖ viewingPub`, compressed, 66 bytes) is registered with `registerKeys(1, metaAddress)`.
- **Buy for someone privately:** recipient address → `stealthMetaAddressOf(recipient, 1)` → ERC-5564 scheme 1 (secp256k1 with view tags): random ephemeral key, shared secret `= ephemeralPriv · viewingPub`, `h = keccak256(shared)`, view tag `= h[0]`, stealth public key `= spendingPub + h·G`, stealth address from it. Payment in HBAR, stipend default 0.5 HBAR, shows "Sends X HBAR (payment + stipend)" and the quote; calls `buyFor`.
- **Inbox:** reads `Announcement` logs of the diamond from the mirror node (`/api/v1/contracts/{diamond}/results/logs`, topic0 = the event signature), filters by view tag, recomputes the stealth address, derives the stealth private key `= spendingPriv + h (mod n)`, shows each address's token and HBAR balance, and **Sweep** sends the token to an address the user enters, signed locally with the stealth key through Hashio. A warning says that sweeping into the wallet that registered re-links the two.
- `utils/stealth/` holds the math with Vitest tests: generate → check → derive key → address round trip, view tag filtering, metadata parsing, and a published ERC-5564 vector if one is available.

## Studio approach A, trimmed (track A)

On the Diamond page: an "Open in Lattice Studio" button builds the live diamond's recipe from its loupe by matching each facet's selectors against Studio's public catalog (CORS `*`), names the facets that are this template's own (`TokenSale`, `TokenSaleV2`, `StealthBuy`), and opens the share link in Studio's Hedera build; a catalog panel shows, for each recognized facet, its summary, storage namespace and whether its catalog release is on Hedera testnet. The share-link encoder is the same as `scripts-js/studioLink.js`, cross-checked in tests.

## Privacy model (README)

Unlinkable: the recipient. Public: the payer, the amount, the time, and that a stealth delivery happened. The anonymity set is everyone who registered a meta-address. Sweeping to the registering wallet re-links. No relayer is needed because the stealth account pays its own gas from the stipend.
