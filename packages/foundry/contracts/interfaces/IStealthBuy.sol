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
    /// @notice Emitted on every stealth purchase, after the ERC-5564 `Announcement`.
    /// @param paidTinybars What the tokens were bought with: `msg.value` minus the stipend.
    /// @param stipendTinybars What the stealth address received in HBAR.
    event StealthDelivery(address indexed stealthAddress, int64 tokens, uint256 paidTinybars, uint256 stipendTinybars);

    /// @notice The stealth address is the zero address.
    error StealthBuyZeroAddress();
    /// @notice The stipend leaves nothing of `value` to pay for tokens.
    error StealthBuyStipendTooHigh(uint256 stipend, uint256 value);
    /// @notice The stealth address did not accept the stipend.
    error StealthBuyStipendFailed(address stealthAddress);

    /// @notice Buys tokens with `msg.value - stipend` at the sale's quote, sends `stipend` and the tokens to
    ///         `stealthAddress`, and announces the delivery for the recipient to find.
    /// @dev The announcement is ERC-5564's `Announcement` with scheme id 1 (secp256k1 with view tags) and the
    ///      payer as caller. Its metadata is 57 bytes: `viewTag`, the ERC-20 `transfer` selector `0xa9059cbb`,
    ///      the token's address and the token units as a `uint256`.
    /// @param ephemeralPubKey The payer's ephemeral public key, from which the recipient derives the address.
    /// @param viewTag The first byte of the shared secret's hash, which lets the recipient skip most announcements.
    /// @param minTokensOut Reverts if the payment buys fewer token units.
    /// @param stipend Tinybars for the stealth address, taken from `msg.value`.
    /// @return tokens Token units delivered to `stealthAddress`.
    function buyFor(
        address stealthAddress,
        bytes calldata ephemeralPubKey,
        bytes1 viewTag,
        int64 minTokensOut,
        uint256 stipend
    ) external payable returns (int64 tokens);
}
