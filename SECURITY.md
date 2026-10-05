# Security

## Report a vulnerability

Report it privately through GitHub: [open a security advisory](https://github.com/dadadave80/lattice-hedera-template/security/advisories/new). Do not open a public issue, pull request or discussion about it.

Include what is affected (contract, script or app file, and the commit), how to reproduce it, and what an attacker gains. A failing Forge test or a testnet transaction hash helps most.

You will get an answer within 7 days. A confirmed issue is fixed on `main`, and the advisory is published with credit to you unless you ask otherwise.

## Scope

| In scope | Out of scope |
| --- | --- |
| This project's contracts in `packages/foundry/contracts` (`TokenSale`, `TokenSaleV2`, `StealthBuy`, `SaucerSwapPool`, their libraries and initializers) | [Lattice](https://github.com/dadadave80/lattice) facets under `packages/foundry/lib/lattice`: report those to Lattice |
| The deploy scripts in `packages/foundry/script` and `packages/foundry/scripts-js` | SaucerSwap, Chainlink, the Hedera network and its relays |
| The app in `packages/nextjs`, including the stealth-key derivation and sweep in `utils/stealth` | Scaffold-HBAR's own code, unless this project changed it |
| The reference diamond on Hedera testnet, `0x4Eb94355872aB90ab258B940eE98B706dC9B2aa9` | Testnet HBAR, tokens or rate limits |

Only `main` is supported.

## Before you use it with real value

Nothing here is audited: not this template, and not Lattice, which is pre-1.0. The diamond's admin can replace any function with `diamondCut`, so whoever holds `DEFAULT_ADMIN_ROLE` controls the sale, its proceeds and the pool's LP tokens. Read the README's "Launch on mainnet" section, get an audit, and put the admin role behind a multisig before a mainnet launch.

Stealth keys are derived from a wallet signature in the browser. Anyone who obtains that signature can find and spend every delivery made to its meta-address.
