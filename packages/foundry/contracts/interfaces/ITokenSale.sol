// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ITokenSale
/// @notice A fixed-USD-price sale of one HTS token that the diamond itself created and treasuries. Buyers
///         pay HBAR; the HBAR/USD rate comes from whichever oracle facet answers `latestAnswer(bytes32)`
///         on the diamond.
/// @dev Units, because Hedera has two views of HBAR:
///      - inside the EVM, `msg.value` and balances are tinybars (1 HBAR = 1e8);
///      - over JSON-RPC, a transaction's `value` is weibars (1 HBAR = 1e18) and the relay converts.
///      Every HBAR amount in this interface is tinybars. USD amounts are 18-decimal fixed point.
///      Token amounts are in the token's smallest unit and are `int64`, as HTS defines them.
interface ITokenSale {
    /// @notice Emitted once, when the sale token is created and its price set.
    event SaleLaunched(address indexed token, int32 decimals, int64 supply, uint256 priceUsd);

    /// @notice Emitted on every purchase. `hbarUsd` is the oracle answer the purchase was priced at.
    event TokensPurchased(address indexed buyer, uint256 tinybars, int64 tokens, uint256 hbarUsd);

    /// @notice `launchSale` was called on a diamond that already sells `token`.
    error TokenSaleAlreadyLaunched(address token);
    /// @notice The sale has no token yet: `launchSale` has not been called.
    error TokenSaleNotLaunched();
    /// @notice A price of zero, or an oracle answer that is not positive.
    error TokenSaleInvalidPrice();
    /// @notice Token decimals outside 0..18.
    error TokenSaleInvalidDecimals(int32 decimals);
    /// @notice The payment buys no whole token unit, or more units than an `int64` can hold.
    error TokenSaleInvalidAmount();
    /// @notice The payment buys fewer tokens than the buyer's `minTokens`.
    error TokenSaleSlippage(int64 tokens, int64 minTokens);
    /// @notice `buyer` must associate with the token before buying (HTS 184).
    error TokenSaleBuyerNotAssociated(address buyer);
    /// @notice HTS refused the transfer to the buyer with `responseCode`.
    error TokenSaleTransferFailed(int64 responseCode);

    /// @notice Creates the sale token through HTS, with the diamond as treasury, and sets its price.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE` and `HTS_MANAGER_ROLE`. `msg.value` pays the HTS creation
    ///      fee. Hedera deducts only the fee (HIP-358); the rest stays in the diamond.
    /// @param decimals Token decimals, 0..18.
    /// @param supply Initial supply in the token's smallest unit, minted to the diamond.
    /// @param priceUsd USD per whole token, 18 decimals.
    function launchSale(
        string calldata name,
        string calldata symbol,
        string calldata memo,
        int32 decimals,
        int64 supply,
        uint256 priceUsd
    ) external payable returns (address token);

    /// @notice Buys tokens with the HBAR sent. Reverts if that buys fewer than `minTokens`.
    /// @return tokens Token units transferred to the caller.
    function buy(int64 minTokens) external payable returns (int64 tokens);

    /// @notice Token units that `tinybars` buys at the current oracle rate.
    function quote(uint256 tinybars) external view returns (int64 tokens);

    /// @notice The sale's configuration and running totals.
    /// @return token The HTS token on sale, or the zero address before launch.
    /// @return decimals The token's decimals.
    /// @return priceUsd USD per whole token, 18 decimals.
    /// @return feedKey The key passed to the oracle facet's `latestAnswer`.
    /// @return sold Token units sold so far.
    /// @return raised Tinybars received so far.
    function saleInfo()
        external
        view
        returns (address token, int32 decimals, uint256 priceUsd, bytes32 feedKey, int64 sold, uint256 raised);
}
