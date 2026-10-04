# Lattice Studio recipe seam: design

- **Date:** 2026-10-03
- **Status:** approved in brainstorm, spike verified, not yet implemented
- **Scope:** how the scaffold-hbar template links to Lattice Studio. The rest of the template (sale facet, UI, eligibility gate) is outside this document.
- **Deadline:** bounty submissions close Sunday 4 October 2026, 23:59 ET (Monday 03:59 UTC).

## Decision

The scaffolded project keeps the Lattice base of its diamond in one file, `packages/foundry/diamond.recipe.json`, written in Lattice Studio's `recipe.json` format. The deploy script builds the diamond from that file and adds a fixed Hedera layer.

A developer opens the file in Studio with a share link, edits it on the sheet, exports `recipe.json` over the file, and redeploys.

Studio is not changed. No Studio code, CLI or network call goes into the template.

## Context

**Template shape (for orientation).** An upgradeable HTS app on a Lattice diamond: the diamond creates and treasuries an HTS token through `HTSAdapter`, sells it at a USD price read from a Chainlink HBAR/USD feed through `ChainlinkAdapter`, and the walkthrough ends with a live `diamondCut`.

**Goal chosen.** Let a developer customize the diamond in Studio and bring the result into the scaffolded project.

**Constraints.**

- The template was not started when this was written.
- Studio v1 has no Hedera facets in its catalog and no Hedera network in its picker.
- Studio v1 creates new diamonds only. Upgrading a live diamond is its v2.
- Studio's CLI is not on npm, so a scaffolded project cannot depend on it.

**Alternatives rejected.**

- **Studio speaks Hedera** (Hedera catalog, Hedera testnet, bootstrapped shared contracts). Best experience, but an estimated 10 to 16 hours of Studio work with live-network unknowns. Deferred until after the bounty.
- **Composer page inside the template.** Rebuilds Studio without its checks.

## What was verified

Everything in this table was run on 2026-10-03. Nothing here touched a live network.

| Claim | How it was checked | Result |
| --- | --- | --- |
| Today's Studio accepts the default base | Studio's own CLI (`check`, `plan`) from `dadadave80/lattice-studio` at `9c9d9eb` | "No problems", 24 selectors, recipe hash `0x40bec7f3…2398a` |
| Studio rejects Hedera facets | Same CLI, recipe naming `HTSAdapter` | "‘HTSAdapter’ isn't in Lattice dev-f4a32c8" |
| The oracle swap is clean | Recipe with `PythAdapter` in place of `ChainlinkAdapter` | "No problems", 28 selectors |
| Both oracles collide | Recipe with both adapters | 4 `SEL-01` blockers until `owners` is set, then "No problems", 29 selectors |
| Recipes transfer one to one | Tree comparison between the catalog's Lattice commit and the Hedera branch | Outside Hedera paths, 8 files differ under `src/` and `script/base/`, none of them a wired facet |
| The reader works from a consuming project | Spike in Appendix C: Foundry 1.8.1, solc 0.8.36, `cancun`, local EVM | 4 recipes build with Studio's selector counts; a fifth, naming an unwired facet, reverts as designed |
| A plain-Node share link is valid | Link built with `zlib`, decoded by Studio's `decodeShareLink` | Same recipe hash as the Studio-encoded link |

Spike results against Studio's plan:

| Recipe | Studio's plan (base) | Spike (base + `HTSAdapter`, 13 selectors) |
| --- | --- | --- |
| Default | 7 facets, 24 selectors | 8 facets, 37 selectors |
| `PythAdapter` for `ChainlinkAdapter` | 28 selectors | 41 selectors |
| Both adapters, `owners` to `PythAdapter` | 29 selectors, `ChainlinkAdapter` 1 of 5 | 42 selectors, `ChainlinkAdapter` 1 |
| Plus `Pausable`, `Multicall`, one `exclude` | 27 selectors, `ChainlinkAdapter` 4 of 5 | 40 selectors, `ChainlinkAdapter` 4 |
| Plus `RateLimiter` (not wired) | n/a | Reverts with the "not compiled into this project" message |

