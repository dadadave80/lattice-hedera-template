// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IDiamondCut } from "@diamond/interfaces/IDiamondCut.sol";
import { IDiamondLoupe } from "@diamond/interfaces/IDiamondLoupe.sol";
import { FacetCut, FacetCutAction } from "@diamond/libraries/DiamondLib.sol";
import { IAccessControl } from "@lattice/interfaces/access/IAccessControl.sol";
import { IHRC719 } from "@lattice/interfaces/external/hedera/IHRC719.sol";
import { TokenSaleV2 } from "../contracts/TokenSaleV2.sol";
import { ITokenSale } from "../contracts/interfaces/ITokenSale.sol";
import { SaleTestBase } from "./SaleTestBase.sol";

/// @notice The README's upgrade walkthrough as a test: cut TokenSaleV2 into a diamond that is already selling.
contract TokenSaleUpgradeTest is SaleTestBase {
    address internal token;
    TokenSaleV2 internal v2;

    function setUp() public override {
        super.setUp();
        token = _launch();
        vm.startPrank(buyer);
        IHRC719(token).associate();
        sale.buy{ value: 10 * ONE_HBAR }(0);
        vm.stopPrank();
        v2 = new TokenSaleV2();
    }

    function test_cut_keepsTheSaleAndAddsTheBonus() public {
        FacetCut[] memory cuts = _cutsFor(address(v2));

        vm.prank(admin);
        IDiamondCut(diamond).diamondCut(cuts, address(0), "");

        (address saleToken,, uint256 priceUsd,, int64 sold, uint256 raised) = sale.saleInfo();
        assertEq(saleToken, token, "same token");
        assertEq(priceUsd, PRICE_USD, "same price");
        assertEq(sold, 40 * ONE_TOKEN, "same total sold");
        assertEq(raised, 10 * ONE_HBAR, "same total raised");

        assertEq(IDiamondLoupe(diamond).facetAddress(ITokenSale.buy.selector), address(v2), "buy replaced");
        assertEq(TokenSaleV2(diamond).bonusBps(), 500, "bonusBps added");
        assertEq(sale.quote(ONE_HBAR), 4.2e8, "4 tokens plus 5%");

        vm.prank(buyer);
        assertEq(sale.buy{ value: ONE_HBAR }(0), 4.2e8);
        assertEq(hts.balanceOf(token, buyer), 44.2e8);
    }

    function test_cut_revertsForAnyoneButTheAdmin() public {
        FacetCut[] memory cuts = _cutsFor(address(v2));

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, buyer, bytes32(0))
        );
        vm.prank(buyer);
        IDiamondCut(diamond).diamondCut(cuts, address(0), "");
    }

    function test_exportSelectors_listsTheSaleSelectorsThenTheNewOne() public view {
        bytes memory exported = v2.exportSelectors();
        assertEq(exported.length, 7 * 4);
        assertEq(_selectorAt(exported, 0), ITokenSale.buy.selector);
        assertEq(_selectorAt(exported, 6), TokenSaleV2.bonusBps.selector);
    }

    /// @dev The same rule the app's Diamond page applies: a selector the diamond already serves is replaced,
    ///      a new one is added.
    function _cutsFor(address facet) internal view returns (FacetCut[] memory cuts) {
        bytes memory exported = TokenSaleV2(facet).exportSelectors();
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
}
