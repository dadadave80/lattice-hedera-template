// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IDiamondCut } from "@diamond/interfaces/IDiamondCut.sol";
import { FacetCut } from "@diamond/libraries/DiamondLib.sol";
import { IHRC719 } from "@lattice/interfaces/external/hedera/IHRC719.sol";
import { IEmergencyStop } from "@lattice/interfaces/security/IEmergencyStop.sol";
import { Vm } from "forge-std/Vm.sol";
import { StealthBuy } from "../contracts/StealthBuy.sol";
import { TokenSaleV2 } from "../contracts/TokenSaleV2.sol";
import { IStealthBuy } from "../contracts/interfaces/IStealthBuy.sol";
import { ITokenSale } from "../contracts/interfaces/ITokenSale.sol";
import { SaleTestBase } from "./SaleTestBase.sol";

/// @dev An address with code that takes no HBAR.
contract RefusesHbar { }

contract StealthBuyTest is SaleTestBase {
    /// @dev ERC-5564's event, written out so the test does not take its signature from the code under test.
    bytes32 internal constant ANNOUNCEMENT = keccak256("Announcement(uint256,address,address,bytes,bytes)");
    bytes internal constant EPHEMERAL_PUB_KEY = hex"0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
    bytes1 internal constant VIEW_TAG = 0xab;
    uint256 internal constant PAYMENT = 10 * ONE_HBAR;
    uint256 internal constant STIPEND = ONE_HBAR / 2;

    address internal stealth = makeAddr("stealth");
    IStealthBuy internal stealthBuy;

    function setUp() public override {
        super.setUp();
        stealthBuy = IStealthBuy(diamond);
    }

    function test_buyFor_paysTheStipendAndDeliversTheTokensToANewAddress() public {
        address token = _launchFor(stealth);
        assertEq(stealth.code.length, 0);
        assertEq(stealth.balance, 0);

        vm.expectEmit(diamond);
        emit IStealthBuy.StealthDelivery(stealth, 40 * ONE_TOKEN, PAYMENT, STIPEND);
        int64 tokens = _buyFor(stealth, 0, STIPEND);

        assertEq(tokens, 40 * ONE_TOKEN);
        assertEq(stealth.balance, STIPEND, "the stipend pays the stealth account's gas");
        assertEq(hts.balanceOf(token, stealth), 40 * ONE_TOKEN);
        assertEq(hts.balanceOf(token, diamond), SUPPLY - 40 * ONE_TOKEN);
        assertEq(diamond.balance, PAYMENT, "the diamond keeps the payment and passes the stipend on");
        assertEq(hts.balanceOf(token, buyer), 0, "nothing reaches the payer");
    }

    function test_buyFor_announcesTheDeliveryAsErc5564Prescribes() public {
        address token = _launchFor(stealth);

        vm.recordLogs();
        _buyFor(stealth, 0, STIPEND);
        Vm.Log memory announcement = _onlyLog(ANNOUNCEMENT);

        assertEq(announcement.topics[1], bytes32(uint256(1)), "scheme 1: secp256k1 with view tags");
        assertEq(announcement.topics[2], bytes32(uint256(uint160(stealth))), "stealth address");
        assertEq(announcement.topics[3], bytes32(uint256(uint160(buyer))), "caller: the payer");
        (bytes memory ephemeralPubKey, bytes memory metadata) = abi.decode(announcement.data, (bytes, bytes));
        assertEq(ephemeralPubKey, EPHEMERAL_PUB_KEY);
        // View tag, then ERC-5564's token layout: the ERC-20 `transfer` selector, the token, the amount.
        assertEq(metadata.length, 57);
        assertEq(
            metadata, bytes.concat(VIEW_TAG, hex"a9059cbb", bytes20(token), bytes32(uint256(uint64(40 * ONE_TOKEN))))
        );
    }

    function test_buyFor_pricesThePaymentAtTheQuote() public {
        _launchFor(stealth);
        feed.setAnswer(0.0731e8); // a rate that does not divide evenly
        uint256 payment = 123_456_789;

        int64 tokens = _buyFor(stealth, payment, 0, STIPEND);

        assertEq(tokens, sale.quote(payment));
        assertEq(tokens, 180_493_825, "1.23456789 HBAR at $0.0731, $0.05 a token, rounded down");
    }

    function test_buyFor_pricesWithTheSaleFacetTheDiamondRuns() public {
        _launchFor(stealth);
        TokenSaleV2 v2 = new TokenSaleV2();
        FacetCut[] memory cuts = _cutsFor(address(v2));
        vm.prank(admin);
        IDiamondCut(diamond).diamondCut(cuts, address(0), "");

        int64 tokens = _buyFor(stealth, 0, STIPEND);

        assertEq(tokens, sale.quote(PAYMENT), "the 5% bonus applies, as it does to buy");
        assertEq(tokens, 42 * ONE_TOKEN);
    }

    function test_buyFor_revertsBelowTheMinimum() public {
        _launchFor(stealth);

        vm.expectRevert(
            abi.encodeWithSelector(ITokenSale.TokenSaleSlippage.selector, 40 * ONE_TOKEN, 40 * ONE_TOKEN + 1)
        );
        _buyFor(stealth, 40 * ONE_TOKEN + 1, STIPEND);
    }

    function test_buyFor_revertsWhileTheEmergencyStopIsActive() public {
        _launchFor(stealth);
        vm.startPrank(admin);
        IEmergencyStop(diamond).addGuardian(admin);
        IEmergencyStop(diamond).emergencyStop("oracle incident");
        vm.stopPrank();

        vm.expectRevert(IEmergencyStop.EmergencyStopActive.selector);
        _buyFor(stealth, 0, STIPEND);
    }

    function test_buyFor_revertsBeforeLaunch() public {
        vm.expectRevert(ITokenSale.TokenSaleNotLaunched.selector);
        _buyFor(stealth, 0, STIPEND);
    }

    function test_buyFor_revertsOnTheZeroAddress() public {
        _launch();

        vm.expectRevert(IStealthBuy.StealthBuyZeroAddress.selector);
        _buyFor(address(0), 0, STIPEND);
    }

    function test_buyFor_revertsUnlessTheStipendLeavesAPayment() public {
        _launchFor(stealth);

        vm.expectRevert(abi.encodeWithSelector(IStealthBuy.StealthBuyStipendTooHigh.selector, ONE_HBAR, ONE_HBAR));
        vm.prank(buyer);
        stealthBuy.buyFor{ value: ONE_HBAR }(stealth, EPHEMERAL_PUB_KEY, VIEW_TAG, 0, ONE_HBAR);

        vm.expectRevert(abi.encodeWithSelector(IStealthBuy.StealthBuyStipendTooHigh.selector, 2 * ONE_HBAR, ONE_HBAR));
        vm.prank(buyer);
        stealthBuy.buyFor{ value: ONE_HBAR }(stealth, EPHEMERAL_PUB_KEY, VIEW_TAG, 0, 2 * ONE_HBAR);
    }

    function test_buyFor_revertsWhenTheAddressRefusesTheStipend() public {
        address refuser = address(new RefusesHbar());
        _launchFor(refuser);

        vm.expectRevert(abi.encodeWithSelector(IStealthBuy.StealthBuyStipendFailed.selector, refuser));
        _buyFor(refuser, 0, STIPEND);
    }

    function test_buyFor_surfacesTheHtsCodeWhenTheAddressCannotTakeTheToken() public {
        _launch(); // and no association: an account without a free automatic association slot

        vm.expectRevert(abi.encodeWithSelector(ITokenSale.TokenSaleBuyerNotAssociated.selector, stealth));
        _buyFor(stealth, 0, STIPEND);
    }

    function test_buyFor_addsThePaymentButNotTheStipendToTheSaleTotals() public {
        address token = _launchFor(stealth);
        vm.startPrank(buyer);
        IHRC719(token).associate();
        sale.buy{ value: ONE_HBAR }(0);
        vm.stopPrank();

        _buyFor(stealth, 0, STIPEND);

        (,,,, int64 sold, uint256 raised) = sale.saleInfo();
        assertEq(sold, 4 * ONE_TOKEN + 40 * ONE_TOKEN);
        assertEq(raised, ONE_HBAR + PAYMENT);
    }

    function test_exportSelectors_matchesTheAbi() public {
        _assertExportsItsAbi("StealthBuy", new StealthBuy().exportSelectors());
    }

    /// @dev Launches the sale and lets `to` receive its token. On Hedera the stipend creates the stealth account
    ///      with unlimited automatic associations (HIP-583, HIP-904), so no `associate()` is needed there. The
    ///      mock HTS has no automatic associations, so the test associates `to` without touching its HBAR or code.
    function _launchFor(address to) internal returns (address token) {
        token = _launch();
        hts.associateToken(to, token);
    }

    function _buyFor(address to, int64 minTokensOut, uint256 stipend) internal returns (int64) {
        return _buyFor(to, PAYMENT, minTokensOut, stipend);
    }

    function _buyFor(address to, uint256 payment, int64 minTokensOut, uint256 stipend) internal returns (int64) {
        vm.prank(buyer);
        return stealthBuy.buyFor{ value: payment + stipend }(to, EPHEMERAL_PUB_KEY, VIEW_TAG, minTokensOut, stipend);
    }

    function _onlyLog(bytes32 topic) internal view returns (Vm.Log memory found) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == diamond && logs[i].topics[0] == topic) {
                found = logs[i];
                ++count;
            }
        }
        assertEq(count, 1, "exactly one such event from the diamond");
    }
}