## Architecture

The diamond has two layers.

- **Lattice base**, declared in `diamond.recipe.json`. This is the part a developer customizes in Studio.
- **Hedera layer**, fixed in the deploy script: `HTSAdapter` and the template's sale facet, with their inits. It stays out of the file because Studio rejects any recipe naming a facet outside its catalog.

`DeployDiamond.s.sol` extends Lattice's `BaseDeploy` and does three things.

1. Reads the recipe: `facets`, `exclude`, `owners` and `init.steps`.
2. Turns each facet name into a cut with helpers Lattice already has.
   - `_facet(name)` resolves the name through `FacetInventory` and deploys it at a deterministic address, through CreateX or, where CreateX is absent as on Hedera, through Arachnid's proxy. It reuses the facet if code already lives there.
   - `_cutExcept(facet, excluded)` reads the facet's own `exportSelectors()` and drops excluded or contested selectors.
3. Appends the Hedera layer and assembles everything in one transaction with `_assembleMulti`, which goes through `LatticeFactory`.

The round trip:

- **Project to Studio:** `yarn diamond:studio` prints an "Open in Lattice Studio" link built from the current file.
- **Studio to project:** export `recipe.json`, save it over `diamond.recipe.json`, run `yarn foundry:deploy`.

When Studio's catalog later includes the Hedera facets, `HTSAdapter` moves from the script into the file. Nothing else changes.

## Components

All paths are inside the scaffolded project.

### 1. `packages/foundry/diamond.recipe.json`

The default base, exactly as Studio exports it. Full text in Appendix A.

- Facets: `ChainlinkAdapter`, `AccessControlDiamondCut`, `EmergencyStop`, `AccessControl`, `Receive`, `DiamondLoupeFacet`, `ERC165Facet`.
- Init: `ChainlinkAdapterInit(admin = deployer)`.
- `EmergencyStop` is included because Studio warns without it (`DEP-02`: nobody can halt upgrades).

### 2. `packages/foundry/script/DeployDiamond.s.sol`

The reader plus the Hedera layer. The spike in Appendix C is the starting point. The production version adds:

- The sale facet and its init to the Hedera layer.
- A selector pre-check between the base and the Hedera layer (see Errors).
- The two warnings (see Errors).
- The deployment record for the frontend (component 6).
- `build(json, admin)` stays `public` and broadcast-free so tests call it directly, as Lattice's own recipes do.

### 3. `packages/foundry/contracts/LatticeFacets.sol`

An import list. A facet can be deployed by name only if it is compiled into the project, and this file is what compiles it.

- Default: the seven base facets, `PythAdapter`, `Pausable`, `Multicall`, `HTSAdapter`, and the inits `ChainlinkAdapterInit`, `PythAdapterInit`, `AccessControlInit`, `HTSAdapterInit`.
- Wiring another facet is one import line, plus an encoder if its init takes more than `admin`.

### 4. Init encoding (inside the script)

- **Generic path:** an init step whose only argument is `admin` is encoded as `init(address)`. That covers 30 of the 85 inits in Studio's catalog.
- **Explicit encoders:** one short branch per other init in the default set, starting with `PythAdapterInit(admin, pyth)`.
- **References:** `{"$ref": "deployer"}` resolves to the broadcaster. A literal address is used as written.

### 5. `packages/foundry/scripts-js/studioLink.js`

Run as `yarn diamond:studio`. Prints `https://lattice-studio-topaz.vercel.app/#s=1.<payload>` for the current file. Appendix B has the verified encoding.

Wire it as a workspace script (`@sh/foundry`) and a root script, following the scaffold's `yarn workspace @sh/foundry <script>` pattern so the CLI's npm rewrite keeps working.

### 6. Merged `Diamond` ABI for the frontend

