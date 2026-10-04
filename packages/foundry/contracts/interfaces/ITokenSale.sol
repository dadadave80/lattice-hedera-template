// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ITokenSale
/// @notice A fixed-USD-price sale of one HTS token that the diamond itself created and treasuries. Buyers
///         pay HBAR; the HBAR/USD rate comes from whichever oracle facet answers `latestAnswer(bytes32)`
///         on the diamond.
/// @dev Units, because Hedera has two views of HBAR:
///      - inside the EVM, `msg.value` and balances are tinybars (1 HBAR = 1e8);
///      - over JSON-RPC, a transaction's `value` is weibars (1 HBAR = 1e18) and the relay converts.
///      Every HBAR amount in this interface is tinybars. USD amounts are 18-decimal fixed point (WAD).
///      Token amounts are in the token's smallest unit and are `int64`, as HTS defines them.
///      `buy` and `IStealthBuy.buyFor` revert with `IEmergencyStop.EmergencyStopActive` while a guardian holds
///      the diamond's emergency stop. Nothing else here is gated by it: quotes, the admin functions and
///      withdrawals keep working.
interface ITokenSale {
    /// @notice Emitted once, when the sale token is created and its price set.
    /// @param token The new HTS token, treasuried by the diamond.
    /// @param decimals The token's decimals.
    /// @param supply The initial supply in token units, all held by the diamond.
    /// @param priceUsd USD per whole token, 18 decimals.
    event SaleLaunched(address indexed token, int32 decimals, int64 supply, uint256 priceUsd);

    /// @notice Emitted when the admin changes the price.
    /// @param priceUsd The new price: USD per whole token, 18 decimals.
    event SalePriceSet(uint256 priceUsd);

    /// @notice Emitted by `buy`. A stealth purchase emits `IStealthBuy.StealthDelivery` instead, never this.
    /// @param buyer The caller, who received the tokens.
    /// @param tinybars The whole `msg.value`, including any remainder too small to buy one more token unit.
    /// @param tokens Token units transferred to `buyer`.
    /// @param hbarUsd The oracle answer the purchase was priced at: USD per HBAR, 18 decimals.
    event TokensPurchased(address indexed buyer, uint256 tinybars, int64 tokens, uint256 hbarUsd);

    /// @notice Emitted when the admin withdraws HBAR from the diamond, before the transfer is made.
    /// @param to The recipient.
    /// @param tinybars The amount sent.
    event ProceedsWithdrawn(address indexed to, uint256 tinybars);

    /// @notice `launchSale` was called on a diamond that already sells a token.
    /// @param token The token already on sale.
    error TokenSaleAlreadyLaunched(address token);
    /// @notice The sale has no token yet: `launchSale` has not been called.
    error TokenSaleNotLaunched();
    /// @notice A price of zero, or an oracle answer that is not positive.
    error TokenSaleInvalidPrice();
    /// @notice Token decimals outside 0..18.
    /// @param decimals The decimals that were passed.
    error TokenSaleInvalidDecimals(int32 decimals);
    /// @notice The payment buys no whole token unit, or more units than an `int64` can hold.
    error TokenSaleInvalidAmount();
    /// @notice The payment buys fewer tokens than the caller's minimum.
    /// @param tokens Token units the payment buys.
    /// @param minTokens The caller's minimum.
    error TokenSaleSlippage(int64 tokens, int64 minTokens);
    /// @notice HTS refused the transfer because the recipient is not associated with the token (HTS 184).
    /// @param buyer The recipient: the buyer, or the stealth address of a stealth purchase.
    error TokenSaleBuyerNotAssociated(address buyer);
    /// @notice HTS refused the transfer to the recipient.
    /// @param responseCode The HTS response code. 178 (`INSUFFICIENT_TOKEN_BALANCE`) means the diamond holds
    ///        fewer tokens than the purchase buys: the sale is sold out until an account with `HTS_OPERATOR_ROLE`
    ///        mints more through `HTSAdapter.mintToken`. 21 (`UNKNOWN`) means the call to HTS itself failed.
    error TokenSaleTransferFailed(int64 responseCode);
    /// @notice The HBAR transfer to the withdrawal recipient failed, or the diamond holds less than requested.
    error TokenSaleWithdrawFailed();

    /// @notice Creates the sale token through HTS, with the diamond as treasury, and sets its price.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE` and `HTS_MANAGER_ROLE`. `msg.value` pays the HTS creation
    ///      fee. Hedera deducts only the fee (HIP-358); the rest stays in the diamond. The diamond holds the
    ///      token's admin and supply keys, and the supply is uncapped. Runs once per diamond.
    /// @param name The token's name.
    /// @param symbol The token's symbol.
    /// @param memo The token's memo.
    /// @param decimals Token decimals, 0..18.
    /// @param supply Initial supply in the token's smallest unit, minted to the diamond.
    /// @param priceUsd USD per whole token, 18 decimals.
    /// @return token The new token's address.
    function launchSale(
        string calldata name,
        string calldata symbol,
        string calldata memo,
        int32 decimals,
        int64 supply,
        uint256 priceUsd
    ) external payable returns (address token);

    /// @notice Sets the price. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param priceUsd USD per whole token, 18 decimals. Zero reverts with `TokenSaleInvalidPrice`.
    function setSalePrice(uint256 priceUsd) external;

    /// @notice Sends HBAR from the diamond to `to`. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @dev Not capped at `raised`: it can move any HBAR the diamond holds, including what `launchSale` left.
    /// @param to The recipient.
    /// @param tinybars The amount to send.
    function withdrawProceeds(address payable to, uint256 tinybars) external;

    /// @notice Buys tokens with the HBAR sent and transfers them to the caller.
    /// @dev The token count rounds down, and the diamond keeps the whole payment, including the remainder too
    ///      small to buy one more unit. The caller must be associated with the token or have a free automatic
    ///      association slot. Reverts with `IEmergencyStop.EmergencyStopActive` while the sale is stopped, and
    ///      with `TokenSaleTransferFailed(178)` when the diamond holds fewer tokens than the payment buys.
    /// @param minTokens Reverts with `TokenSaleSlippage` if the payment buys fewer token units.
    /// @return tokens Token units transferred to the caller.
    function buy(int64 minTokens) external payable returns (int64 tokens);

    /// @notice Token units that `tinybars` buys at the current oracle rate, rounded down, bonus included.
    /// @dev Reverts as `buy` would for a payment that buys no unit (`TokenSaleInvalidAmount`), before launch
    ///      and on a bad oracle answer. It does not check the stop or the diamond's token balance.
    /// @param tinybars The payment to price.
    /// @return tokens Token units the payment buys.
    function quote(uint256 tinybars) external view returns (int64 tokens);

    /// @notice The sale's configuration and running totals.
    /// @return token The HTS token on sale, or the zero address before launch.
    /// @return decimals The token's decimals.
    /// @return priceUsd USD per whole token, 18 decimals.
    /// @return feedKey The key passed to the oracle facet's `latestAnswer`.
    /// @return sold Token units sold so far, stealth purchases included.
    /// @return raised Tinybars paid for tokens so far, stealth purchases included and stipends excluded. It
    ///         counts remainders the diamond kept, and withdrawals do not reduce it.
    function saleInfo()
        external
        view
        returns (address token, int32 decimals, uint256 priceUsd, bytes32 feedKey, int64 sold, uint256 raised);
}
