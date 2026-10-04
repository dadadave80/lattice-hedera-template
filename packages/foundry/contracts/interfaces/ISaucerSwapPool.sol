// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ISaucerSwapPool
/// @notice Puts the sale's token and HBAR into a SaucerSwap V1 pool: the diamond creates the token/WHBAR pool, or
///         adds to it when one exists, and keeps the LP tokens. The sale keeps selling its remaining tokens.
/// @dev The sale keeps selling at the oracle price after the pool opens, so the pool's price cannot stay above the
///      sale's: whenever it does, anyone can buy from the sale and sell into the pool, and the diamond's LP position
///      takes that selling. `emergencyStop` blocks both `buy` and `seedPool`, so it cannot end the sale and keep the
///      pool; ending the sale for good needs a new `TokenSale` facet.
///      Every HBAR amount here is tinybars, as in `ITokenSale`. Token amounts are in the token's smallest unit and
///      are `int64`, as HTS defines them. LP amounts are in the LP token's smallest unit (8 decimals).
interface ISaucerSwapPool {
    /// @notice What `poolInfo` returns.
    /// @param router The SaucerSwap V1 router the diamond adds liquidity through.
    /// @param factory The SaucerSwap V1 factory that creates and lists pairs.
    /// @param whbar The WHBAR HTS token that pairs with the sale's token.
    /// @param pair The token/WHBAR pair, or the zero address when nobody has created it yet.
    /// @param lpToken The pair's LP token, or the zero address when there is no pair.
    /// @param lpBalance LP token units the diamond holds.
    /// @param lpTotalSupply LP token units in existence, including the 1000 the first deposit locks.
    /// @param reserveTokens Sale token units in the pool.
    /// @param reserveTinybars Tinybars (as WHBAR) in the pool.
    /// @param creationFee What creating the pair costs now, in tinybars, at the network's exchange rate.
    struct PoolInfo {
        address router;
        address factory;
        address whbar;
        address pair;
        address lpToken;
        uint256 lpBalance;
        uint256 lpTotalSupply;
        uint256 reserveTokens;
        uint256 reserveTinybars;
        uint256 creationFee;
    }

    /// @notice Emitted every time the diamond adds liquidity.
    /// @param pair The token/WHBAR pair.
    /// @param lpToken The pair's LP token.
    /// @param created True when this call created the pool.
    /// @param tokens Sale token units added.
    /// @param tinybars Tinybars added, not counting the creation fee.
    /// @param liquidity LP token units the diamond received.
    /// @param creationFee Tinybars paid to create the pool, 0 when it already existed.
    event PoolSeeded(
        address indexed pair,
        address indexed lpToken,
        bool created,
        int64 tokens,
        uint256 tinybars,
        uint256 liquidity,
        uint256 creationFee
    );

    /// @notice Emitted when the admin moves LP tokens out of the diamond.
    /// @param lpToken The pair's LP token.
    /// @param to The account that received them.
    /// @param amount LP token units moved.
    event LiquidityTransferred(address indexed lpToken, address indexed to, int64 amount);

    /// @notice The facet was cut in without running `SaucerSwapPoolInit`, so it has no router.
    error SaucerSwapPoolNotConfigured();
    /// @notice An amount or a minimum is zero or negative.
    error SaucerSwapPoolInvalidAmount();
    /// @notice The diamond holds fewer tinybars than the call needs, the creation fee included.
    error SaucerSwapPoolInsufficientHbar(uint256 needed, uint256 balance);
    /// @notice The diamond holds fewer of the sale's token units than the call adds.
    error SaucerSwapPoolInsufficientTokens(uint256 needed, uint256 balance);
    /// @notice Creating the pool costs more than the caller's `maxCreationFee`.
    error SaucerSwapPoolCreationFeeTooHigh(uint256 fee, uint256 maxCreationFee);
    /// @notice HTS refused to set the router's allowance with `responseCode`.
    error SaucerSwapPoolApproveFailed(int64 responseCode);
    /// @notice HTS refused to associate the diamond with the LP token with `responseCode`.
    error SaucerSwapPoolAssociateFailed(int64 responseCode);
    /// @notice The diamond has not added liquidity yet, so it has no LP token to move.
    error SaucerSwapPoolNoLiquidity();
    /// @notice HTS refused to move the diamond's LP tokens with `responseCode`.
    error SaucerSwapPoolTransferFailed(int64 responseCode);

    /// @notice Adds `tokens` of the diamond's sale token and `tinybars` of its HBAR to the SaucerSwap V1 pool,
    ///         creating the pool first when it does not exist. The diamond receives the LP tokens.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`, and the emergency stop must be off.
    ///      - HBAR comes from the diamond's balance, sale proceeds included. `msg.value` adds to that balance first,
    ///        so the admin can bring the HBAR in the same call.
    ///      - New pool: the call also pays the pair creation fee, which SaucerSwap sets in USD and the network
    ///        converts at its exchange rate. The pool opens at exactly `tinybars` to `tokens`. To open at the price
    ///        buyers pay, pass `tokens = quote(tinybars)`; under `TokenSaleV2` that price includes the bonus.
    ///      - Existing pool, including one someone else created first: the router adds at the pool's ratio and
    ///        reverts below the minimums, and the HBAR it does not use stays in the diamond.
    ///      - Set `minTokens` and `minTinybars` close to `tokens` and `tinybars` (for example 99%) even when no pool
    ///        exists. If someone creates the pool before this transaction lands, the call adds to their pool at
    ///        their price, and only the minimums stop it. Zero minimums are refused.
    ///      - The router gets an allowance of exactly `tokens`, and whatever it does not use is withdrawn.
    ///      - On Hedera, give the transaction an explicit gas limit of 10-12M: creating a pool alone uses about
    ///        7.5M, and the relay's estimate is not reliable for HTS calls.
    /// @param tokens Sale token units to add, from the diamond's treasury.
    /// @param tinybars HBAR to add, in tinybars, not counting the creation fee.
    /// @param minTokens The fewest token units the router may add. Must be positive.
    /// @param minTinybars The fewest tinybars the router may add. Must be positive.
    /// @param maxCreationFee New pool: the most tinybars the creation fee may cost. Pass a margin over
    ///        `poolInfo().creationFee`, for example 105%: the exchange rate can move before the transaction lands,
    ///        and the call pays only the fee at execution. Ignored when the pool exists.
    /// @param deadline Unix time in seconds after which the router refuses the call.
    /// @return tokensAdded Sale token units the pool took.
    /// @return tinybarsAdded Tinybars the pool took, not counting the creation fee.
    /// @return liquidity LP token units the diamond received.
    function seedPool(
        int64 tokens,
        uint256 tinybars,
        int64 minTokens,
        uint256 minTinybars,
        uint256 maxCreationFee,
        uint256 deadline
    ) external payable returns (int64 tokensAdded, uint256 tinybarsAdded, uint256 liquidity);

    /// @notice Moves `amount` of the diamond's LP tokens to `to`, which must be associated with the LP token.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`. Works while the emergency stop is on, as `withdrawProceeds` does.
    ///      The LP token is the one the diamond last added liquidity to.
    function transferLiquidity(address to, int64 amount) external;

    /// @notice The SaucerSwap addresses the diamond uses, its pool and its LP position.
    /// @dev The pair is read from the factory on every call, so a pool someone else created shows up here before
    ///      the diamond adds to it. Before the sale launches, only the addresses and the creation fee are filled.
    function poolInfo() external view returns (PoolInfo memory info);
}