The scaffold's `generateTsAbis.js` only sees top-level `CREATE` and `CREATE2` transactions. The diamond is created inside `LatticeFactory.deploy`, and facets go through Arachnid's proxy, so none of them appear.

- The deploy script writes `deployments/diamond/<chainId>.json` with the diamond's address, the facet names and the excluded selectors. A subfolder is used because the generator treats every file directly under `deployments/` as a chain.
- `generateTsAbis.js` gains one step: when that record exists, add a `Diamond` entry to `deployedContracts.ts` whose ABI is the union of those facets' ABIs, without `exportSelectors()` and without excluded selectors.
- The same step drops deploy plumbing from the output: init contracts, `MultiInit`, `LatticeFactory`, `LatticeRegistry`.

The scaffold hooks and the Debug page then show whatever was cut.

### Docs

- **README, "Customize in Lattice Studio":** the five-step path below, a sheet screenshot, and the oracle swap as the worked example.
- **`AGENTS.md`:** rules for agents. Edit the recipe to change the base. Wire a missing facet in `LatticeFacets.sol`. Never hand-edit cuts in the script.
- Both state plainly that the Hedera facets are added by the template and are not on Studio's sheet yet.

## Recipe fields

| Field | Handling |
| --- | --- |
| `facets` | Each name is deployed with `_facet(name)` and cut. Order follows the file. |
| `exclude` | Selectors dropped from every facet's cut. |
| `owners` | A contested selector is dropped from every facet except its named owner. |
| `init.kind = "steps"` | Each step is deployed and encoded, in order. |
| `init.kind = "none"` | No recipe inits. The Hedera layer's inits still run. |
| `init.kind = "bundle"` | Not supported. Reverts with a message. |
| `{"$ref": "deployer"}` | The broadcaster. |
| `{"$ref": "self"}` | Not supported. Reverts with a message. |
| `catalog` | Compared with the tag the template expects. A mismatch warns. |
| `immutable`, or no cut facet | Warns: the upgrade walkthrough needs a cut facet. |
| `$schema`, `name`, `template`, `schemaVersion` | Ignored. |

After the recipe's steps, the script always appends the Hedera layer's inits and `DiamondIntrospectionInit.initUpgradeable`.

## Developer path

1. Scaffold, then `yarn foundry:deploy --network hedera_testnet`. The base comes from the file, the Hedera layer is added, and the diamond is deployed in one transaction.
2. `yarn diamond:studio` opens the base on Studio's sheet.
3. Change it, for example replace `ChainlinkAdapter` with `PythAdapter`. Studio re-checks selectors, storage, inits and authority on every edit.
4. Export `recipe.json` and save it over `diamond.recipe.json`.
5. `yarn foundry:deploy` again. A new diamond is deployed and the app's `Diamond` ABI follows the new facet list.

The docs must say two things about step 5.

- **It deploys a new diamond.** Changing the live one is the separate `diamondCut` walkthrough.
- **An oracle swap leaves the sale facet untouched, but not the setup.** Both adapters serve `latestAnswer(bytes32)`, `getFeed(bytes32)`, `latestAnswerRaw(bytes32)` and `unregisterFeed(bytes32)`. `registerFeed` has a different signature on each, and Pyth needs `updatePriceFeeds` before a read.

## Errors

Each failure reverts before any transaction, with a message that names the fix.

| Condition | Message |
| --- | --- |
| Facet not compiled into the project | "`X` is in the recipe but not compiled into this project; add its import to contracts/LatticeFacets.sol" |
| Facet unknown to Lattice | `BaseDeploy`'s own "`X` is not in FacetInventory" |
| Init with arguments and no encoder | "`XInit` takes arguments this template cannot encode yet; add an encoder in _initStep" |
| `init.kind = "bundle"` | "init.kind must be 'steps' or 'none'; 'bundle' inits are not supported yet" |
| `{"$ref": "self"}` | "only {"$ref": "deployer"} is supported" |
| Base selector also exported by the Hedera layer | Names both facets and the selector. Not in the spike. |
| Invalid JSON or no `facets` list | Forge's parse error, prefixed with the file name |

