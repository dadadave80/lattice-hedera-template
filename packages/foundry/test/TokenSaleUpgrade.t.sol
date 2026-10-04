// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IDiamondCut } from "@diamond/interfaces/IDiamondCut.sol";
import { IDiamondLoupe } from "@diamond/interfaces/IDiamondLoupe.sol";
import { FacetCut } from "@diamond/libraries/DiamondLib.sol";
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
}
