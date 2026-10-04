# Submission: Lattice Hedera Template

Bounty: Scaffold-HBAR Template Bounty. Submissions close Sunday 4 October 2026, 23:59 ET.

## What to submit

| Field | Value |
| --- | --- |
| Public GitHub repository | https://github.com/dadadave80/lattice-hedera-template |
| HashScan link | https://hashscan.io/testnet/transaction/0xe0720ff59f10e754f01e34c5633b6e31d9fef2e9028c7f1568a2a40a0b4cfd1f (the upgrade to `TokenSaleV2`), or the private purchase, https://hashscan.io/testnet/transaction/{{BUYFOR_TX}}, once it is on testnet |
| Scaffold command | `npm create scaffold-hbar@latest -- --template dadadave80/lattice-hedera-template` |
| Developer experience survey | answered by David, using the notes below |

## One paragraph

An upgradeable HTS token sale on a Lattice diamond that also sells privately. One contract address creates an
HTS token through the Hedera Token Service and sells it for HBAR at a USD price read from the Chainlink HBAR/USD
feed. The showcase is the private purchase: a buyer pays for someone else, and the tokens land on a one-time
ERC-5564 stealth address that nothing on chain ties to the recipient. The HBAR stipend sent with the purchase
creates the stealth account (HIP-583) with unlimited automatic token associations (HIP-904), so the token
arrives in the same transaction, and the stipend later pays the recipient's sweep, so no relayer is needed. The
diamond is upgraded in place with one `diamondCut` from the app. Every Lattice facet in it, `HTSAdapter` and the
ERC-6538 registry and ERC-5564 announcer included, is listed in a Lattice Studio recipe file, so a developer
changes it on a canvas in Studio's Hedera build instead of in Solidity.

## Where the rubric is answered

| Criterion | Where |
| --- | --- |
| Ecosystem integration (35) | HTS through Lattice's `HTSAdapter`, `TokenSale` and `StealthBuy`; Chainlink through `ChainlinkAdapter`; ERC-5564 and ERC-6538 through Lattice's `ERC5564Announcer` and `ERC6538Registry`; HIP-583 lazy account creation and HIP-904 automatic association for stealth deliveries; HIP-719 association in the app; mirror node log reads for the private inbox; HashScan links; the Scaffold-HBAR hooks, Debug Contracts and CLI manifest. |
| Documentation (30) | `README.md` (with the private-purchase walkthrough and its privacy model), `AGENTS.md`, `packages/foundry/README.md`, natspec on every contract, the custom CLI outro. |
| Code quality (20) | 65 Forge tests, 24 Node tests, 99 Vitest tests (the stealth-address math checked against vectors from ScopeLift's stealth-address-sdk), CI, `forge fmt` and ESLint clean, `scripts/gate.sh`. |
| Hedera service depth (15) | Token creation with the diamond as treasury and `delegatableContractId` keys, treasury transfers with response-code handling, association, tinybar and weibar handling, a live upgrade on testnet, and stealth deliveries that create the recipient's account and associate it inside the purchase, with the hollow account completed by its own first transaction. |

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
- The reference deployment (18 transactions, 13.8 million gas, before private purchases), the token launch and
  one purchase cost 33.6 HBAR.
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
- GitHub's archive applies `export-ignore`, so `docs/` and `scripts/` stay out of a project scaffolded from the
  published repository. The CLI reads `template.json` and leaves it out too.
- Source verification was not part of the build plan. The scaffold's `yarn foundry:verify:testnet` (Sourcify)
  verified all 18 reference contracts with exact runtime matches, including facets deployed through the
  deterministic deployment proxy and the diamond created inside `LatticeFactory`, and HashScan showed "Full
  Match" right away. The deploy now runs the same `forge verify-contract` for every contract it created, so a
  template user ships verified contracts without an extra command.

From giving Lattice Studio a Hedera build:

- Hedera's JSON-RPC relay rejects a transaction asking for more than 15,000,000 gas (`-32005
  GAS_LIMIT_TOO_HIGH`), while its blocks report a gas limit of 150,000,000. A tool that sizes the gas cap from
  the latest block has to special-case Hedera.
- CreateX is not deployed on Hedera; Arachnid's deterministic deployment proxy is. A tool that deploys through
  CreateX elsewhere needs another path on Hedera; Studio uses `LatticeFactory` there.

From building private purchases:

- Each Hedera behavior the feature depends on was tried on testnet before any of it was written. HBAR sent from
  a contract to a fresh EVM address created a hollow account with `max_automatic_token_associations = -1`
  (645,737 gas). An HTS transfer from a diamond to that account delivered the token and associated it (756,050
  gas). The hollow account's first transaction, a token transfer signed with its own key, completed the account
  (36,880 gas, about 0.03 HBAR).
- Hedera charged the gas used, not a share of the gas limit: the reference diamond's purchase was charged gas
  used × 84 tinybars.
- The JSON-RPC relay cannot simulate a transaction from an address Hedera has no account for, so the app
  disables a wallet's buttons until it holds HBAR.
- The mirror node searches contract logs by topic only within a timestamp range of at most 7 days. Reading
  every announcement a contract has made takes one search per week of its history.