Two conditions print a warning and continue: a recipe pinned to a different catalog tag, and a recipe with no cut facet.

## Tests

All local and offline, in `packages/foundry/test/`.

- **Default recipe.** The loupe lists the seven base facets plus the Hedera layer, 24 base selectors, each routed to its facet.
- **Oracle swap.** With `PythAdapter` in place of `ChainlinkAdapter`, `latestAnswer(bytes32)` routes to the Pyth facet.
- **`exclude` and `owners`.** An excluded selector is absent. A contested selector routes to its named owner.
- **Each failure** reverts with its message.
- **Link script** (Node test): its output inflates back to the recipe, and the Studio-encoded link in Appendix B decodes to the same recipe.

One manual check before submitting: open the printed link in the hosted app, do the oracle swap, export, and redeploy on testnet.

## Out of scope

- Any change to Studio: no Hedera catalog, no Hedera network in the picker.
- Studio code, Studio's CLI or any network call inside the template.
- An in-app composer.
- `bundle` inits and `{"$ref": "self"}`.
- A second recipe file for the Hedera layer.

## Build order

- **Build it second.** First get a hand-wired diamond deployed on testnet and the app booting. Then replace the hard-coded base with the reader. If the seam slips, the template still ships.
- **Budget:** roughly 3 to 4 hours. The spike already covers the reader's core.
- **Cut order if time runs short:**
  1. The Node test for the link script.
  2. `owners` support (revert with a message instead).
  3. Every extra wired facet except `PythAdapter`, which the worked example needs.

## Not verified: check during the build

- **The hosted app opening the link.** The link was decoded with Studio's code and catalog, not loaded in the hosted app.
- **Anything on Hedera testnet.** The spike ran in Foundry's local EVM. Unknown on testnet: gas per transaction against Hedera's per-transaction limit, HBAR cost of the first deploy, and facet reuse through Arachnid's proxy on a live relay.
- **`forge script --broadcast` against the Hedera relay.** Lattice issue #227 and relay issue #5826 report it failing on Foundry 1.8+. This design neither fixes nor worsens that.
- **HTS calls during deploy.** A `forge script` simulation cannot execute Hedera system contracts, so token creation must stay out of the deploy script. `HTSAdapterInit` itself is safe: its source only seeds roles and registers the interface, and it ran in the spike's local EVM.
- **Compiler settings and reuse.** A facet's address commits to its initcode. Developers only share facets if the template pins solc, optimizer and EVM version. Correctness does not depend on reuse.
- **`LATTICE_FACTORY`.** Without it, `BaseDeploy` deploys a registry and factory per run. Setting it in `.env.example` to a factory deployed once on testnet would remove two contract creations per developer.
- **The scaffold CLI reinstalling Lattice.** The CLI reinstalls Foundry libraries from `remappings.txt` at the tag in `foundry.lock`. Lattice needs a tag at the Hedera branch tip (`6c8db45`), and every remapping must go through `lib/lattice/` so the CLI sees one library. Confirm with `CREATE_SCAFFOLD_HBAR_TEMPLATE_DIR`.
- **`forge-std`.** The spike mapped `forge-std/` to Lattice's copy. The scaffold ships its own (v1.15.0); check the script compiles against it.
- **The sale facet's selectors.** `_cut(address)` needs the facet to implement `exportSelectors()` (ERC-8153), as Lattice facets do.

## After the bounty

Give Studio a Hedera catalog and Hedera testnet. Then the whole diamond, `HTSAdapter` included, is composed on the sheet, and the same file carries it. The template's Hedera layer shrinks to the sale facet.

---

## Appendix A: default recipe

`packages/foundry/diamond.recipe.json`, as Studio's CLI exports it. Studio's checker reports "No problems" for it.

