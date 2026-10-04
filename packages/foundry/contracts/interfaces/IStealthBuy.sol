// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IStealthBuy
/// @notice Buys the sale's token for someone else and delivers it to a one-time ERC-5564 stealth address, which
///         nothing on chain ties to the recipient. The payer, the amount and the time stay public.
/// @dev On Hedera, HBAR sent to an address that has no account creates one (HIP-583) with unlimited automatic
///      token associations (HIP-904), so the stealth address can take the token in the same transaction. The
///      stipend is that HBAR, and it later pays the stealth account's own gas to move the token.
///      Every HBAR amount here is tinybars, as in `ITokenSale`.
interface IStealthBuy {
    /// @notice Emitted on every stealth purchase, after the ERC-5564 `Announcement`. A stealth purchase emits
    ///         this instead of `ITokenSale.TokensPurchased`.
    /// @param stealthAddress The one-time address that received the stipend and the tokens.
    /// @param tokens Token units delivered.
    /// @param paidTinybars What the tokens were bought with: `msg.value` minus the stipend, including any
    ///        remainder too small to buy one more token unit.
    /// @param stipendTinybars What the stealth address received in HBAR.
    event StealthDelivery(address indexed stealthAddress, int64 tokens, uint256 paidTinybars, uint256 stipendTinybars);

    /// @notice The stealth address is the zero address.
    error StealthBuyZeroAddress();
    /// @notice The stipend leaves nothing of `value` to pay for tokens.
    /// @param stipend The stipend asked for.
    /// @param value The tinybars sent.
    error StealthBuyStipendTooHigh(uint256 stipend, uint256 value);
    /// @notice The stealth address did not accept the stipend.
    /// @param stealthAddress The address that refused it.
    error StealthBuyStipendFailed(address stealthAddress);

    /// @notice Buys tokens with `msg.value - stipend` at the sale's quote, sends `stipend` and the tokens to
    ///         `stealthAddress`, and announces the delivery for the recipient to find.
    /// @dev Priced by the diamond's own `quote`, so the running sale facet's bonus applies, and booked into the
    ///      sale's `sold` and `raised` like any purchase. It emits `StealthDelivery`, not `TokensPurchased`. The
    ///      token count rounds down and the diamond keeps the whole payment, remainder included.
    ///      Reverts with `ITokenSale.TokenSaleNotLaunched` before launch, then with
    ///      `IEmergencyStop.EmergencyStopActive` while the sale is stopped. A sold-out sale reverts with
    ///      `ITokenSale.TokenSaleTransferFailed(178)`.
    ///      The totals are booked before the stipend is sent, and the stipend is sent before the tokens because
    ///      on Hedera it is what creates the stealth account. There is no reentrancy guard: a stealth address
    ///      with code can buy again from the stipend call and sees the totals already updated.
    ///      The announcement is ERC-5564's `Announcement` with scheme id 1 (secp256k1 with view tags) and the
    ///      payer as caller. Its metadata is 57 bytes: `viewTag`, the ERC-20 `transfer` selector `0xa9059cbb`,
    ///      the token's address and the token units as a `uint256`.
    /// @param stealthAddress The recipient's one-time address, derived off chain from their stealth meta-address.
    /// @param ephemeralPubKey The payer's ephemeral public key, from which the recipient derives the address.
    /// @param viewTag The first byte of the shared secret's hash, which lets the recipient skip most announcements.
    /// @param minTokensOut Reverts with `ITokenSale.TokenSaleSlippage` if the payment buys fewer token units.
    /// @param stipend Tinybars for the stealth address, taken from `msg.value`. There is no on-chain minimum and
    ///        zero passes. Sending enough to create the account and pay its later gas is left to the payer.
    /// @return tokens Token units delivered to `stealthAddress`.
    function buyFor(
        address stealthAddress,
        bytes calldata ephemeralPubKey,
        bytes1 viewTag,
        int64 minTokensOut,
        uint256 stipend
    ) external payable returns (int64 tokens);
}
