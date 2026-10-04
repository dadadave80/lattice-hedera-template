// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IDiamondLoupe } from "@diamond/interfaces/IDiamondLoupe.sol";
import { FacetCut } from "@diamond/libraries/DiamondLib.sol";
import { BaseDeploy } from "@lattice-script/base/BaseDeploy.s.sol";
import { DEFAULT_ADMIN_ROLE } from "@lattice/access/libraries/AccessControlLib.sol";
import { IAccessControl } from "@lattice/interfaces/access/IAccessControl.sol";
import { IChainlinkAdapter } from "@lattice/interfaces/oracles/IChainlinkAdapter.sol";
import { IEmergencyStop } from "@lattice/interfaces/security/IEmergencyStop.sol";
import { PythAdapterInit } from "@lattice/oracles/pyth/PythAdapterInit.sol";
import { DiamondIntrospectionInit } from "@lattice/utils/DiamondIntrospectionInit.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";
import { SaucerSwapPool } from "../contracts/SaucerSwapPool.sol";
import { SaucerSwapPoolInit } from "../contracts/SaucerSwapPoolInit.sol";
import { StealthBuy } from "../contracts/StealthBuy.sol";
import { TokenSale } from "../contracts/TokenSale.sol";
import { TokenSaleInit } from "../contracts/TokenSaleInit.sol";

// A facet is deployed by name from its compiled artifact, and Foundry compiles only what something imports.
// Importing the wiring file here makes every wired facet part of any build that includes this script.
import "../contracts/LatticeFacets.sol";

/// @title SaucerSwapV1
/// @notice SaucerSwap V1's addresses on each Hedera network (https://docs.saucerswap.finance/developers/contracts),
///         for `SaucerSwapPoolInit`. `DeployDiamond` and `DeploySaucerSwapPool` both read them here.
/// @dev The router is SaucerSwapV1RouterV3, the current one; its older versions and the old WHBAR are deprecated.
///      `whbar` is the WHBAR HTS token the router's `whbar()` returns, which is what `getPair` takes, not the
///      wrapping contract its `WHBAR()` returns.
library SaucerSwapV1 {
    address internal constant ROUTER_TESTNET = 0x0000000000000000000000000000000000004b40; // 0.0.19264
    address internal constant FACTORY_TESTNET = 0x00000000000000000000000000000000000026E7; // 0.0.9959
    address internal constant WHBAR_TESTNET = 0x0000000000000000000000000000000000003aD2; // 0.0.15058
    address internal constant ROUTER_MAINNET = 0x00000000000000000000000000000000002E7A5D; // 0.0.3045981
    address internal constant FACTORY_MAINNET = 0x0000000000000000000000000000000000103780; // 0.0.1062784
    address internal constant WHBAR_MAINNET = 0x0000000000000000000000000000000000163B5a; // 0.0.1456986

    /// @notice Mainnet's addresses on chain 295, testnet's on any other chain, as `DeployDiamond` picks the feed.
    function addresses(uint256 chainId) internal pure returns (address router, address factory, address whbar) {
        if (chainId == 295) return (ROUTER_MAINNET, FACTORY_MAINNET, WHBAR_MAINNET);
        return (ROUTER_TESTNET, FACTORY_TESTNET, WHBAR_TESTNET);
    }
}