```json
{
  "$schema": "https://lattice-studio.invalid/schema/recipe.v1.json",
  "schemaVersion": 1,
  "name": "Hedera diamond base",
  "catalog": {
    "tag": "dev-f4a32c8",
    "hash": "0x2ab42999bbfac307417b4265a7e9dbb8e004a8473bc9fc532b9bf33efa1d20c1"
  },
  "facets": [
    "ChainlinkAdapter",
    "AccessControlDiamondCut",
    "EmergencyStop",
    "AccessControl",
    "Receive",
    "DiamondLoupeFacet",
    "ERC165Facet"
  ],
  "owners": {},
  "exclude": [],
  "init": {
    "kind": "steps",
    "steps": [
      {
        "spec": "ChainlinkAdapterInit",
        "args": {
          "admin": {
            "$ref": "deployer"
          }
        }
      }
    ]
  }
}
```

Studio's cut plan for it:

```
[00] ADD DiamondLoupeFacet        4/4 selectors
[01] ADD ERC165Facet              1/1 selector
[02] ADD ChainlinkAdapter         5/5 selectors
[03] ADD AccessControlDiamondCut  1/1 selector
[04] ADD EmergencyStop            7/7 selectors
[05] ADD AccessControl            5/5 selectors
[06] ADD Receive                  1/1 selector
```

## Appendix B: share link

The format is `#s=1.<base64url(deflate-raw(recipe JSON without $schema))>`.

The default recipe, encoded by Studio's own encoder:

```
https://lattice-studio-topaz.vercel.app/#s=1.XU_JbsIwEP0VNOqRStkgJDeUtmqlnqjUC-IwtifEIrEj21AQyr933PTEad5sb7mDxIC9PUJ9hw59BzUk1wxFkVVVJUSLMk_KIi15sF5hSZUSYkNJUuCmKHMhq1au8kxUos1zajFVWSJTWEJApgRFl-e2wDyTG5iWQFfZnxVBvT8sgakpeMbQdKhNr81pq3AM5Ph9KyV531gTnO1fNA7WqOYcePM6kDuSkbevYMfHS-53JElfiNH_26c9j_QWxeL3rknXq7ljD9roEJOftFFs1wcaPV_Ntd7fAd2RAVc1aBPBk6P2L9jY2xtbnTiWH0ny7DHGRySfDnxgcODQ8E6KHC7U7Gsh0Eeb9seQiyKRSXY04Df32rJcOv0C
```

The encoding the template's script needs, verified against Studio's decoder:

```js
import { readFileSync } from "node:fs";
import { deflateRawSync } from "node:zlib";

const { $schema, ...recipe } = JSON.parse(readFileSync("diamond.recipe.json", "utf8"));
const packed = deflateRawSync(Buffer.from(JSON.stringify(recipe)), { level: 9 });
console.log("https://lattice-studio-topaz.vercel.app/#s=1." + packed.toString("base64url"));
```

## Appendix C: spike

Verified locally with Foundry 1.8.1 and solc 0.8.36. It is a starting point, not final code: no sale facet, no pre-check, no warnings, no deployment record, no tests.

Lattice was cloned to `lib/lattice` at `feat/hedera-system-contract-modules` (`6c8db45`) with its submodules.

`remappings.txt`:

```
@lattice/=lib/lattice/src/
@lattice-script/=lib/lattice/script/
@lattice-test/=lib/lattice/test/
@diamond/=lib/lattice/lib/diamond-lib/src/
forge-std/=lib/lattice/lib/forge-std/src/
```

`foundry.toml` settings that mattered: `solc = "0.8.36"`, `evm_version = "cancun"`, `ffi = true`, and `fs_permissions` with read access to the project root. The scaffold's `foundry.toml` already has the last three.

