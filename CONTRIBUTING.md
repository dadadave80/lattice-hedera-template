# Contributing

Issues and pull requests are welcome. For anything larger than a fix, open an issue first so we can agree on the approach. Report security problems privately, as [SECURITY.md](SECURITY.md) says.

## Set up

You need Node.js 20.18.3 or later, Yarn (through Corepack), Git and [Foundry](https://getfoundry.sh). Deploying to Hedera needs Foundry 1.7.1; building and testing work on any recent Foundry.

```bash
git clone --recurse-submodules https://github.com/dadadave80/lattice-hedera-template.git
cd lattice-hedera-template
yarn install
```

There is no local chain: HTS and the Chainlink feed exist only on Hedera. Contract tests run against mocks, and the app runs against Hedera testnet.

## Before you open a pull request

All of these must pass. CI runs the same checks.

```bash
yarn foundry:test        # Forge tests and the Node tests for scripts-js
yarn next:test           # Vitest unit tests
yarn lint                # next lint, forge fmt --check, prettier --check
yarn next:check-types
yarn next:build
```

`yarn format` fixes what `yarn lint` reports.

## Rules

[AGENTS.md](AGENTS.md) lists the rules that are easy to get wrong. The ones that break things most often:

- Change the diamond's Lattice facets in `packages/foundry/diamond.recipe.json`, not in Solidity.
- Facets hold no state. Storage lives in a library with its own ERC-7201 slot. Append fields to a storage struct; never reorder or remove them, and never change a slot.
- Every facet lists its selectors in `exportSelectors()`. A test fails when the list and the ABI disagree.
- Contracts see tinybars. Convert HBAR units in the app only through `packages/nextjs/utils/sale/units.ts`.
- Check the response code of every call to the HTS system contract (`22` is success).
- Do not edit `packages/foundry/lib` or `packages/nextjs/contracts/deployedContracts.ts`. The second is generated on every deploy.

Test behavior through the diamond, as a wallet would, including the revert a caller sees. Put frontend logic that can be wrong in `packages/nextjs/utils` with a `*.test.ts` beside it.

## Commits and pull requests

Use [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`, `docs:`, `test:`, `chore:`). Keep a pull request to one change, describe what it changes and how you tested it, and update the README and AGENTS.md when behavior or commands change.

By contributing you agree that your work is licensed under the project's [MIT licence](LICENCE) and that you follow the [code of conduct](CODE_OF_CONDUCT.md).
