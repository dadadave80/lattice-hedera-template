# Submission: Lattice Hedera Template

Bounty: Scaffold-HBAR Template Bounty. Submissions close Sunday 4 October 2026, 23:59 ET.

## What to submit

| Field | Value |
| --- | --- |
| Public GitHub repository | https://github.com/dadadave80/lattice-hedera-template |
| HashScan link | https://hashscan.io/testnet/transaction/0xe0720ff59f10e754f01e34c5633b6e31d9fef2e9028c7f1568a2a40a0b4cfd1f |
| Scaffold command | `npm create scaffold-hbar@latest -- --template dadadave80/lattice-hedera-template` |
| Developer experience survey | answered by David, using the notes below |

## One paragraph

An upgradeable HTS token sale on a Lattice diamond. One contract address creates an HTS token through the
Hedera Token Service, sells it for HBAR at a USD price read from the Chainlink HBAR/USD feed, and is upgraded
in place with one `diamondCut` from the app. The diamond's base is a Lattice Studio recipe file, so a
developer changes it on a canvas instead of in Solidity.

## Where the rubric is answered

| Criterion | Where |
| --- | --- |
| Ecosystem integration (35) | HTS through Lattice's `HTSAdapter` and `TokenSale`; Chainlink through `ChainlinkAdapter`; HIP-719 association in the app; HashScan links; the Scaffold-HBAR hooks, Debug Contracts and CLI manifest. |
| Documentation (30) | `README.md`, `AGENTS.md`, `packages/foundry/README.md`, natspec on every contract, the custom CLI outro. |
| Code quality (20) | 43 Forge tests, 24 Node tests, 33 Vitest tests, CI, `forge fmt` and ESLint clean, `scripts/gate.sh`. |
| Hedera service depth (15) | Token creation with the diamond as treasury and `delegatableContractId` keys, treasury transfers with response-code handling, association, tinybar and weibar handling, a live upgrade on testnet. |

## Notes for the developer experience survey

Raw material from building this template. Keep what matches your own experience.

From planning:

- Foundry 1.8 cannot run `forge script` against the Hedera relay (`-32602 Invalid parameter 1`, relay issue
  5826). Foundry 1.7.1 can. Nothing in the scaffolded project says so. The build used 1.7.1 throughout.
- The CLI reinstalls Forge libraries from `remappings.txt`, the root `.gitmodules` and the tags in
  `foundry.lock`. A template author only learns this from the CLI's source. A library pinned to a commit
  rather than a tag cannot be expressed.
- The shape of `template.json` is only documented by the CLI's validation code.
- `packages/foundry/.prettier.json` is not a file name Prettier reads, so the scripts are formatted with
  Prettier's defaults.

Seen during the build on 4 October:

- Without `--skip-hedera-skills` or `--ci` the CLI stops at a prompt, which blocks non-interactive use.
- The CLI will not scaffold into a folder that exists, so a template author working in a prepared folder has
  to scaffold next door and move the files in.
- A Foundry-only scaffold still ships a CI workflow, a lint-staged configuration and an `AGENTS.md` that
  refer to Hardhat.
- The frontend generator only sees contracts that appear as a creation in Forge's broadcast file. A contract
  created by a factory, such as a diamond or a proxy, is invisible to it.
- `forge script` cannot simulate a call to an HTS system contract, so anything that creates a token must be a
  separate transaction after the deploy.
- `yarn foundry:deploy` asks for the keystore password on a terminal, so a coding agent cannot run it against
  a live network; the deploy was run with `forge script --private-key` from `.env` instead.
- The full deployment (18 transactions, 13.8 million gas), the token launch and one purchase cost 33.6 HBAR.
  Creating the token took about 11.8 HBAR of the 20 sent; the rest stayed in the diamond.
- Sending HBAR to a new EVM address creates the account (lazy create) and needs about 600,000 gas. A transfer
  with a 100,000 gas limit failed with `INSUFFICIENT_GAS`; wallets that default to 21,000 fail the same way.
- Accounts created from an EVM address have unlimited automatic token associations (HIP-904), so the
  "associate before you can receive" step most Hedera tutorials describe is optional for MetaMask and burner
  accounts. Their first purchase associated them, and cost about 800,000 gas instead of 111,000.
- Testing the "not associated" path needed an account with no automatic association slots. The HIP-904
  account call `setUnlimitedAutomaticAssociations(false)` made one, and the sale then refused it with
  `TokenSaleBuyerNotAssociated`.
- `eth_call` simulations from system accounts (`0.0.2`, `0.0.98`, `0.0.800`) fail with
  `INSUFFICIENT_PAYER_BALANCE` or odd HTS codes, so they cannot stand in for a user in a dry run.
- A reverted transaction's receipt from the relay carries no reason. The mirror node's
  `/contracts/results/<hash>` gives the error and the revert data a few seconds later.
- HashScan returns 404 to `curl` for transaction, token and contract pages; they only resolve in a browser,
  so a script cannot check README links against HashScan.
- GitHub reported 45 Dependabot alerts on the first push (2 critical, 13 high). Every flagged package
  (`next`, `axios`, `protobufjs`, `tar`, `hono` and others) is in the stock `blank` template's `yarn.lock` at the
  same entries; the template adds none. A new scaffold starts with these alerts.
- GitHub's archive applies `export-ignore`, so `template.json`, `docs/` and `scripts/` stay out of a project
  scaffolded from the published repository.
- Source verification was not part of the build plan. The scaffold's `yarn foundry:verify:testnet` (Sourcify)
  verified all 18 reference contracts with exact runtime matches, including facets deployed through the
  deterministic deployment proxy and the diamond created inside `LatticeFactory`, and HashScan showed "Full
  Match" right away. The deploy now runs the same `forge verify-contract` for every contract it created, so a
  template user ships verified contracts without an extra command.
