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
