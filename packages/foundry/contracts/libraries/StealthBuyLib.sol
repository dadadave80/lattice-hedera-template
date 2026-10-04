// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC5564Announcer } from "@lattice/interfaces/privacy/IERC5564Announcer.sol";
import { EmergencyStopLib } from "@lattice/security/libraries/EmergencyStopLib.sol";
import { IStealthBuy } from "../interfaces/IStealthBuy.sol";
import { ITokenSale } from "../interfaces/ITokenSale.sol";
import { TokenSaleLib, TokenSaleStorage } from "./TokenSaleLib.sol";

/// @dev ERC-5564 scheme 1: secp256k1 with view tags.
uint256 constant SCHEME_ID = 1;

/// @dev The ERC-20 `transfer` selector, which ERC-5564's metadata uses to say a token was sent.
bytes4 constant ERC20_TRANSFER = 0xa9059cbb;

/// @title StealthBuyLib
/// @notice Logic for the StealthBuy facet. It keeps no storage of its own: a stealth purchase is a sale, so it
///         books into `TokenSaleStorage` and pays out through the sale's treasury transfer.
library StealthBuyLib {
    function buyFor(
        address stealthAddress,
        bytes calldata ephemeralPubKey,
        bytes1 viewTag,
        int64 minTokensOut,
        uint256 stipend
    ) internal returns (int64 tokens) {
        TokenSaleStorage storage $ = TokenSaleLib.tokenSaleStorage();
        if ($.token == address(0)) revert ITokenSale.TokenSaleNotLaunched();
        EmergencyStopLib.checkNotStopped();
        if (stealthAddress == address(0)) revert IStealthBuy.StealthBuyZeroAddress();
        if (stipend >= msg.value) revert IStealthBuy.StealthBuyStipendTooHigh(stipend, msg.value);

        uint256 payment = msg.value - stipend;
        // Priced by the sale facet the diamond runs, bonus included, so a stealth purchase gets what `quote` says.
        tokens = ITokenSale(address(this)).quote(payment);
        if (tokens < minTokensOut) revert ITokenSale.TokenSaleSlippage(tokens, minTokensOut);

        $.sold += tokens;
        $.raised += payment;

        // The HBAR goes first because on Hedera it is what creates the stealth account the tokens go to.
        (bool ok,) = stealthAddress.call{ value: stipend }("");
        if (!ok) revert IStealthBuy.StealthBuyStipendFailed(stealthAddress);
        TokenSaleLib._transferFromTreasury($.token, stealthAddress, tokens);

        // What `ERC5564AnnouncerLib.announce` emits. That function takes the metadata as calldata, and the
        // metadata is built here.
        emit IERC5564Announcer.Announcement(
            SCHEME_ID,
            stealthAddress,
            msg.sender,
            ephemeralPubKey,
            // forge-lint: disable-next-line(unsafe-typecast)
            abi.encodePacked(viewTag, ERC20_TRANSFER, $.token, uint256(uint64(tokens)))
        );
        emit IStealthBuy.StealthDelivery(stealthAddress, tokens, payment, stipend);
    }
}
