// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IAccessControl } from "@lattice/interfaces/access/IAccessControl.sol";
import { IHTSAdapter } from "@lattice/interfaces/tokens/IHTSAdapter.sol";
import { TokenSale } from "../contracts/TokenSale.sol";
import { ITokenSale } from "../contracts/interfaces/ITokenSale.sol";
import { TOKEN_SALE_STORAGE_SLOT } from "../contracts/libraries/TokenSaleLib.sol";
import { SaleTestBase } from "./SaleTestBase.sol";

contract TokenSaleTest is SaleTestBase {
    function test_saleInfo_startsWithTheFeedKeyAndNoToken() public view {
        (address token,,, bytes32 feedKey, int64 sold, uint256 raised) = sale.saleInfo();

        assertEq(token, address(0), "no token before launch");
        assertEq(feedKey, HBAR_USD, "TokenSaleInit stored the feed key");
        assertEq(sold, 0);
        assertEq(raised, 0);
    }

    function test_launchSale_createsATokenTheDiamondTreasuries() public {
        address token = _launch();

        assertEq(IHTSAdapter(diamond).createdTokens()[0], token, "created through HTSAdapter's storage");
        assertEq(hts.treasury(token), diamond, "diamond is the treasury");
        assertEq(hts.balanceOf(token, diamond), SUPPLY, "supply minted to the diamond");

        (address saleToken, int32 decimals, uint256 priceUsd, bytes32 feedKey, int64 sold, uint256 raised) =
            sale.saleInfo();
        assertEq(saleToken, token);
        assertEq(decimals, 8);
        assertEq(priceUsd, PRICE_USD);
        assertEq(feedKey, HBAR_USD);
        assertEq(sold, 0);
        assertEq(raised, 0);
    }

    function test_launchSale_revertsForAnyoneButTheAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, buyer, bytes32(0))
        );
        vm.prank(buyer);
        sale.launchSale{ value: CREATION_FEE }("Lattice Sale Token", "LST", "", 8, SUPPLY, PRICE_USD);
    }

    function test_launchSale_revertsASecondTime() public {
        address token = _launch();

        vm.expectRevert(abi.encodeWithSelector(ITokenSale.TokenSaleAlreadyLaunched.selector, token));
        vm.prank(admin);
        sale.launchSale{ value: CREATION_FEE }("Second Token", "SEC", "", 8, SUPPLY, PRICE_USD);
    }

    function test_launchSale_revertsOnBadInput() public {
        vm.startPrank(admin);
        vm.expectRevert(ITokenSale.TokenSaleInvalidPrice.selector);
        sale.launchSale{ value: CREATION_FEE }("Lattice Sale Token", "LST", "", 8, SUPPLY, 0);

        vm.expectRevert(abi.encodeWithSelector(ITokenSale.TokenSaleInvalidDecimals.selector, int32(19)));
        sale.launchSale{ value: CREATION_FEE }("Lattice Sale Token", "LST", "", 19, SUPPLY, PRICE_USD);
        vm.stopPrank();
    }

    function test_storageSlot_followsErc7201() public pure {
        bytes32 expected = keccak256(abi.encode(uint256(keccak256("lattice-hedera-template.storage.TokenSale")) - 1))
            & ~bytes32(uint256(0xff));
        assertEq(TOKEN_SALE_STORAGE_SLOT, expected);
    }

    function test_exportSelectors_matchesTheAbi() public {
        _assertExportsItsAbi("TokenSale", new TokenSale().exportSelectors());
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
