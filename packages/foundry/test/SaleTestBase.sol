// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IDiamondLoupe } from "@diamond/interfaces/IDiamondLoupe.sol";
import { FacetCut, FacetCutAction } from "@diamond/libraries/DiamondLib.sol";
import { MockHederaTokenService } from "@lattice-test/mocks/hedera/MockHederaTokenService.sol";
import { IERC8153 } from "@lattice/interfaces/external/ercs/IERC8153.sol";
import { IChainlinkAdapter } from "@lattice/interfaces/oracles/IChainlinkAdapter.sol";
import { HTS_SYSTEM_CONTRACT } from "@lattice/tokens/hedera/HTSAdapterLib.sol";
import { Test } from "forge-std/Test.sol";
import { TokenSale } from "../contracts/TokenSale.sol";
import { ITokenSale } from "../contracts/interfaces/ITokenSale.sol";
import { DeployDiamond } from "../script/DeployDiamond.s.sol";
import { MockAggregatorV3 } from "./mocks/MockAggregatorV3.sol";

/// @notice Builds the production diamond through the deploy script, with Lattice's HTS mock etched at 0x167 and
///         a mock Chainlink feed registered under the sale's key. Everything a test calls goes through the
///         diamond, exactly as it does on Hedera.
/// @dev Uses the default recipe frozen in `test/fixtures`, not your `diamond.recipe.json`, so these tests keep
///      passing after you customize the diamond's base.
abstract contract SaleTestBase is Test {
    bytes32 internal constant HBAR_USD = "HBAR/USD";
    uint256 internal constant ONE_HBAR = 1e8; // tinybars, the unit of msg.value inside Hedera's EVM
    int64 internal constant ONE_TOKEN = 1e8; // the sale token has 8 decimals
    int64 internal constant SUPPLY = 1_000_000 * ONE_TOKEN;
    uint256 internal constant PRICE_USD = 0.05e18; // $0.05 per token
    uint256 internal constant CREATION_FEE = 20 * ONE_HBAR;

    address internal admin = makeAddr("admin");
    address internal buyer = makeAddr("buyer");

    MockHederaTokenService internal hts = MockHederaTokenService(payable(HTS_SYSTEM_CONTRACT));
    MockAggregatorV3 internal feed;
    DeployDiamond internal deployer;
    address internal diamond;
    ITokenSale internal sale;

    function setUp() public virtual {
        vm.etch(HTS_SYSTEM_CONTRACT, address(new MockHederaTokenService()).code);

        deployer = new DeployDiamond();
        diamond = _assembleDiamond();
        sale = ITokenSale(diamond);

        feed = new MockAggregatorV3();
        feed.setAnswer(0.2e8); // 1 HBAR = $0.20
        vm.prank(admin);
        IChainlinkAdapter(diamond).registerFeed(HBAR_USD, address(feed), 1 hours);

        vm.deal(admin, 100 * ONE_HBAR);
        vm.deal(buyer, 100 * ONE_HBAR);
    }

    /// @dev The diamond every test runs against, with `admin` as its admin. Override it to test another shape.
    function _assembleDiamond() internal virtual returns (address) {
        return deployer.assemble(vm.readFile("test/fixtures/default.recipe.json"), admin);
    }

    function _launch() internal returns (address token) {
        vm.prank(admin);
        token = sale.launchSale{ value: CREATION_FEE }("Lattice Sale Token", "LST", "", 8, SUPPLY, PRICE_USD);
    }

    /// @dev Every function in `name`'s ABI except `exportSelectors()` must be exported, and nothing else.
    function _assertExportsItsAbi(string memory name, bytes memory exported) internal view {
        string memory artifact = vm.readFile(string.concat("out/", name, ".sol/", name, ".json"));
        string[] memory signatures = vm.parseJsonKeys(artifact, ".methodIdentifiers");

        assertEq(exported.length, (signatures.length - 1) * 4, "one selector per ABI function");
        for (uint256 i; i < signatures.length; ++i) {
            bytes4 selector = bytes4(keccak256(bytes(signatures[i])));
            if (selector == TokenSale.exportSelectors.selector) continue;
            assertTrue(_contains(exported, selector), string.concat(signatures[i], " is not exported"));
        }
    }

    /// @dev The same rule the app's Diamond page applies: a selector the diamond already serves is replaced,
    ///      a new one is added.
    function _cutsFor(address facet) internal view returns (FacetCut[] memory cuts) {
        bytes memory exported = IERC8153(facet).exportSelectors();
        uint256 count = exported.length / 4;
        bytes4[] memory replaced = new bytes4[](count);
        bytes4[] memory added = new bytes4[](count);
        uint256 replaces;
        uint256 adds;
        for (uint256 i; i < count; ++i) {
            bytes4 selector = _selectorAt(exported, i);
            if (IDiamondLoupe(diamond).facetAddress(selector) == address(0)) added[adds++] = selector;
            else replaced[replaces++] = selector;
        }
        assembly ("memory-safe") {
            mstore(replaced, replaces)
            mstore(added, adds)
        }
        cuts = new FacetCut[](2);
        cuts[0] = FacetCut({ facetAddress: facet, action: FacetCutAction.Replace, functionSelectors: replaced });
        cuts[1] = FacetCut({ facetAddress: facet, action: FacetCutAction.Add, functionSelectors: added });
    }

    function _selectorAt(bytes memory packed, uint256 index) internal pure returns (bytes4 selector) {
        assembly ("memory-safe") {
            selector := mload(add(add(packed, 0x20), mul(index, 4)))
        }
    }

    function _contains(bytes memory packed, bytes4 selector) internal pure returns (bool) {
        for (uint256 i; i < packed.length; i += 4) {
            bytes4 chunk;
            assembly ("memory-safe") {
                chunk := mload(add(add(packed, 0x20), i))
            }
            if (chunk == selector) return true;
        }
        return false;
    }
}