`contracts/LatticeFacets.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// The facets (and inits) this project can deploy by name. One import line wires one more.
import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ChainlinkAdapter} from "@lattice/oracles/chainlink/ChainlinkAdapter.sol";
import {ChainlinkAdapterInit} from "@lattice/oracles/chainlink/ChainlinkAdapterInit.sol";
import {PythAdapter} from "@lattice/oracles/pyth/PythAdapter.sol";
import {PythAdapterInit} from "@lattice/oracles/pyth/PythAdapterInit.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {HTSAdapter} from "@lattice/tokens/hedera/HTSAdapter.sol";
import {HTSAdapterInit} from "@lattice/tokens/hedera/HTSAdapterInit.sol";
import {Multicall} from "@lattice/utils/Multicall.sol";
```

`script/DeployDiamond.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {PythAdapterInit} from "@lattice/oracles/pyth/PythAdapterInit.sol";
import {HTSAdapterInit} from "@lattice/tokens/hedera/HTSAdapterInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";
import {console} from "forge-std/console.sol";

interface ILoupe {
    struct Facet {
        address facetAddress;
        bytes4[] functionSelectors;
    }

    function facets() external view returns (Facet[] memory);
}

/// @notice SPIKE. Builds a Lattice diamond from `diamond.recipe.json` (Lattice Studio's recipe format) plus a
///         fixed Hedera layer. Proves the recipe seam works from a consuming Foundry project.
contract DeployDiamond is BaseDeploy {
    string internal constant RECIPE = "diamond.recipe.json";

    function run() external returns (address diamond) {
        string memory json = vm.readFile(RECIPE);
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory calls) = build(json, deployer);
        diamond = _assembleMulti(cuts, inits, calls);
        vm.stopBroadcast();
        _report(diamond);
    }

    /// @notice Cuts and inits for the recipe's Lattice base plus this template's Hedera layer. No broadcast.
    function build(string memory json, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory calls)
    {
        string[] memory names = vm.parseJsonStringArray(json, ".facets");
        cuts = new FacetCut[](names.length + 1);
        for (uint256 i; i < names.length; ++i) {
            _requireWired(names[i]);
            cuts[i] = _cutExcept(_facet(names[i]), _excludedFor(json, names[i]));
        }
        // Hedera layer: fixed by the template until Studio's catalog carries it.
        cuts[names.length] = _cut(_facet("HTSAdapter"));

        uint256 steps = _stepCount(json);
        inits = new address[](steps + 2);
        calls = new bytes[](steps + 2);
        for (uint256 i; i < steps; ++i) {
            (inits[i], calls[i]) = _initStep(json, i, admin);
        }
        inits[steps] = address(new HTSAdapterInit());
        calls[steps] = abi.encodeCall(HTSAdapterInit.init, (admin));
        inits[steps + 1] = address(new DiamondIntrospectionInit());
        calls[steps + 1] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    // ── recipe reading ──────────────────────────────────────────────────────────────────────────────

    /// @dev `exclude` plus every contested selector that `owners` gives to a different facet.
    function _excludedFor(string memory json, string memory facet) internal view returns (bytes4[] memory out) {
        string[] memory excluded = vm.parseJsonStringArray(json, ".exclude");
        string[] memory contested = vm.parseJsonKeys(json, ".owners");
        out = new bytes4[](excluded.length + contested.length);
        uint256 n;
        for (uint256 i; i < excluded.length; ++i) {
            out[n++] = bytes4(vm.parseBytes(excluded[i]));
        }
        for (uint256 i; i < contested.length; ++i) {
            string memory owner = vm.parseJsonString(json, string.concat(".owners['", contested[i], "']"));
            if (!_eq(owner, facet)) out[n++] = bytes4(vm.parseBytes(contested[i]));
        }
        assembly ("memory-safe") {
            mstore(out, n)
        }
    }

    function _stepCount(string memory json) internal view returns (uint256 n) {
        string memory kind = vm.parseJsonString(json, ".init.kind");
        if (_eq(kind, "none")) return 0;
        require(_eq(kind, "steps"), "Recipe: init.kind must be 'steps' or 'none'; 'bundle' inits are not supported yet");
        while (vm.keyExistsJson(json, string.concat(".init.steps[", vm.toString(n), "]"))) ++n;
    }

    function _initStep(string memory json, uint256 i, address deployer)
        internal
        returns (address init, bytes memory data)
    {
        string memory at = string.concat(".init.steps[", vm.toString(i), "]");
        string memory spec = vm.parseJsonString(json, string.concat(at, ".spec"));
        _requireWired(spec);
        string memory args = string.concat(at, ".args");
        string[] memory keys = vm.parseJsonKeys(json, args);
        init = deployCode(string.concat(spec, ".sol:", spec));

        // Generic: any init whose only argument is `admin`.
        if (keys.length == 1 && _eq(keys[0], "admin")) {
            return (init, abi.encodeWithSignature("init(address)", _addr(json, string.concat(args, ".admin"), deployer)));
        }
        if (_eq(spec, "PythAdapterInit")) {
            return (
                init,
                abi.encodeCall(
                    PythAdapterInit.init,
                    (
                        _addr(json, string.concat(args, ".admin"), deployer),
                        _addr(json, string.concat(args, ".pyth"), deployer)
                    )
                )
            );
        }
        revert(string.concat("Recipe: ", spec, " takes arguments this template cannot encode yet; add an encoder in _initStep"));
    }

    /// @dev A literal address, or `{"$ref": "deployer"}`.
    function _addr(string memory json, string memory path, address deployer) internal view returns (address) {
        string memory ref = string.concat(path, "['$ref']");
        if (vm.keyExistsJson(json, ref)) {
            require(
                _eq(vm.parseJsonString(json, ref), "deployer"),
                "Recipe: only {\"$ref\": \"deployer\"} is supported; {\"$ref\": \"self\"} is not yet"
            );
            return deployer;
        }
        return vm.parseJsonAddress(json, path);
    }

    function _requireWired(string memory name) internal view {
        require(
            vm.exists(string.concat("out/", name, ".sol/", name, ".json")),
            string.concat(
                "Recipe: ", name, " is in the recipe but not compiled into this project; add its import to contracts/LatticeFacets.sol"
            )
        );
    }

    function _eq(string memory a, string memory b) private pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _report(address diamond) private view {
        ILoupe.Facet[] memory facets = ILoupe(diamond).facets();
        uint256 selectors;
        for (uint256 i; i < facets.length; ++i) {
            selectors += facets[i].functionSelectors.length;
            console.log("facet", facets[i].facetAddress, facets[i].functionSelectors.length);
        }
        console.log("diamond", diamond);
        console.log("facets", facets.length, "selectors", selectors);
    }
}
```

