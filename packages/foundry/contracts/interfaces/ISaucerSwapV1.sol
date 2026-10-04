// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ISaucerSwapV1Factory
/// @notice The part of SaucerSwap V1's factory that `SaucerSwapPool` reads
///         (https://docs.saucerswap.finance/developers/contracts).
interface ISaucerSwapV1Factory {
    /// @notice The pair of `tokenA` and `tokenB`, in either order, or the zero address when there is none.
    function getPair(address tokenA, address tokenB) external view returns (address pair);

    /// @notice What creating a pair costs, in tinycents (1 USD = 1e10 tinycents). SaucerSwap can change it.
    function pairCreateFee() external view returns (uint256 tinycents);
}

/// @title ISaucerSwapV1Router
/// @notice The two liquidity functions of SaucerSwapV1RouterV3 that `SaucerSwapPool` calls. Every HBAR amount is
///         tinybars and every token amount is in the token's smallest unit.
interface ISaucerSwapV1Router {
    /// @notice Creates the `token`/WHBAR pair and adds its first liquidity. `msg.value` must be strictly more than
    ///         the pair creation fee in tinybars, and everything above the fee becomes the pool's HBAR.
    /// @dev The min arguments have no effect: a new pool takes `amountTokenDesired` and all the HBAR above the fee,
    ///      so nothing is refunded. The router pulls the token with HTS `transferToken`, which needs an allowance
    ///      from the caller.
    /// @return amountToken Token units added.
    /// @return amountETH Tinybars added.
    /// @return liquidity LP token units minted to `to` (8 decimals).
    function addLiquidityETHNewPool(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    /// @notice Adds liquidity to an existing `token`/WHBAR pair at its current reserve ratio and sends the HBAR it
    ///         did not use back to the caller.
    /// @dev Reverts `INSUFFICIENT_A_AMOUNT` or `INSUFFICIENT_B_AMOUNT` when the ratio would add less than a minimum.
    /// @return amountToken Token units added.
    /// @return amountETH Tinybars added.
    /// @return liquidity LP token units minted to `to` (8 decimals).
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

/// @title ISaucerSwapV1Pair
/// @notice The part of a SaucerSwap V1 pair that `SaucerSwapPool` reads.
/// @dev The pair's LP token is a separate HTS token, not the pair's own address. Read its supply from
///      `lpToken()`: `totalSupply()` on the pair itself reverts on some deployed mainnet pairs.
interface ISaucerSwapV1Pair {
    /// @notice The lower of the pair's two token addresses.
    function token0() external view returns (address);

    /// @notice The higher of the pair's two token addresses.
    function token1() external view returns (address);

    /// @notice The HTS token the pair mints to liquidity providers.
    function lpToken() external view returns (address);

    /// @notice The pair's reserves, ordered as `token0` and `token1`, and the time they last changed.
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

/// @title IHederaTokenServiceApprove
/// @notice The HTS system contract's fungible-token `approve`, which Lattice's `IHederaTokenService` does not carry.
interface IHederaTokenServiceApprove {
    /// @notice Lets `spender` move `amount` of the caller's `token`. Replaces any earlier allowance; 0 removes it.
    /// @return responseCode 22 on success. HTS does not revert.
    function approve(address token, address spender, uint256 amount) external returns (int64 responseCode);
}
