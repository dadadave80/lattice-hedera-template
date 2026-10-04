# Lattice Studio speaks Hedera: plan

**Goal:** compose a whole Hedera diamond in Lattice Studio, `HTSAdapter` included, deploy it from Studio to Hedera testnet, and have the template's "Open in Lattice Studio" link land on that Studio.
**Approved by David on 4 October 2026, about 14:00 UTC:** full scope (S1 + S2 + L + T); the Studio `lattice/` submodule moves to `6c8db45` on `feat/hedera` only; testnet sends for the bootstrap and a scripted deploy with the key in `packages/foundry/.env`; push `feat/hedera` for a Vercel preview and link the template to it.
**Freeze:** 00:00 UTC on 5 October. Nothing new after that: merge what is green, gates, CI, submission notes. If S2 is not green by 21:00 UTC, ship S1 + L and T without the recipe switch, and say so in the README and the survey notes.

## Where the work happens

| Repo | Path | Branch | Rule |
| --- | --- | --- | --- |
| Lattice Studio | `~/Dev/lattice-studio` | `feat/hedera`, from `dev` at `9c9d9eb` | `dev` and `main` untouched. `main` deploys production on push. |
| Lattice | `~/Dev/projects/lattice` | none | Read only. Studio pins `6c8db45` (tag `hedera-template-pin-6c8db45`). |
| Template | this repo | `build`, then `main` | Same conventions as the build plan. |

Studio's house rules (its `AGENTS.md`) bind every Studio change: scoped Conventional Commits; named exports only, no `any`; no dependency changes; never hand-edit `catalog/`, `packages/tokens/dist/`, `golden/expected/` or `apps/studio/vercel.json` (regenerate them); frozen paths `packages/core/src/model/`, `apps/studio/src/contracts/`, every `package.json`, `bun.lock`, build configs; `packages/core` stays pure; network calls only under `apps/studio/src/chain/` and the listed loaders; copy rules (US spelling, sentence case, no "please", state what happened then what to do, disabled controls say why); specs and plans are never committed there; no pushes, no transactions.

Foundry: Studio's catalog and golden builds need 1.8.3 (`PATH=$HOME/.foundry/versions/foundry-rs/foundry/v1.8.3:$PATH`); Hedera `forge script` needs 1.7.1 (the machine default). Never run `foundryup --use`.

## Tracks

**S1. Hedera Testnet as a Studio deploy target** (worktree `~/Dev/lattice-studio-s1`, branch `feat/hedera-chain`). Follow `15a5652` (HSKChain 133): a `ChainSpec` for 296 (HashScan explorer, portal faucet, Hashio RPC, `gasCap: 15_000_000n` because the relay rejects more than 15M per transaction while blocks report 150M, `ensChainId` Sepolia, HBAR 18 decimals over JSON-RPC), picker, copy, `NOT_ON_ETHERSCAN`, README Status, `docs/release.md`, and the tests 15a5652 touched. The CLI's probe must not use the 150M block limit as the cap on 296. Mainnet 295 stays off. Not in scope: changing the deploy state machine's gas handling (a demo diamond is far below the cap).

**S2. Hedera catalog** (main checkout, branch `feat/hedera`). Bump `lattice/` to `6c8db45`; overlay entries for `HTSAdapter`, `HTSAdapterInit` (admin is the authority, `DEFAULT_ADMIN_ROLE`) and minimal ones for `HSSAdapter`, `HederaExchangeRateAdapter`, `HederaPrngAdapter`, `HASSignatureVerifier` and their inits; an `HTSAdapter` recipe template (mirror `overlay/recipes/ChainlinkVRF.yaml`); correct the stale citation in `overlay/inits/accounts.yaml` (`AccountSignerLib.sol#L146-L150` is `#L166-L170` at `6c8db45`); regenerate `catalog/dev-6c8db45` with Foundry 1.8.3 (it becomes default; `dev-f4a32c8` stays in the manifest); update every test, fixture and CLI pin that names `f4a32c8` or the facet counts. The fixture generator reads the gitignored `.handoff/design/prototype/prototype-data.json`: extend that local input for the five facets (60 minutes at most); never weaken `fixtures/validate.test.ts`. Scan the new catalog's creation code for CLZ (`0x1e`) outside metadata: Hedera has no CLZ. A hit in a facet the demo uses is a stop.

**L. Live proof on Hedera testnet** (after S2 is merged and scanned, and after an advisor check). Bootstrap through Arachnid's proxy only what the `HTSAdapter` recipe needs (registry, factory, its facets and inits) and confirm each lands at the catalog's predicted address. Export the recipe's Foundry script with Studio's CLI, deploy the diamond with Foundry 1.7.1, read `facets()`, and verify on Sourcify with Foundry 1.8.3 from the `6c8db45` checkout. Then David deploys one diamond from Studio's UI with his wallet. Keep every command in the scratchpad for the README.

**T. Template** (after S2's catalog tag and hash exist). `HTSAdapter` moves into `diamond.recipe.json` (Hedera layer becomes `TokenSale` only: `HEDERA_FACETS` 2 to 1, 24 to 37 selectors, the four fixture recipes, `CATALOG_TAG`, the warning test); `studioLink.js` points at the Hedera Studio URL and `STUDIO_ENCODED` is regenerated with the new branch's encoder; README "Customize in Lattice Studio" and the Limits rewritten; `warnings()` silent for the shipped recipe. Gate: 43+ Forge tests, Node and Vitest suites, `gate.sh static` and `scaffold`, CI. If T is not green by the freeze, revert it to `b83d716` and link the Studio work as a companion.

## Hosting

Vercel builds every pushed branch as a Preview, but the project's Deployment Protection puts previews behind Vercel sign-in (checked: previews answer 302 to `vercel.com/sso-api`; production answers 200). David chooses how judges reach the Hedera Studio. Every code change alters the CSP hashes in `apps/studio/vercel.json`, so the branch's last commit regenerates it with `STUDIO_VERCEL_JSON=1 bun run build`.

## Review

Each track: builder with tests, then an Opus reviewer and two Opus skeptics per Important finding, one repair round. After merging S1 into `feat/hedera`: `bun run check`, `bun test`, the browser tests of touched files, `bun run golden`, `bun run test:chain`, against the baseline recorded before any change.