Spike output for the default recipe (`forge script script/DeployDiamond.s.sol`, local EVM):

```
Script ran successfully.
Gas used: 13479145
facet ... 5    ChainlinkAdapter
facet ... 1    AccessControlDiamondCut
facet ... 7    EmergencyStop
facet ... 5    AccessControl
facet ... 1    Receive
facet ... 4    DiamondLoupeFacet
facet ... 1    ERC165Facet
facet ... 13   HTSAdapter
facets 8 selectors 37
```

The facet names on the right are annotations: the script logs addresses and counts, in recipe order.

## Sources

- Lattice Studio: https://github.com/dadadave80/lattice-studio (README, `packages/core`, `packages/cli`, `catalog/dev-f4a32c8`)
- Lattice, Hedera branch: https://github.com/dadadave80/lattice/tree/feat/hedera-system-contract-modules (`script/base/BaseDeploy.s.sol`, `script/lib/FacetInventory.sol`, `docs/guides/hedera.md`)
- Scaffold HBAR base template: https://github.com/hedera-dev/scaffold-hbar/tree/templates/blank-template
- Bounty brief: https://hedera.com/blog/scaffold-hbar-template-bounty/
- Relay issue: https://github.com/hiero-ledger/hiero-json-rpc-relay/issues/5826
- Lattice issue: https://github.com/dadadave80/lattice/issues/227