/// @title DeployDiamond
/// @notice Builds this project's diamond in two layers and deploys it in one transaction.
///         - The Lattice base comes from `diamond.recipe.json`, a file in Lattice Studio's recipe format, and
///           includes `HTSAdapter`, `ERC6538Registry` and `ERC5564Announcer`. Change the base by editing that
///           file (or exporting over it from Studio), never by editing cuts here.
///         - The Hedera layer is fixed below: this project's `TokenSale`, `StealthBuy` and `SaucerSwapPool` facets.
///           They stay out of the recipe because they are not Lattice's facets, so Studio's catalog does not carry
///           them. `SaucerSwapPool` gets the SaucerSwap V1 addresses of the chain it is deployed to.
/// @dev `build` and `assemble` take the recipe as a string and never broadcast, so tests call them directly.
contract DeployDiamond is BaseDeploy {
    string internal constant RECIPE = "diamond.recipe.json";

    /// @dev The Studio catalog the pinned Lattice sources match. A recipe from another catalog still deploys;
    ///      it only earns a warning.
    string internal constant CATALOG_TAG = "dev-6c8db45";

    /// @dev The key the sale reads its HBAR/USD rate under, on whichever oracle facet the recipe cuts.
    bytes32 internal constant HBAR_USD = "HBAR/USD";

    /// @dev Chainlink HBAR/USD price feeds (https://docs.chain.link/data-feeds/price-feeds/addresses?network=hedera).
    address internal constant HBAR_USD_FEED_TESTNET = 0x59bC155EB6c6C415fE43255aF66EcF0523c92B4a;
    address internal constant HBAR_USD_FEED_MAINNET = 0xAF685FB45C12b92b5054ccb9313e135525F9b5d5;

    bytes4 internal constant DIAMOND_CUT = 0x1f931c1c;

    /// @dev How many facets and initializers the Hedera layer appends to the recipe's. A facet added in `build()`
    ///      without raising `HEDERA_FACETS` stops it with an array out-of-bounds panic (0x32).
    uint256 internal constant HEDERA_FACETS = 3;
    uint256 internal constant HEDERA_INITS = 3;

    /// @notice Deploys the diamond from `diamond.recipe.json` on Hedera testnet or mainnet and writes
    ///         `deployments/diamond/<chainId>.json`. When the deployer is the recipe's admin, it also registers the
    ///         Chainlink HBAR/USD feed and makes the deployer an emergency-stop guardian, each only if the recipe
    ///         has the facet (`ChainlinkAdapter`, `EmergencyStop`).
    /// @dev The token is not created here: `forge script` cannot simulate HTS, so `launchSale` is a separate
    ///      transaction. Writes no record on a dry run.
    /// @return diamond The new diamond's address.
    function run() external returns (address diamond) {
        require(
            block.chainid == 295 || block.chainid == 296,
            "DeployDiamond: this diamond needs Hedera (HTS and a Chainlink feed). Deploy with --network hedera_testnet"
        );
        string memory json = vm.readFile(RECIPE);

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        (string[] memory names, FacetCut[] memory cuts, address[] memory inits, bytes[] memory calls) =
            build(json, deployer);
        diamond = _assembleMulti(cuts, inits, calls);
        _registerHbarUsdFeed(diamond, deployer);
        _addGuardian(diamond, deployer);
        vm.stopBroadcast();

        string[] memory notes = warnings(json, cuts);
        for (uint256 i; i < notes.length; ++i) {
            console.log(string.concat("Warning: ", notes[i]));
        }
        // A run without --broadcast deploys nothing, so there is no diamond to record.
        if (vm.isContext(VmSafe.ForgeContext.ScriptDryRun)) {
            console.log("Dry run: nothing deployed, record not written");
            return diamond;
        }
        _writeRecord(diamond, names, cuts);
        console.log("Diamond deployed at", diamond);
    }

    /// @notice Deploys the diamond described by `json` plus the Hedera layer, with `admin` standing for the
    ///         recipe's `{"$ref": "deployer"}`.
    /// @param json The recipe, as text.
    /// @param admin The address that stands for `{"$ref": "deployer"}`.
    /// @return diamond The new diamond's address.
    function assemble(string memory json, address admin) public returns (address diamond) {
        (, FacetCut[] memory cuts, address[] memory inits, bytes[] memory calls) = build(json, admin);
        diamond = _assembleMulti(cuts, inits, calls);
    }

    /// @notice The facet cuts and initializer calls for the recipe's base plus the Hedera layer.
    /// @dev Deploys the facets and initializers it names. Reverts with a message naming the fix when the recipe
    ///      lacks `HTSAdapter` or its init, names a facet that is not compiled in, or gives a selector two owners.
    /// @param json The recipe, as text.
    /// @param admin The address that stands for `{"$ref": "deployer"}`.
    /// @return names The facet name behind each cut, in cut order.
    /// @return cuts One `Add` cut per facet: the recipe's, then `TokenSale` and `StealthBuy`.
    /// @return inits The initializers, in run order: the recipe's steps, then `TokenSaleInit` and
    ///         `DiamondIntrospectionInit`.
    /// @return calls The calldata for each initializer, matched by index.
    function build(string memory json, address admin)
        public
        returns (string[] memory names, FacetCut[] memory cuts, address[] memory inits, bytes[] memory calls)
    {
        string[] memory base = _facetNames(json);
        uint256 steps = _stepCount(json);
        _requireHtsAdapter(json, base, steps);

        names = new string[](base.length + HEDERA_FACETS);
        cuts = new FacetCut[](base.length + HEDERA_FACETS);
        for (uint256 i; i < base.length; ++i) {
            _requireWired(base[i]);
            names[i] = base[i];
            cuts[i] = _cutExcept(_facet(base[i]), _excludedFor(json, base[i]));
        }
        names[base.length] = "TokenSale";
        cuts[base.length] = _cut(address(new TokenSale()));
        names[base.length + 1] = "StealthBuy";
        cuts[base.length + 1] = _cut(address(new StealthBuy()));
        names[base.length + 2] = "SaucerSwapPool";
        cuts[base.length + 2] = _cut(address(new SaucerSwapPool()));
        _requireProjectFacets(names, base.length);
        _requireDistinctSelectors(names, cuts);

        inits = new address[](steps + HEDERA_INITS);
        calls = new bytes[](steps + HEDERA_INITS);
        for (uint256 i; i < steps; ++i) {
            (inits[i], calls[i]) = _initStep(json, i, admin);
        }
        inits[steps] = address(new TokenSaleInit());
        calls[steps] = abi.encodeCall(TokenSaleInit.init, (HBAR_USD));
        (address router, address factory, address whbar) = SaucerSwapV1.addresses(block.chainid);
        inits[steps + 1] = address(new SaucerSwapPoolInit());
        calls[steps + 1] = abi.encodeCall(SaucerSwapPoolInit.init, (router, factory, whbar));
        inits[steps + 2] = address(new DiamondIntrospectionInit());
        calls[steps + 2] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    /// @notice Problems that do not stop a deploy but that the developer should hear about.
    /// @param json The recipe, as text.
    /// @param cuts The cuts `build` returned.
    /// @return notes One sentence per problem: a recipe pinned to another catalog, or no facet serving
    ///         `diamondCut`.
    function warnings(string memory json, FacetCut[] memory cuts) public view returns (string[] memory notes) {
        notes = new string[](2);
        uint256 n;
        if (vm.keyExistsJson(json, ".catalog.tag")) {
            string memory tag = vm.parseJsonString(json, ".catalog.tag");
            if (!_eq(tag, CATALOG_TAG)) {
                notes[n++] = string.concat(
                    "the recipe is pinned to catalog ", tag, " but this template's Lattice matches ", CATALOG_TAG
                );
            }
        }
        if (!_serves(cuts, DIAMOND_CUT)) {
            notes[n++] = "no facet in the recipe serves diamondCut, so this diamond cannot be upgraded";
        }
        assembly ("memory-safe") {
            mstore(notes, n)
        }
    }

    // ── recipe reading ──────────────────────────────────────────────────────────────────────────────

    function _facetNames(string memory json) internal pure returns (string[] memory) {
        try vm.parseJsonStringArray(json, ".facets") returns (string[] memory names) {
            return names;
        } catch {
            revert("Recipe: diamond.recipe.json must be valid JSON with a 'facets' list of facet names");
        }
    }

    /// @dev `exclude`, plus every contested selector that `owners` gives to a different facet.
    function _excludedFor(string memory json, string memory facet) internal view returns (bytes4[] memory out) {
        string[] memory excluded =
            vm.keyExistsJson(json, ".exclude") ? vm.parseJsonStringArray(json, ".exclude") : new string[](0);
        string[] memory contested =
            vm.keyExistsJson(json, ".owners") ? vm.parseJsonKeys(json, ".owners") : new string[](0);
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
        while (vm.keyExistsJson(json, string.concat(".init.steps[", vm.toString(n), "]"))) {
            ++n;
        }
    }

    function _initStep(string memory json, uint256 i, address deployer)
        internal
        returns (address init, bytes memory data)
    {
        string memory step = string.concat(".init.steps[", vm.toString(i), "]");
        string memory spec = vm.parseJsonString(json, string.concat(step, ".spec"));
        _requireWired(spec);
        string memory args = string.concat(step, ".args");
        string[] memory keys = vm.parseJsonKeys(json, args);
        init = deployCode(string.concat(spec, ".sol:", spec));

        // Generic: any init that takes no argument, and any init whose only argument is `admin`.
        if (keys.length == 0) return (init, abi.encodeWithSignature("init()"));
        if (keys.length == 1 && _eq(keys[0], "admin")) {
            return
                (init, abi.encodeWithSignature("init(address)", _addr(json, string.concat(args, ".admin"), deployer)));
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
        revert(
            string.concat(
                "Recipe: ", spec, " takes arguments this template cannot encode yet; add an encoder in _initStep"
            )
        );
    }

    /// @dev `TokenSale.launchSale` creates the token through `HTSAdapterLib`, which needs `HTS_MANAGER_ROLE`, and
    ///      `HTSAdapterInit` is what grants it.
    function _requireHtsAdapter(string memory json, string[] memory facets, uint256 steps) internal pure {
        bool cut;
        for (uint256 i; i < facets.length; ++i) {
            if (_eq(facets[i], "HTSAdapter")) cut = true;
        }
        bool initialized;
        for (uint256 i; i < steps; ++i) {
            string memory spec = vm.parseJsonString(json, string.concat(".init.steps[", vm.toString(i), "].spec"));
            if (_eq(spec, "HTSAdapterInit")) initialized = true;
        }
        require(
            cut && initialized,
            "Recipe: TokenSale creates its token through HTSAdapter, with the roles HTSAdapterInit grants; add HTSAdapter and its HTSAdapterInit step in Lattice Studio"
        );
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

    /// @dev A facet can only be deployed by name if `contracts/LatticeFacets.sol` compiled it into this project.
    function _requireWired(string memory name) internal view {
        require(
            vm.exists(string.concat("out/", name, ".sol/", name, ".json")),
            string.concat(
                "Recipe: ",
                name,
                " is in the recipe but not compiled into this project; add its import to contracts/LatticeFacets.sol"
            )
        );
    }

    /// @dev The Hedera layer is wired by hand in `build()`, so it is checked here, before anything is broadcast.
    ///      `scripts-js/generateTsAbis.js` reads each recorded facet's ABI from `out/<name>.sol/<name>.json`, which
    ///      exists only when the facet's file is named after its contract.
    function _requireProjectFacets(string[] memory names, uint256 first) internal view {
        for (uint256 i = first; i < names.length; ++i) {
            require(
                bytes(names[i]).length != 0,
                "DeployDiamond: HEDERA_FACETS is higher than the number of facets build() appends after the recipe's"
            );
            require(
                vm.exists(string.concat("out/", names[i], ".sol/", names[i], ".json")),
                string.concat(
                    "DeployDiamond: ",
                    names[i],
                    " has no artifact at out/",
                    names[i],
                    ".sol/",
                    names[i],
                    ".json; put the contract in contracts/",
                    names[i],
                    ".sol, a file named after it"
                )
            );
        }
    }

    /// @dev A diamond routes each selector to exactly one facet. Checking here names both facets, where the
    ///      diamond's own error would name neither.
    function _requireDistinctSelectors(string[] memory names, FacetCut[] memory cuts) internal pure {
        for (uint256 a; a < cuts.length; ++a) {
            for (uint256 b = a + 1; b < cuts.length; ++b) {
                bytes4[] memory left = cuts[a].functionSelectors;
                bytes4[] memory right = cuts[b].functionSelectors;
                for (uint256 i; i < left.length; ++i) {
                    for (uint256 j; j < right.length; ++j) {
                        if (left[i] == right[j]) {
                            revert(
                                string.concat(
                                    "Recipe: selector ",
                                    vm.toString(abi.encodePacked(left[i])),
                                    " is exported by both ",
                                    names[a],
                                    " and ",
                                    names[b],
                                    "; give it one owner in Lattice Studio (owners) or drop it (exclude)"
                                )
                            );
                        }
                    }
                }
            }
        }
    }

    function _serves(FacetCut[] memory cuts, bytes4 selector) internal pure returns (bool) {
        for (uint256 i; i < cuts.length; ++i) {
            bytes4[] memory selectors = cuts[i].functionSelectors;
            for (uint256 j; j < selectors.length; ++j) {
                if (selectors[j] == selector) return true;
            }
        }
        return false;
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    // ── after the diamond exists ────────────────────────────────────────────────────────────────────

    /// @dev Chainlink only. Another oracle facet registers its feed with its own arguments (see the README).
    ///      `registerFeed` needs `DEFAULT_ADMIN_ROLE`, which `caller` lacks when the recipe names another admin.
    function _registerHbarUsdFeed(address diamond, address caller) internal {
        if (IDiamondLoupe(diamond).facetAddress(IChainlinkAdapter.registerFeed.selector) == address(0)) {
            console.log(
                "No ChainlinkAdapter in this recipe: register an HBAR/USD feed under the key 'HBAR/USD' yourself."
            );
            return;
        }
        bool mainnet = block.chainid == 295;
        address feed = mainnet ? HBAR_USD_FEED_MAINNET : HBAR_USD_FEED_TESTNET;
        // Testnet feeds are not kept on a production heartbeat, so the testnet default is deliberately loose.
        uint256 maxStaleness = vm.envOr("HBAR_USD_MAX_STALENESS", mainnet ? uint256(25 hours) : uint256(365 days));
        if (
            IDiamondLoupe(diamond).facetAddress(IAccessControl.hasRole.selector) != address(0)
                && !IAccessControl(diamond).hasRole(DEFAULT_ADMIN_ROLE, caller)
        ) {
            console.log(
                string.concat(
                    "The recipe makes another account admin, so the feed is not registered. From that account, call registerFeed(\"HBAR/USD\", ",
                    vm.toString(feed),
                    ", ",
                    vm.toString(maxStaleness),
                    ") on the diamond."
                )
            );
            return;
        }
        IChainlinkAdapter(diamond).registerFeed(HBAR_USD, feed, uint48(maxStaleness));
    }

    /// @dev Nobody can call `emergencyStop` until an admin adds a guardian, so the deploy makes `caller` one.
    function _addGuardian(address diamond, address caller) internal {
        if (IDiamondLoupe(diamond).facetAddress(IEmergencyStop.addGuardian.selector) == address(0)) {
            console.log("No EmergencyStop in this recipe: nothing can pause the sale.");
            return;
        }
        if (
            IDiamondLoupe(diamond).facetAddress(IAccessControl.hasRole.selector) != address(0)
                && !IAccessControl(diamond).hasRole(DEFAULT_ADMIN_ROLE, caller)
        ) {
            console.log(
                "The recipe makes another account admin, so no guardian is set. From that account, call addGuardian(<address>) on the diamond."
            );
            return;
        }
        IEmergencyStop(diamond).addGuardian(caller);
    }

    /// @dev What `scripts-js/generateTsAbis.js` needs to give the frontend one `Diamond` contract: the address,
    ///      the facet names, and the selectors each facet serves after `exclude` and `owners` were applied.
    function _writeRecord(address diamond, string[] memory names, FacetCut[] memory cuts) internal {
        string memory selectors;
        for (uint256 i; i < names.length; ++i) {
            bytes4[] memory cut = cuts[i].functionSelectors;
            string[] memory hexes = new string[](cut.length);
            for (uint256 j; j < cut.length; ++j) {
                hexes[j] = vm.toString(abi.encodePacked(cut[j]));
            }
            selectors = vm.serializeString("selectors", names[i], hexes);
        }
        vm.serializeAddress("record", "address", diamond);
        vm.serializeUint("record", "deployedOnBlock", block.number);
        vm.serializeString("record", "facets", names);
        string memory record = vm.serializeString("record", "selectors", selectors);

        vm.createDir("deployments/diamond", true);
        vm.writeJson(record, string.concat("deployments/diamond/", vm.toString(block.chainid), ".json"));
    }
}
