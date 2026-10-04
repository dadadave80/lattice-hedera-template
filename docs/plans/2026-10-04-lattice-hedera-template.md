# Lattice Hedera Template Implementation Plan

**Goal:** Ship `dadadave80/lattice-hedera-template`, a Scaffold-HBAR template that passes the bounty's eligibility gate and is submitted before Sunday 4 October 2026, 23:59 ET (Monday 03:59 UTC, 04:59 WAT): an upgradeable HTS token sale on a Lattice diamond, priced by Chainlink, whose base can be edited in Lattice Studio.
**Architecture:** `DeployDiamond.s.sol` builds one Lattice diamond (EIP-2535) on Hedera: it reads the Lattice base from `packages/foundry/diamond.recipe.json`, a file in Lattice Studio's recipe format, and appends a fixed Hedera layer of Lattice's `HTSAdapter` and this project's `TokenSale` facet. `TokenSale` creates an HTS token with the diamond as treasury and sells it for HBAR at a USD price read through the diamond's own `latestAnswer(bytes32)`, which `ChainlinkAdapter` serves. The Next.js app sees one `Diamond` contract whose ABI is the union of its facets, and its walkthrough ends with a live `diamondCut` to `TokenSaleV2`.
**Tech Stack:** create-scaffold-hbar 0.4.1 and its `blank` template (Yarn 3 workspaces, Foundry, Next.js 15, wagmi, viem, DaisyUI); Solidity 0.8.36 on `cancun`; Lattice at tag `hedera-template-pin-6c8db45`; the Hedera Token Service system contract at `0x167`; the Chainlink HBAR/USD feed; Foundry 1.7.1; Node's built-in test runner; Vitest 3; GitHub Actions.

---

## Read this first

This plan is for Claude Code, working in `~/Dev/projects/lattice-hedera-template` in a session started in that folder with `claude --add-dir ../lattice ../lattice-studio`. The folder already exists. Before Task 1 it holds only `docs/plans/`, with this plan and the design, and Task 1 scaffolds the project into it. `../lattice` and `../lattice-studio` are David's checkouts of the two repositories the template builds on; "Three folders" below says what belongs in each. The plan has 41 tasks in seven phases, numbered from 0. The approved design for the Lattice Studio link is `docs/plans/2026-10-03-studio-recipe-seam-design.md`; this plan implements it.

Two things before Task 1. Do not run `/init`, `/turbocharge:setup` or `/turbocharge:atlas` in this folder: the scaffold brings its own `CLAUDE.md` and `AGENTS.md`, those files ship to everyone who scaffolds the template, and a `CLAUDE.md` that is already here stops Task 1's move. And if you hand tasks to subagents, give each one the "Conventions" section with its task: a subagent that reads only its own task does not know that listings are exact, that Step 2 must fail for the reason given, or that Foundry 1.7.1 is required.

### The bounty's gate

Every item is pass or fail. `scripts/gate.sh`, written in Task 2, checks all of them.

| Gate item | Checked by |
| --- | --- |
| Scaffolds cleanly with `npm create scaffold-hbar@latest -- --template dadadave80/lattice-hedera-template` | `scripts/gate.sh scaffold` (Task 38) and `published` (Task 40) |
| Valid `template.json` | `scripts/gate.sh static` |
| `README.md` and `AGENTS.md` present | `scripts/gate.sh static` |
| Install, lint and build succeed from a fresh scaffold | `scripts/gate.sh scaffold` |
| The app boots and its core routes return OK | `scripts/gate.sh scaffold` |
| At least one Hedera service operational, with a verifiable testnet transaction and a HashScan or mirror link | Tasks 22 and 39; `scripts/gate.sh static` checks the links are in the README |
| No committed secrets, no committed `.env` | `scripts/gate.sh static` |
| Original work under MIT | `LICENCE`; `scripts/gate.sh static` |

The rubric after the gate: ecosystem integration 35, documentation 30, code quality 20, Hedera service depth 15.

### Conventions

1. **Paths and commands are relative to the repository root.** A command in parentheses, such as `(cd packages/foundry && forge test)`, runs in a subshell so the next command starts from the root again.
2. **Listings are exact.** `Create` means a new file with exactly that content. `Replace the whole of` means overwrite. `Edit` gives text that occurs exactly once in the file, and what to insert after it, insert before it, or replace it with. An inserted block may begin with an empty line, and where one ends with an empty line the instruction says so. Keep those lines: they separate functions, and `forge fmt --check` fails without them.
3. **Step 2 must fail for the reason given.** If it passes, or fails differently, stop and find out why before Step 3. The quoted output was captured from a real run; `<repo>` stands for the absolute path of the repository.
4. **A task that changes no behaviour has no unit test.** Scaffolding, deleting files, documents and deployments are checked by a command that fails before the change and passes after it. The task says so in Step 1.
5. **Use Foundry 1.7.1 for everything.** It builds, tests and formats this project the same as 1.8, and it is the only version whose `forge script` reaches Hedera's relay.
6. **Commit on the branch `build`.** Run the `git commit` given in Step 5 and append whatever attribution trailer your session's instructions require. The pre-commit hook lints and type-checks staged files under `packages/nextjs`; never pass `--no-verify`. After every commit `git status --short` must print nothing.
7. **If `yarn lint` complains about formatting, run `yarn format`** and look at what it changed before committing.
8. **Secrets.** The deployer key lives only in `packages/foundry/.env`, which is git-ignored. Never print it, never put it in a command as a literal, never commit it. Do not open that file, or `../lattice/.env`, to read a key: the commands in Tasks 22 and 39 load it into the shell without showing it.
9. **Your own working files stay out of the repository.** If the session's tooling writes notes, memory, logs or settings into this folder, add their paths to `.git/info/exclude`, not to `.gitignore`, and never commit them. Task 1 does this for Claude Code's local settings and subagent memory. Where a task says `git add -A`, look at `git status --short` first.

### Three folders

The three repositories sit side by side in `~/Dev/projects`. A change is made in the folder of the repository it changes.

| Folder | Repository | What this plan does there |
| --- | --- | --- |
| `lattice-hedera-template`, the working directory | `dadadave80/lattice-hedera-template`, created on GitHub in Task 40 | Everything, on the branch `build`. |
| `../lattice` | `dadadave80/lattice` | One thing: Task 4 tags commit `6c8db45` and pushes the tag. No branch is merged or checked out and no file is edited. |
| `../lattice-studio` | `dadadave80/lattice-studio` | Nothing. It is there to read. |

1. **Never edit `packages/foundry/lib/lattice`.** It is a submodule pinned to a tag. A project scaffolded from the template installs Lattice from GitHub by that tag, so an edit made there would exist nowhere else.
2. **If a task exposes a defect in Lattice**, which is most likely in Task 22, the first live deployment: keep the template working from the pinned tag with the contingency the task gives, then tell David what you found. A fix in Lattice is his decision. It is made in `../lattice` on `feat/hedera-system-contract-modules`, with Lattice's own tests and conventions, and it reaches the template only through a new pin (rule 3).
3. **To move the template to another Lattice commit, add a tag. Never move one.** Projects already scaffolded install the old tag by name. The new tag carries the first seven characters of its commit. With David's go-ahead for the push:

   ```bash
   NEW=<the full 40-character commit hash, already pushed to dadadave80/lattice>
   TAG=hedera-template-pin-$(printf %.7s "$NEW")
   git -C ../lattice tag "$TAG" "$NEW" && git -C ../lattice push origin "$TAG"
   (cd packages/foundry && forge remove lattice --force && forge install "dadadave80/lattice@$TAG")
   ```

   `forge install` rewrites `packages/foundry/foundry.lock`: the `lib/lattice` entry now names the new tag and commit, and a stray `packages/foundry/lib/forge-std` entry is back. Delete the stray entry, so the file has the two entries Task 4 shows. Then:

   ```bash
   yarn foundry:test && bash scripts/gate.sh static
   git add .gitmodules packages/foundry/foundry.lock packages/foundry/lib/lattice
   git commit -m "build: pin Lattice at $TAG"
   ```

   Run `bash scripts/gate.sh scaffold` again before Task 40. The two `forge` commands were run against a second tag in the planning sandbox, and the lock file came out as described.
4. **`../lattice-studio` needs no change for this template.** The template calls nothing in Studio and copies none of its code. Two files here follow formats Studio owns, and are the ones to revisit if Studio changes them: `packages/foundry/script/DeployDiamond.s.sol` reads the recipe format (`../lattice-studio/apps/studio/public/schema/recipe.v1.json`), and `packages/foundry/scripts-js/studioLink.js` writes the share-link format (`../lattice-studio/packages/core/src/share/link.ts`). Putting `HTSAdapter` on Studio's sheet means regenerating Studio's catalog from a Lattice commit that has the Hedera facets. That is Studio work for after the bounty; the design lists it as out of scope. When Studio's catalog does change, its tag and hash change with it, and five places here name them: `catalog` in `packages/foundry/diamond.recipe.json` and in the four recipes under `packages/foundry/test/fixtures/`, `CATALOG_TAG` in `DeployDiamond.s.sol`, the warning test in `test/DeployDiamond.t.sol`, which quotes the tag, `STUDIO_ENCODED` in `scripts-js/studioLink.test.js`, and the table of values in this plan. Export the default recipe from the new Studio and copy the values from that file.
5. **Ask David before any push from `../lattice` or `../lattice-studio`.** The only push this plan needs there is the tag in Task 4. A commit in either folder follows that repository's conventions, not this plan's.
6. **One thing in `../lattice` is worth a minute of David's time, and it is optional.** The README links Lattice's Hedera guide on the branch `feat/hedera-system-contract-modules`. That guide still says twice, in its opening and above its verification table, that nothing has been sent to a live Hedera network, while the table itself records the live probe of 12 September. A judge who follows the link reads the opening first. Correcting the two sentences is a documentation commit on that branch; the pin tag does not move and nothing in the template changes. The link names the branch, so when the branch is merged and deleted, change the link in the template's README in the same sitting.

### What needs David

| Task | What |
| --- | --- |
| Before 1 | A Claude Code session started in the folder. This plan and the design document are already in its `docs/plans/`. |
| 4 | Go-ahead to push the tag `hedera-template-pin-6c8db45` to `dadadave80/lattice`. |
| 22 | A funded Hedera testnet key in `packages/foundry/.env` as `HEDERA_TESTNET_PK`: the hex key, `0x` and 64 characters, not the DER form. The estimate for the build is about 40 HBAR (deployment 12 to 17, token creation 20, a 1 HBAR purchase, the rest gas), and about 30 more for the optional check at the end of Task 39, so 100 HBAR, one faucet claim, covers it. Lattice's probe uses the same variable name, so David can copy the line from `../lattice/.env`. The account that sent that probe, `0xc46a896cbf32ba3212ebe12108345f30ac0a0efd`, held 1,414 HBAR when its balance last changed, on 14 September. |
| 30 | Ten minutes in a browser with a wallet, unless Claude Code has a browser tool. |
| 39 | The upgrade from the app with the admin wallet. A terminal fallback exists. |
| 40 | Go-ahead to create the public repository and push. |
| 41 | Submitting, and answering the developer experience survey. |

### How this plan was verified

- Every task that changes a file (Tasks 2 to 37, and the file edits of Tasks 39 and 41) was replayed in order in a clean copy of the CLI's scaffold output, with Foundry 1.7.1 and Node 22. Each Step 2 failed with the output quoted in the task, each Step 4 passed, each commit went through the pre-commit hook and left a clean working tree, and `forge fmt --check` and Prettier were clean at every commit. For the two deployment tasks (22 and 39) the replay substituted a deployment made on a local chain and placeholder transaction hashes.
- The resulting tree was put through `scripts/gate.sh scaffold` with the real CLI from npm. All fourteen checks passed. The Lattice tag does not exist on GitHub yet, so a local mirror of Lattice carrying that tag stood in for it.
- The contracts, scripts and app were exercised end to end against a local chain with Lattice's HTS mock and a mock feed in place: `yarn foundry:deploy` under Foundry 1.7.1 (18 transactions), `launchSale`, `associate` and `buy` through `cast`, and in a browser the sale page, the admin card, the facet table, the cut preview and the cut to `TokenSaleV2`.
- The final Forge suite also passes on Foundry 1.8.1 and on 1.8.4, the newest release, and `forge fmt --check` is clean on both. On 1.8.1 `forge build` prints ten informational lint notes about `TokenSaleLib.sol` (inline assembly, a low-level call, internal functions used once). They come from the Lattice module pattern itself. Foundry 1.7.1 and 1.8.4 print none.
- The whole replay was run a second time from the stock scaffold on 4 October. All 41 tasks passed, and `scripts/gate.sh static` (12 checks) and `scripts/gate.sh scaffold` (14 checks) passed on the tree it produced. The one difference from the first run, apart from timings, is noted in Task 6.
- After that run these passages were changed by hand and were not replayed: this section and the ones around it, Task 1, the tag commands in Task 4, the failure notes in Tasks 6, 22 and 30, and one command in Task 39 that printed a field the mirror node's list does not have. No listing of a file's content was changed. Task 1's move into the existing folder was run on a stock scaffold in the sandbox (Linux, bash 5.2): the stock tests passed afterwards, a commit went through the pre-commit hook, and the working tree was clean. macOS ships bash 3.2, which has every feature the script uses. The mirror-node commands in Tasks 22 and 39 were run against a sample with the fields the live mirror node returns.
- The public testnet mirror node was read on 4 October 2026 between 01:45 and 02:15 UTC. Nothing was sent to the network. What it showed is in the table below. Testnet was on network version 0.77.2; Lattice's probe of 12 September ran on 0.76.3.
- The link that `yarn diamond:studio` prints for the default recipe was opened in the hosted Lattice Studio on 4 October, in a browser on David's machine. Studio loaded it as `Hedera diamond base (shared)`, reported `No problems` and `5 facets · 24 selectors`, and named its catalog `dev f4a32c8`, the one this plan pins.
- The three forms of HashScan link the README uses were opened the same way, with the transactions, token and diamond of Lattice's probe: `/testnet/transaction/<EVM hash>`, `/testnet/token/<EVM address>` and `/testnet/contract/<EVM address>` all resolve.

### Not verified

The sandbox could not reach Hedera's relay, and nothing was pushed to GitHub. Each item below is exercised for the first time in the task named, which carries the contingency. The middle column is what the mirror node and Lattice's own probe record (`../lattice/broadcast/ProbeHedera.s.sol/296/run-latest.json`) already show.

| Not verified | What is known | First exercised in |
| --- | --- | --- |
| Deploying Lattice facets through the deterministic deployment proxy by way of the relay | The proxy is on testnet as contract `0.0.4283707`. CreateX is not, so `BaseDeploy` takes the proxy path. The probe deployed its facets with plain `CREATE`, so its record shows no deployment through the proxy. | Task 22, step 3b |
| The Chainlink testnet feed having a usable answer through the relay | It has one on the mirror node. The feed proxy `0.0.4870176` points at aggregator `0xd4dc5f0a891381d09d6437482a0e4e2dca4accaa`, which reported at 20:16, 21:30 and 23:06 UTC on 3 October. The last answer was `10159039`, which is $0.1016 at 8 decimals. | Task 22, step 3a |
| What a deployment costs in HBAR | Gas is 83 tinybars on testnet. The local reference deployment used 13.8 million gas: about 11.5 HBAR at that price, or 15.6 at the 113 tinybars the probe paid on 12 September. The probe's receipts show the network charging the gas a call used, not a share of its limit. | Task 22, steps 3b to 3d |
| The unused part of the token creation payment staying in the diamond | The probe sent its diamond (`0.0.10506850`) 70 HBAR and created two tokens with 20 HBAR each. The diamond still holds 38.19 HBAR, so each creation took about 15.9 HBAR and the rest stayed. | Task 22, step 3c |
| A treasury transfer made from inside a facet, which is what `buy` does | Not measured anywhere. Lattice's guide reasons that it passes for the same reason the facet's mint did in the probe. | Task 22, step 3d |
| An unassociated buyer being refused with `TokenSaleBuyerNotAssociated` on the live network | | Task 30, step 4 of the walkthrough |
| `eth_call` answering HIP-719 `isAssociated()`, and wallet gas estimation for calls into HTS | | Task 30 |
| GitHub applying `export-ignore` to the archive the CLI downloads; the Actions workflow; scaffolding from the published repository | | Task 40 |
| The CLI scaffolding under a temporary name on David's machine | The name appears in no scaffolded file, and the stock `blank` template has no rename map. | Task 1 |

### One deviation from the design's build order

The design says to put a hand-wired diamond on testnet and boot the app first, and to write the recipe reader afterwards. Here the deploy script reads the recipe from its first version (Task 5). The prototype showed that reading a facet list and admin-only init steps takes about twenty lines more than hard-coding them, and it avoids a hand-wired script that a later task would throw away. The design's intent is kept: nothing optional stands in front of the gate. The rest of the seam (other init shapes, `owners`, `exclude`, warnings, the Studio link) is Phase 4, after the testnet deployment and the app.

### If time runs short

Start Phase 6 no later than 20:00 ET on Sunday (Monday 00:00 UTC, 01:00 WAT), with whatever is done. Phases 1, 2, 3, 5 and 6 are never cut. Inside Phase 4, cut in this order, which is the design's:

1. The third test in `studioLink.test.js` (the cross-check against Studio's encoder) and its constant.
2. Task 32. Then remove the row ``| `selector 0x… is exported by both A and B` | ... |`` from the README's error table, remove ``, `owners`, `exclude` `` from the test table in `packages/foundry/README.md`, and expect three fewer Forge tests wherever a count is quoted.
3. Task 33. Expect two fewer Forge tests.

Task 31 and the script half of Task 34 stay: the README's oracle swap and its first Studio step depend on them.

### Values used throughout

| What | Value |
| --- | --- |
| Hedera testnet relay, chain id | `https://testnet.hashio.io/api`, 296 |
| Hedera testnet mirror node | `https://testnet.mirrornode.hedera.com/api/v1` |
| HTS system contract | `0x0000000000000000000000000000000000000167` |
| Chainlink HBAR/USD feed, testnet | `0x59bC155EB6c6C415fE43255aF66EcF0523c92B4a` |
| Chainlink HBAR/USD feed, mainnet | `0xAF685FB45C12b92b5054ccb9313e135525F9b5d5` |
| Deterministic deployment proxy | `0x4e59b44847b379578588920cA78FbF26c0B4956C` |
| Lattice pin | tag `hedera-template-pin-6c8db45`, commit `6c8db45aa46986af2edb6a0d8fb02a4a92faef01` |
| Lattice Studio | `https://lattice-studio-topaz.vercel.app/`, catalog tag `dev-f4a32c8` |
| HBAR units | contracts see tinybars (1 HBAR = 1e8); a JSON-RPC `value` is weibars (1 HBAR = 1e18) |
| HTS response codes | 22 success, 184 token not associated, 178 insufficient token balance |
| `TokenSale` selectors | `buy(int64)` `0x08bf598d`, `launchSale(...)` `0xdf1d74ae`, `quote(uint256)` `0xed1bd76c`, `saleInfo()` `0x8e3695b8`, `setSalePrice(uint256)` `0x1919fed7`, `withdrawProceeds(address,uint256)` `0x970ea83e`; `TokenSaleV2` adds `bonusBps()` `0x404f21a5` |

---

## Phase 0: Workspace, gate and pins

### Task 1: Scaffold the workspace

**Files:**
- Create: the project in `~/Dev/projects/lattice-hedera-template` (written by the CLI next door, then moved in)
- Already there: `docs/plans/2026-10-03-studio-recipe-seam-design.md`
- Already there: `docs/plans/2026-10-04-lattice-hedera-template.md`

The folder exists and holds this plan and the design. The CLI will not scaffold into a folder that exists: its first step is `mkdir <name>`, and it stops when that fails. So the CLI scaffolds the stock `blank` template into a temporary folder next door, and the result is moved in here. The folder this session runs in is never removed or renamed. The name given to the CLI appears in no scaffolded file, so the temporary name leaves no trace.

The CLI installs dependencies, installs the Forge libraries and makes the first commit on `main`. Everything after this task happens inside the project.

**Step 1: Write the failing test**

There is no code to test yet. The check is that the stock tests run in this folder:

```bash
yarn foundry:test
```

**Step 2: Run test to verify it fails**

Run: `yarn foundry:test`

Expected: FAIL. Yarn finds no project here, because the folder holds only `docs/`. The wording depends on the Yarn installed globally; Yarn 1 says `error Couldn't find a package.json file in "<repo>"`.

**Step 3: Write minimal implementation**

Check the toolchain first. Every command must succeed before you scaffold:

```bash
node --version      # v20.18.3 or newer
yarn --version      # any version: the project carries its own Yarn 3.2.3
git --version
gh auth status      # logged in as dadadave80
forge --version     # write this down: it is David's usual Foundry
foundryup --install v1.7.1
forge --version     # forge Version: 1.7.1
```

If `yarn` is missing, `corepack enable` provides it on Node 24 and older; otherwise `npm install --global yarn`.

Foundry 1.7.1 is used for the whole build: it builds, tests and formats this project exactly as 1.8 does, and it is the only version whose `forge script` can reach Hedera's JSON-RPC relay. `foundryup` switches the machine's active Foundry, which David's other projects use too. Task 41 reminds him to switch back.

Look at what the folder holds:

```bash
ls -A
```

Expected: `docs`, and perhaps `.claude` (this session's local settings) or `.DS_Store`. If anything else is there, stop and ask David what it is.

Scaffold next door. `--skip-hedera-skills` is there because the CLI otherwise stops to ask a question, and because the marketplace skills do not belong in a template repository:

```bash
(cd ~/Dev/projects && npm create scaffold-hbar@latest lattice-hedera-template-scaffold -- \
  --template blank --solidity-framework foundry --frontend nextjs-app \
  --network testnet --package-manager yarn --skip-hedera-skills)
```

Expected: the CLI finishes with its next-steps text, and `~/Dev/projects/lattice-hedera-template-scaffold` holds the project.

Move the project in. The script first looks for names both folders have. A directory on both sides (`.claude`) is merged. Anything else on both sides stops the script before it moves a single file:

```bash
(cd ~/Dev/projects && bash -c '
set -euo pipefail
shopt -s dotglob nullglob
src=lattice-hedera-template-scaffold dst=lattice-hedera-template
clash=0
for entry in "$src"/*; do
  name=${entry##*/}
  [ -e "$dst/$name" ] || [ -L "$dst/$name" ] || continue
  if [ "$name" = .git ] || [ ! -d "$entry" ] || [ -L "$entry" ] || [ ! -d "$dst/$name" ] || [ -L "$dst/$name" ]; then
    echo "STOP: $name exists in both folders" >&2
    clash=1
  fi
done
[ "$clash" = 0 ] || exit 1
for entry in "$src"/*; do
  name=${entry##*/}
  if [ -d "$dst/$name" ]; then
    cp -R "$entry"/. "$dst/$name"/ && rm -rf "$entry"
  else
    mv "$entry" "$dst"/
  fi
done
rmdir "$src"
')
```

Expected: no output, and `~/Dev/projects/lattice-hedera-template-scaffold` is gone. If it prints `STOP`, nothing was moved. For a file, rename David's copy (`mv <name> <name>.before-scaffold`), run the block again, and tell David. If the name is `.git`, this folder is already a git repository: ask David before doing anything.

Start the working branch, and keep this session's own files out of `git status`. `.git/info/exclude` is local to this checkout, so nothing about it reaches the template:

```bash
git switch -c build
printf '%s\n' '.claude/settings.local.json' '.claude/agent-memory/' '.claude/agent-memory-local/' 'ATLAS.md' >> .git/info/exclude
git log --oneline
git status --short
```

Expected: one commit, `Initial commit with create-scaffold-hbar @ 0.4.1`, and one untracked entry, `?? docs/`. If another untracked path shows up and the session's tooling wrote it, add it to `.git/info/exclude` as well.

All work happens on `build`. `main` is fast-forwarded and pushed in Task 40, with David's go-ahead.

**Step 4: Run test to verify it passes**

Run: `yarn foundry:test`

Expected: PASS. The stock `HederaToken` tests pass and the `HtsTokenCreator` suite is skipped, because it needs a Hedera fork. If Yarn cannot find a tool after the move, run `yarn install` once and try again; it only relinks.

**Step 5: Commit**

```bash
git add docs/plans
git commit -m "docs: add the design and the implementation plan"
```

---

### Task 2: Template manifest and the eligibility gate

**Files:**
- Create: `scripts/gate.sh`
- Create: `template.json`
- Create: `.gitattributes`
- Modify: `LICENCE`

The bounty's gate is pass or fail, so it becomes a script before anything else is built. `scripts/gate.sh static` is the acceptance test for the manifest, the documents, the secrets rule and the testnet evidence. Later tasks turn its lines green one at a time. Its `scaffold` and `published` modes are used in Tasks 38 and 40.

**Step 1: Write the failing test**

Create `scripts/gate.sh`:

```bash
#!/usr/bin/env bash
# The Scaffold-HBAR template bounty's eligibility gate, as commands. This script lives in the template
# repository and is left out of the projects scaffolded from it (see .gitattributes).
#
#   scripts/gate.sh static      Checks the repository itself. Takes seconds.
#   scripts/gate.sh scaffold    Scaffolds a project from the committed tree, then lints, tests, builds and
#                               boots it. Takes minutes. Needs forge, yarn and network access.
#   scripts/gate.sh published   The same, scaffolding from GitHub the way a judge does.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REPO="dadadave80/lattice-hedera-template"
PORT=3210
failures=0

check() { # check "<what must hold>" <command> [args...]
  local description=$1 output
  shift
  if output=$("$@" 2>&1); then
    printf 'PASS  %s\n' "$description"
  else
    printf 'FAIL  %s\n' "$description"
    [ -n "$output" ] && printf '%s\n' "$output" | tail -n 20 | sed 's/^/      /'
    failures=$((failures + 1))
  fi
}

finish() {
  if [ "$failures" -gt 0 ]; then
    printf '\n%s check(s) failed.\n' "$failures"
    exit 1
  fi
  printf '\nAll checks passed.\n'
}

# ── static ──────────────────────────────────────────────────────────────────────────────────────────

manifest_is_valid() {
  [ -f "$ROOT/template.json" ] || return 1
  node -e '
    const manifest = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const { capabilities } = manifest["create-scaffold-hbar"];
    const ok =
      manifest.name === "lattice-hedera-template" &&
      capabilities.frontend.join() === "nextjs-app" &&
      capabilities.solidityFramework.join() === "foundry" &&
      capabilities.packageManager.join() === "yarn";
    process.exit(ok ? 0 : 1);
  ' "$ROOT/template.json"
}

readme_has() { grep -qE -- "$1" "$ROOT/README.md"; }

readme_has_no_placeholders() { ! grep -q "PENDING" "$ROOT/README.md"; }

no_env_file_is_tracked() {
  ! git -C "$ROOT" ls-files | grep -E '(^|/)\.env[^/]*$' | grep -qvE '\.env\.example$'
}

no_private_key_is_tracked() {
  ! git -C "$ROOT" grep -IqE '(PRIVATE_KEY|_PK)[[:space:]]*=[[:space:]]*["'\'']?(0x)?[0-9a-fA-F]{64}' -- .
}

# create-scaffold-hbar reinstalls every library named in remappings.txt. It needs the library's URL from
# .gitmodules and its tag from foundry.lock, and stops if either is missing.
libraries_are_pinned() {
  local lib
  [ -f "$ROOT/.gitmodules" ] || return 1
  for lib in $(sed -nE 's#^[^=]*=lib/([^/]+)/.*#\1#p' "$ROOT/packages/foundry/remappings.txt" | sort -u); do
    grep -q "path = packages/foundry/lib/$lib\$" "$ROOT/.gitmodules" || return 1
    node -e '
      const lock = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      process.exit(lock[`lib/${process.argv[2]}`]?.tag?.name ? 0 : 1);
    ' "$ROOT/packages/foundry/foundry.lock" "$lib" || return 1
  done
}

app_points_at_testnet_diamond() {
  grep -q "296: {" "$ROOT/packages/nextjs/contracts/deployedContracts.ts" &&
    grep -q "Diamond: {" "$ROOT/packages/nextjs/contracts/deployedContracts.ts"
}

static_checks() {
  check "template.json is a valid create-scaffold-hbar manifest for this template" manifest_is_valid
  check "README.md exists" test -s "$ROOT/README.md"
  check "AGENTS.md exists" test -s "$ROOT/AGENTS.md"
  check "LICENCE is MIT" grep -q "MIT License" "$ROOT/LICENCE"
  check "README.md shows the scaffold command" readme_has "npm create scaffold-hbar@latest -- --template $REPO"
  check "README.md explains the Lattice Studio seam" readme_has "^## Customize in Lattice Studio"
  check "README.md links testnet transactions on HashScan or the mirror node" \
    readme_has "https://(hashscan\.io/testnet/(tx|transaction)|testnet\.mirrornode\.hedera\.com/api/v1/contracts/results)/0x"
  check "README.md has no PENDING placeholders" readme_has_no_placeholders
  check "no .env file is tracked" no_env_file_is_tracked
  check "no private key is tracked" no_private_key_is_tracked
  check "every Forge library in remappings.txt is pinned in .gitmodules and foundry.lock" libraries_are_pinned
  check "the app points at a diamond on Hedera testnet" app_points_at_testnet_diamond
}

# ── scaffold ────────────────────────────────────────────────────────────────────────────────────────

server=""
stop_server() {
  # The server was started under job control, so it leads its own process group.
  [ -n "$server" ] && kill -- "-$server" 2>/dev/null
  return 0
}

route_is_ok() { curl -fsS -o /dev/null "http://localhost:$PORT$1"; }

wait_for_server() {
  local attempt
  for attempt in $(seq 1 60); do
    route_is_ok / && return 0
    sleep 1
  done
  return 1
}

scaffold_checks() { # scaffold_checks local|published
  local work project template
  work=$(mktemp -d)
  project="$work/gate-project"

  if [ "$1" = local ]; then
    # What GitHub would hand the CLI: the committed tree, minus export-ignore paths.
    mkdir "$work/template"
    git -C "$ROOT" archive HEAD | tar -x -C "$work/template"
    # The CLI's own seam for templates that are not published yet: copy this tree instead of downloading.
    export CREATE_SCAFFOLD_HBAR_TEMPLATE_DIR="$work/template"
    template=blank
  else
    template=$REPO
  fi

  printf 'Scaffolding into %s (log: %s/scaffold.log)\n' "$project" "$work"
  (cd "$work" && npm create scaffold-hbar@latest gate-project -- --template "$template" \
    --solidity-framework foundry --frontend nextjs-app --network testnet --package-manager yarn \
    --ci --skip-hedera-skills) >"$work/scaffold.log" 2>&1
  check "the template scaffolds and installs" test -f "$project/packages/foundry/lib/lattice/src/Lattice.sol"
  if [ "$failures" -gt 0 ]; then
    tail -n 30 "$work/scaffold.log"
    finish
  fi

  cd "$project" || exit 1
  check "the scaffold has README.md and AGENTS.md" test -s README.md -a -s AGENTS.md
  check "the scaffold leaves out template.json, docs and scripts" \
    test ! -e template.json -a ! -e docs -a ! -e scripts -a ! -e .gitattributes
  check "no .env file is committed in the scaffold" no_env_file_is_tracked_in "$project"
  check "yarn lint" yarn lint
  check "yarn foundry:test" yarn foundry:test
  check "yarn next:test" yarn next:test
  check "yarn next:check-types" yarn next:check-types
  check "yarn next:build" yarn next:build

  set -m
  yarn next:serve --port "$PORT" >"$work/serve.log" 2>&1 &
  server=$!
  set +m
  trap stop_server EXIT
  check "the app boots" wait_for_server
  local route
  for route in / /diamond /debug /blockexplorer; do
    check "GET $route returns OK" route_is_ok "$route"
  done
  stop_server
}

no_env_file_is_tracked_in() {
  ! git -C "$1" ls-files | grep -E '(^|/)\.env[^/]*$' | grep -qvE '\.env\.example$'
}

case "${1:-}" in
  static) static_checks ;;
  scaffold) scaffold_checks local ;;
  published) scaffold_checks published ;;
  *)
    printf 'Usage: scripts/gate.sh static|scaffold|published\n'
    exit 2
    ;;
esac
finish
```

```bash
chmod +x scripts/gate.sh
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/gate.sh static`

Expected: FAIL. Five lines fail. The first one is this task's.

```text
FAIL  template.json is a valid create-scaffold-hbar manifest for this template
PASS  README.md exists
PASS  AGENTS.md exists
PASS  LICENCE is MIT
FAIL  README.md shows the scaffold command
FAIL  README.md explains the Lattice Studio seam
FAIL  README.md links testnet transactions on HashScan or the mirror node
PASS  README.md has no PENDING placeholders
PASS  no .env file is tracked
PASS  no private key is tracked
PASS  every Forge library in remappings.txt is pinned in .gitmodules and foundry.lock
FAIL  the app points at a diamond on Hedera testnet
5 check(s) failed.
```

**Step 3: Write minimal implementation**

The manifest declares what the template supports. The CLI validates it and removes it from the scaffolded project. Yarn is the only package manager because the CLI's npm mode rewrites every `yarn` in the project's text files.

Create `template.json`:

```json
{
  "name": "lattice-hedera-template",
  "description": "Upgradeable HTS token sale on a Lattice diamond, priced by Chainlink, customizable in Lattice Studio.",
  "version": "0.1.0",
  "create-scaffold-hbar": {
    "capabilities": {
      "frontend": ["nextjs-app"],
      "solidityFramework": ["foundry"],
      "packageManager": ["yarn"]
    },
    "defaults": {
      "frontend": "nextjs-app",
      "solidityFramework": "foundry",
      "packageManager": "yarn"
    },
    "outro": {
      "sections": [
        {
          "title": "Try it first (nothing to deploy)",
          "steps": [
            {
              "label": "Run the contract and script tests",
              "command": "{run:foundry:test}"
            },
            {
              "label": "Start the app against the reference diamond on Hedera testnet",
              "command": "{run:next:dev}"
            }
          ]
        },
        {
          "title": "Deploy your own diamond",
          "steps": [
            {
              "label": "Create a deployer account",
              "command": "{run:foundry:account:generate}"
            },
            {
              "label": "Fund it with testnet HBAR",
              "url": "https://portal.hedera.com/faucet"
            },
            {
              "label": "Deploy to Hedera testnet",
              "command": "{run:foundry:deploy} --network hedera_testnet",
              "text": "Deploying needs Foundry 1.7.1 for now. The README explains why."
            },
            {
              "label": "Change the diamond in Lattice Studio",
              "command": "{run:diamond:studio}"
            }
          ]
        }
      ]
    }
  }
}
```

GitHub builds the archive the CLI downloads with `git archive`, which honours `export-ignore`. This keeps the build documents, the gate script and this file itself out of scaffolded projects.

Create `.gitattributes`:

```text
# Kept in this repository, left out of the projects scaffolded from it: the build documents, the
# eligibility gate script, and this file.
.gitattributes export-ignore
docs export-ignore
scripts export-ignore
```

Add the template author's copyright line under the two that are there.

Replace the whole of `LICENCE` with:

```text
MIT License

Copyright (c) 2023 BuidlGuidl
Copyright (c) 2026 hedera-dev
Copyright (c) 2026 David Dada

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**Step 4: Run test to verify it passes**

Run: `bash scripts/gate.sh static | grep template.json`

Expected: PASS. `PASS  template.json is a valid create-scaffold-hbar manifest for this template`. The script as a whole still exits 1: the README lines belong to Task 35, the evidence lines to Tasks 22 and 39.

**Step 5: Commit**

```bash
git add scripts/gate.sh template.json .gitattributes LICENCE
git commit -m "chore: add the template manifest and the eligibility gate"
```

---

### Task 3: Remove the stock sample contracts

**Files:**
- Delete: `packages/foundry/contracts/HederaToken.sol`
- Delete: `packages/foundry/contracts/HtsTokenCreator.sol`
- Delete: `packages/foundry/contracts/interfaces/IHederaTokenService.sol`
- Delete: `packages/foundry/script/Deploy.s.sol`
- Delete: `packages/foundry/script/DeployHederaToken.s.sol`
- Delete: `packages/foundry/script/DeployHtsTokenCreator.s.sol`
- Delete: `packages/foundry/test/HederaToken.t.sol`
- Delete: `packages/foundry/test/HtsTokenCreator.t.sol`
- Modify: `packages/nextjs/contracts/deployedContracts.ts`

The blank template ships an ERC-20, an HTS token creator, their tests and deploy scripts, and a `deployedContracts.ts` that points at them. None of it survives. `Deploy.s.sol` comes back in Task 16.

**Step 1: Write the failing test**

Nothing here has behaviour to test. The check is that no source file refers to the samples:

```bash
! grep -rlE 'HederaToken|HtsTokenCreator' packages/foundry/contracts packages/foundry/script packages/foundry/test packages/nextjs/contracts
```

**Step 2: Run test to verify it fails**

Run:

```bash
! grep -rlE 'HederaToken|HtsTokenCreator' packages/foundry/contracts packages/foundry/script packages/foundry/test packages/nextjs/contracts
```

Expected: FAIL. The command lists the files that still mention the samples and exits 1.

```text
packages/foundry/contracts/HtsTokenCreator.sol
packages/foundry/contracts/HederaToken.sol
packages/foundry/contracts/interfaces/IHederaTokenService.sol
packages/foundry/script/DeployHederaToken.s.sol
packages/foundry/script/Deploy.s.sol
packages/foundry/script/DeployHtsTokenCreator.s.sol
packages/foundry/test/HederaToken.t.sol
packages/foundry/test/HtsTokenCreator.t.sol
packages/nextjs/contracts/deployedContracts.ts
```

**Step 3: Write minimal implementation**

```bash
git rm packages/foundry/contracts/HederaToken.sol \
  packages/foundry/contracts/HtsTokenCreator.sol \
  packages/foundry/contracts/interfaces/IHederaTokenService.sol \
  packages/foundry/script/Deploy.s.sol \
  packages/foundry/script/DeployHederaToken.s.sol \
  packages/foundry/script/DeployHtsTokenCreator.s.sol \
  packages/foundry/test/HederaToken.t.sol \
  packages/foundry/test/HtsTokenCreator.t.sol
```

This is what `generateTsAbis.js` writes when nothing is deployed. The app type-checks against it until the first testnet deployment replaces it in Task 22.

Replace the whole of `packages/nextjs/contracts/deployedContracts.ts` with:

```typescript
/**
 * This file is autogenerated by Scaffold-HBAR.
 * You should not edit it manually or your changes might be overwritten.
 */
import { GenericContractsDeclaration } from "~~/utils/scaffold-hbar/contract";

const deployedContracts = {} as const;

export default deployedContracts satisfies GenericContractsDeclaration;
```

**Step 4: Run test to verify it passes**

Run:

```bash
! grep -rlE 'HederaToken|HtsTokenCreator' packages/foundry/contracts packages/foundry/script packages/foundry/test packages/nextjs/contracts && yarn next:check-types
```

Expected: PASS. No file is listed and the type check exits 0.

**Step 5: Commit**

```bash
git add packages/foundry packages/nextjs/contracts/deployedContracts.ts
git commit -m "chore: remove the stock sample contracts"
```

---

### Task 4: Pin Lattice and swap the Forge libraries

**Files:**
- Create: `packages/foundry/contracts/LatticeFacets.sol`
- Modify: `packages/foundry/foundry.lock`
- Modify: `packages/foundry/remappings.txt`
- Modify: `packages/foundry/foundry.toml`

The template depends on Lattice's Hedera branch at commit `6c8db45`. `create-scaffold-hbar` reinstalls every library named in `remappings.txt` with `forge install <repo>@<tag>`, reading the repository from the root `.gitmodules` and the tag from `foundry.lock`, so the pin has to be a tag.

**Needs David's go-ahead:** pushing the tag writes to `dadadave80/lattice`. Ask before Step 3.

**Step 1: Write the failing test**

The first file that needs Lattice is the one that compiles its facets into the project, so it is the check: it builds only when the library and the remappings are in place.

Create `packages/foundry/contracts/LatticeFacets.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// The facets (and inits) this project can deploy by name. One import line wires one more.
import { DiamondLoupeFacet } from "@diamond/facets/DiamondLoupeFacet.sol";
import { ERC165Facet } from "@diamond/facets/ERC165Facet.sol";
import { Receive } from "@lattice/Receive.sol";
import { AccessControl } from "@lattice/access/AccessControl.sol";
import { AccessControlInit } from "@lattice/access/AccessControlInit.sol";
import { AccessControlDiamondCut } from "@lattice/governance/AccessControlDiamondCut.sol";
import { ChainlinkAdapter } from "@lattice/oracles/chainlink/ChainlinkAdapter.sol";
import { ChainlinkAdapterInit } from "@lattice/oracles/chainlink/ChainlinkAdapterInit.sol";
import { PythAdapter } from "@lattice/oracles/pyth/PythAdapter.sol";
import { PythAdapterInit } from "@lattice/oracles/pyth/PythAdapterInit.sol";
import { EmergencyStop } from "@lattice/security/EmergencyStop.sol";
import { Pausable } from "@lattice/security/Pausable.sol";
import { HTSAdapter } from "@lattice/tokens/hedera/HTSAdapter.sol";
import { HTSAdapterInit } from "@lattice/tokens/hedera/HTSAdapterInit.sol";
import { Multicall } from "@lattice/utils/Multicall.sol";
```

**Step 2: Run test to verify it fails**

Run: `(cd packages/foundry && forge build)`

Expected: FAIL. The `@diamond/` and `@lattice/` imports do not resolve.

```text
Unable to resolve imports:
"@lattice/Receive.sol" in "<repo>/packages/foundry/contracts/LatticeFacets.sol"
```

**Step 3: Write minimal implementation**

Tag the pinned commit in David's Lattice checkout, `../lattice`, and push the tag. These commands read and write git objects only. They leave the branch that is checked out there, and its working tree, as they are:

```bash
git -C ../lattice remote get-url origin
git -C ../lattice fetch origin
git -C ../lattice tag hedera-template-pin-6c8db45 6c8db45aa46986af2edb6a0d8fb02a4a92faef01
git -C ../lattice push origin hedera-template-pin-6c8db45
git ls-remote --tags https://github.com/dadadave80/lattice hedera-template-pin-6c8db45
```

Expected: the first command names `dadadave80/lattice`, and the last prints one line, `6c8db45aa46986af2edb6a0d8fb02a4a92faef01	refs/tags/hedera-template-pin-6c8db45`. Tag this commit even if the branch has moved on: every listing in this plan was verified against it. On 4 October at 01:50 UTC `feat/hedera-system-contract-modules` still pointed at this commit and the tag did not exist yet.

If `../lattice` is missing, or its `origin` is another repository, create the same tag through GitHub instead, then run the `git ls-remote` line:

```bash
gh api repos/dadadave80/lattice/git/refs \
  -f ref=refs/tags/hedera-template-pin-6c8db45 -f sha=6c8db45aa46986af2edb6a0d8fb02a4a92faef01
```

Swap the libraries:

```bash
cd packages/foundry
forge remove openzeppelin-contracts solidity-bytes-utils hedera-forking --force
forge install dadadave80/lattice@hedera-template-pin-6c8db45
```

Expected: `Installed lattice tag=hedera-template-pin-6c8db45@6c8db45aa46986af2edb6a0d8fb02a4a92faef01`.

`forge remove` leaves the removed libraries in `foundry.lock`, and adds a stray `packages/foundry/lib/forge-std` key. Write the file out exactly:

Replace the whole of `packages/foundry/foundry.lock` with:

```json
{
  "lib/forge-std": {
    "tag": {
      "name": "v1.15.0",
      "rev": "0844d7e1fc5e60d77b68e469bff60265f236c398"
    }
  },
  "lib/lattice": {
    "tag": {
      "name": "hedera-template-pin-6c8db45",
      "rev": "6c8db45aa46986af2edb6a0d8fb02a4a92faef01"
    }
  }
}
```

Replace the whole of `packages/foundry/remappings.txt` with:

```text
forge-std/=lib/forge-std/src/
@lattice/=lib/lattice/src/
@lattice-script/=lib/lattice/script/
@lattice-test/=lib/lattice/test/
@diamond/=lib/lattice/lib/diamond-lib/src/
```

Edit `packages/foundry/foundry.toml`.

Edit 1 of 2. After:

```toml
libs = ['lib']
```

insert:

```toml
# Lattice is developed against this compiler. Pinning it (with the optimizer settings below) keeps facet
# bytecode identical for everyone who scaffolds this template, so facets land on the same deterministic
# addresses and are reused instead of redeployed.
solc = "0.8.36"
optimizer = true
optimizer_runs = 200
```

Edit 2 of 2. Replace:

```toml
evm_version = "cancun"

# Suppress style lints for API/modifier names we don't control
[lint]
exclude_lints = ["mixed-case-variable", "mixed-case-function"]
```

with:

```toml
evm_version = "cancun"
# Lattice and forge-std are pinned dependencies; their compiler warnings are not this project's to fix.
ignored_warnings_from = ["lib"]

# Suppress style lints for API/modifier names we don't control, and one that mistakes Lattice's library
# calls (AccessControlLib.checkRole) for external calls.
[lint]
exclude_lints = ["mixed-case-variable", "mixed-case-function", "reentrancy-events"]
# Lint the contracts that get deployed. Tests and scripts lean on cheatcodes the linter flags by design.
ignore = ["test/**/*.sol", "script/**/*.sol", "contracts/LatticeFacets.sol"]
```

**Step 4: Run test to verify it passes**

Run:

```bash
(cd packages/foundry && forge build) && bash scripts/gate.sh static | grep 'Forge library'
```

Expected: PASS. `Compiler run successful!`, then `PASS  every Forge library in remappings.txt is pinned in .gitmodules and foundry.lock`.

**Step 5: Commit**

```bash
git add .gitmodules packages/foundry
git commit -m "build: depend on Lattice instead of the stock libraries"
```

---

## Phase 1: The diamond and the sale facet

### Task 5: Build the diamond's base from the recipe

**Files:**
- Test: `packages/foundry/test/fixtures/default.recipe.json`
- Test: `packages/foundry/test/DeployDiamond.t.sol`
- Delete: `packages/foundry/test/.gitkeep`
- Create: `packages/foundry/diamond.recipe.json`
- Create: `packages/foundry/script/DeployDiamond.s.sol`

The deploy script is the only thing that knows how the diamond is put together, and the tests build their diamonds through it, so it comes first. This version reads the recipe's facet list and its init steps, treating every step as `init(admin)`, and appends `HTSAdapter`. That is all the default recipe needs. The other recipe fields arrive in Tasks 31 to 33.

`_facet`, `_cut` and `_assembleMulti` come from Lattice's `BaseDeploy`: `_facet` deploys a Lattice facet by name at a deterministic address, `_cut` reads the facet's own `exportSelectors()`, and `_assembleMulti` creates and initializes the diamond in one transaction.

**Step 1: Write the failing test**

The default recipe, frozen as a fixture. Tests read this copy so that they keep passing after a developer customizes the project's own recipe.

Create `packages/foundry/test/fixtures/default.recipe.json`:

```json
{
  "$schema": "https://lattice-studio.invalid/schema/recipe.v1.json",
  "schemaVersion": 1,
  "name": "Hedera diamond base",
  "catalog": {
    "tag": "dev-f4a32c8",
    "hash": "0x2ab42999bbfac307417b4265a7e9dbb8e004a8473bc9fc532b9bf33efa1d20c1"
  },
  "facets": [
    "ChainlinkAdapter",
    "AccessControlDiamondCut",
    "EmergencyStop",
    "AccessControl",
    "Receive",
    "DiamondLoupeFacet",
    "ERC165Facet"
  ],
  "owners": {},
  "exclude": [],
  "init": {
    "kind": "steps",
    "steps": [
      {
        "spec": "ChainlinkAdapterInit",
        "args": {
          "admin": {
            "$ref": "deployer"
          }
        }
      }
    ]
  }
}
```

Create `packages/foundry/test/DeployDiamond.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { MultiInit } from "@diamond/initializers/MultiInit.sol";
import { IDiamondLoupe } from "@diamond/interfaces/IDiamondLoupe.sol";
import { Facet, FacetCut } from "@diamond/libraries/DiamondLib.sol";
import { Lattice } from "@lattice/Lattice.sol";
import { IAccessControl } from "@lattice/interfaces/access/IAccessControl.sol";
import { IHTSAdapter } from "@lattice/interfaces/tokens/IHTSAdapter.sol";
import { Test } from "forge-std/Test.sol";
import { DeployDiamond } from "../script/DeployDiamond.s.sol";

contract DeployDiamondTest is Test {
    address internal admin = makeAddr("admin");
    DeployDiamond internal deployer;
    string internal recipe;

    function setUp() public {
        deployer = new DeployDiamond();
        recipe = vm.readFile("test/fixtures/default.recipe.json");
    }

    /// @dev The one test that reads your own `diamond.recipe.json`. It stays green as long as that file builds.
    function test_projectRecipe_buildsADiamondWithTheHederaLayer() public {
        (address diamond,,) = _diamond(vm.readFile("diamond.recipe.json"));

        assertTrue(
            IDiamondLoupe(diamond).facetAddress(IHTSAdapter.createFungibleToken.selector) != address(0), "HTSAdapter"
        );
    }

    function test_defaultRecipe_buildsTheBaseAndTheHederaLayer() public {
        (address diamond, string[] memory names, FacetCut[] memory cuts) = _diamond(recipe);

        assertEq(names.length, 8, "seven base facets and HTSAdapter");
        assertEq(names[7], "HTSAdapter");

        Facet[] memory facets = IDiamondLoupe(diamond).facets();
        assertEq(facets.length, 8);

        uint256 baseSelectors;
        for (uint256 i; i < cuts.length; ++i) {
            if (i < 7) baseSelectors += cuts[i].functionSelectors.length;
            for (uint256 j; j < cuts[i].functionSelectors.length; ++j) {
                assertEq(
                    IDiamondLoupe(diamond).facetAddress(cuts[i].functionSelectors[j]),
                    cuts[i].facetAddress,
                    string.concat("a ", names[i], " selector is routed elsewhere")
                );
            }
        }
        assertEq(baseSelectors, 24, "the selector count Lattice Studio plans for the default base");
    }

    function test_defaultRecipe_makesTheAdminTheAdminOfEveryLayer() public {
        (address diamond,,) = _diamond(recipe);

        assertTrue(IAccessControl(diamond).hasRole(bytes32(0), admin), "DEFAULT_ADMIN_ROLE");
        assertTrue(IAccessControl(diamond).hasRole(keccak256("HTS_MANAGER_ROLE"), admin), "HTS_MANAGER_ROLE");
    }

    /// @dev Initializes a diamond from one `build`, so the returned cuts are the ones the diamond was made from.
    function _diamond(string memory json)
        internal
        returns (address diamond, string[] memory names, FacetCut[] memory cuts)
    {
        address[] memory inits;
        bytes[] memory calls;
        (names, cuts, inits, calls) = deployer.build(json, admin);
        Lattice lattice = new Lattice();
        lattice.initialize(cuts, address(new MultiInit()), abi.encodeCall(MultiInit.multiInit, (inits, calls)));
        diamond = address(lattice);
    }
}
```

```bash
git rm packages/foundry/test/.gitkeep
```

**Step 2: Run test to verify it fails**

Run: `(cd packages/foundry && forge test --match-contract DeployDiamondTest)`

Expected: FAIL. The test imports `script/DeployDiamond.s.sol`, which does not exist.

```text
Error (6275): Source "script/DeployDiamond.s.sol" not found: File not found. Searched the following locations: "<repo>/packages/foundry".
```

**Step 3: Write minimal implementation**

The project's own recipe starts as the same file:

Create `packages/foundry/diamond.recipe.json`:

```json
{
  "$schema": "https://lattice-studio.invalid/schema/recipe.v1.json",
  "schemaVersion": 1,
  "name": "Hedera diamond base",
  "catalog": {
    "tag": "dev-f4a32c8",
    "hash": "0x2ab42999bbfac307417b4265a7e9dbb8e004a8473bc9fc532b9bf33efa1d20c1"
  },
  "facets": [
    "ChainlinkAdapter",
    "AccessControlDiamondCut",
    "EmergencyStop",
    "AccessControl",
    "Receive",
    "DiamondLoupeFacet",
    "ERC165Facet"
  ],
  "owners": {},
  "exclude": [],
  "init": {
    "kind": "steps",
    "steps": [
      {
        "spec": "ChainlinkAdapterInit",
        "args": {
          "admin": {
            "$ref": "deployer"
          }
        }
      }
    ]
  }
}
```

Create `packages/foundry/script/DeployDiamond.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { FacetCut } from "@diamond/libraries/DiamondLib.sol";
import { BaseDeploy } from "@lattice-script/base/BaseDeploy.s.sol";
import { HTSAdapterInit } from "@lattice/tokens/hedera/HTSAdapterInit.sol";
import { DiamondIntrospectionInit } from "@lattice/utils/DiamondIntrospectionInit.sol";

// A facet is deployed by name from its compiled artifact, and Foundry compiles only what something imports.
// Importing the wiring file here makes every wired facet part of any build that includes this script.
import "../contracts/LatticeFacets.sol";

/// @title DeployDiamond
/// @notice Builds this project's diamond in two layers and deploys it in one transaction.
///         - The Lattice base comes from `diamond.recipe.json`, a file in Lattice Studio's recipe format.
///           Change the base by editing that file (or exporting over it from Studio), never by editing cuts here.
///         - The Hedera layer is fixed below: `HTSAdapter`. It stays out of the recipe because Studio's
///           catalog does not carry the Hedera facets yet.
/// @dev `build` and `assemble` take the recipe as a string and never broadcast, so tests call them directly.
contract DeployDiamond is BaseDeploy {
    /// @dev How many facets and initializers the Hedera layer appends to the recipe's.
    uint256 internal constant HEDERA_FACETS = 1;
    uint256 internal constant HEDERA_INITS = 2;

    /// @notice Deploys the diamond described by `json` plus the Hedera layer, with `admin` holding every role.
    function assemble(string memory json, address admin) public returns (address diamond) {
        (, FacetCut[] memory cuts, address[] memory inits, bytes[] memory calls) = build(json, admin);
        diamond = _assembleMulti(cuts, inits, calls);
    }

    /// @notice The facet cuts and initializer calls for the recipe's base plus the Hedera layer.
    /// @return names The facet name behind each cut, in cut order.
    function build(string memory json, address admin)
        public
        returns (string[] memory names, FacetCut[] memory cuts, address[] memory inits, bytes[] memory calls)
    {
        string[] memory base = _facetNames(json);
        names = new string[](base.length + HEDERA_FACETS);
        cuts = new FacetCut[](base.length + HEDERA_FACETS);
        for (uint256 i; i < base.length; ++i) {
            names[i] = base[i];
            cuts[i] = _cut(_facet(base[i]));
        }
        names[base.length] = "HTSAdapter";
        cuts[base.length] = _cut(_facet("HTSAdapter"));

        uint256 steps = _stepCount(json);
        inits = new address[](steps + HEDERA_INITS);
        calls = new bytes[](steps + HEDERA_INITS);
        for (uint256 i; i < steps; ++i) {
            (inits[i], calls[i]) = _initStep(json, i, admin);
        }
        inits[steps] = address(new HTSAdapterInit());
        calls[steps] = abi.encodeCall(HTSAdapterInit.init, (admin));
        inits[steps + 1] = address(new DiamondIntrospectionInit());
        calls[steps + 1] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    // ── recipe reading ──────────────────────────────────────────────────────────────────────────────

    function _facetNames(string memory json) internal pure returns (string[] memory) {
        return vm.parseJsonStringArray(json, ".facets");
    }

    function _stepCount(string memory json) internal view returns (uint256 n) {
        while (vm.keyExistsJson(json, string.concat(".init.steps[", vm.toString(n), "]"))) {
            ++n;
        }
    }

    /// @dev Every initializer the recipe lists is called as `init(admin)`.
    function _initStep(string memory json, uint256 i, address admin)
        internal
        returns (address init, bytes memory data)
    {
        string memory spec = vm.parseJsonString(json, string.concat(".init.steps[", vm.toString(i), "].spec"));
        init = deployCode(string.concat(spec, ".sol:", spec));
        data = abi.encodeWithSignature("init(address)", admin);
    }
}
```

**Step 4: Run test to verify it passes**

Run: `(cd packages/foundry && forge test --match-contract DeployDiamondTest)`

Expected: PASS. Three tests pass.

```text
Suite result: ok. 3 passed; 0 failed; 0 skipped; finished in 10.54ms (12.95ms CPU time)
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: build the diamond's Lattice base from a Lattice Studio recipe"
```

---

### Task 6: Cut a TokenSale facet into the diamond

**Files:**
- Test: `packages/foundry/test/SaleTestBase.sol`
- Test: `packages/foundry/test/TokenSale.t.sol`
- Test: `packages/foundry/test/DeployDiamond.t.sol`
- Create: `packages/foundry/contracts/interfaces/ITokenSale.sol`
- Create: `packages/foundry/contracts/libraries/TokenSaleLib.sol`
- Create: `packages/foundry/contracts/TokenSale.sol`
- Create: `packages/foundry/contracts/TokenSaleInit.sol`
- Modify: `packages/foundry/script/DeployDiamond.s.sol`

A Lattice module is three files: an interface, a library that owns the logic and an ERC-7201 storage struct, and a stateless facet that forwards to the library. This task creates all three with one function, `saleInfo()`, plus the initializer, and adds the facet to the Hedera layer. The storage struct is complete from the start because its layout is the one thing an upgrade can never change.

`test_exportSelectors_matchesTheAbi` compares the facet's `exportSelectors()` with its compiled ABI. From here on, adding a function without exporting its selector fails that test.

**Step 1: Write the failing test**

Create `packages/foundry/test/SaleTestBase.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { MockHederaTokenService } from "@lattice-test/mocks/hedera/MockHederaTokenService.sol";
import { HTS_SYSTEM_CONTRACT } from "@lattice/tokens/hedera/HTSAdapterLib.sol";
import { Test } from "forge-std/Test.sol";
import { ITokenSale } from "../contracts/interfaces/ITokenSale.sol";
import { DeployDiamond } from "../script/DeployDiamond.s.sol";

/// @notice Builds the production diamond through the deploy script, with Lattice's HTS mock etched at 0x167.
///         Everything a test calls goes through the diamond, exactly as it does on Hedera.
/// @dev Uses the default recipe frozen in `test/fixtures`, not your `diamond.recipe.json`, so these tests keep
///      passing after you customize the diamond's base.
abstract contract SaleTestBase is Test {
    bytes32 internal constant HBAR_USD = "HBAR/USD";
    uint256 internal constant ONE_HBAR = 1e8; // tinybars, the unit of msg.value inside Hedera's EVM

    address internal admin = makeAddr("admin");
    address internal buyer = makeAddr("buyer");

    DeployDiamond internal deployer;
    address internal diamond;
    ITokenSale internal sale;

    function setUp() public virtual {
        vm.etch(HTS_SYSTEM_CONTRACT, address(new MockHederaTokenService()).code);

        deployer = new DeployDiamond();
        diamond = deployer.assemble(vm.readFile("test/fixtures/default.recipe.json"), admin);
        sale = ITokenSale(diamond);

        vm.deal(admin, 100 * ONE_HBAR);
        vm.deal(buyer, 100 * ONE_HBAR);
    }
}
```

Create `packages/foundry/test/TokenSale.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { TokenSale } from "../contracts/TokenSale.sol";
import { TOKEN_SALE_STORAGE_SLOT } from "../contracts/libraries/TokenSaleLib.sol";
import { SaleTestBase } from "./SaleTestBase.sol";

contract TokenSaleTest is SaleTestBase {
    function test_saleInfo_startsWithTheFeedKeyAndNoToken() public view {
        (address token,,, bytes32 feedKey, int64 sold, uint256 raised) = sale.saleInfo();

        assertEq(token, address(0), "no token before launch");
        assertEq(feedKey, HBAR_USD, "TokenSaleInit stored the feed key");
        assertEq(sold, 0);
        assertEq(raised, 0);
    }

    function test_storageSlot_followsErc7201() public pure {
        bytes32 expected = keccak256(abi.encode(uint256(keccak256("lattice-hedera-template.storage.TokenSale")) - 1))
            & ~bytes32(uint256(0xff));
        assertEq(TOKEN_SALE_STORAGE_SLOT, expected);
    }

    function test_exportSelectors_matchesTheAbi() public {
        _assertExportsItsAbi("TokenSale", new TokenSale().exportSelectors());
    }

    /// @dev Every function in `name`'s ABI except `exportSelectors()` must be exported, and nothing else.
    function _assertExportsItsAbi(string memory name, bytes memory exported) internal view {
        string memory artifact = vm.readFile(string.concat("out/", name, ".sol/", name, ".json"));
        string[] memory signatures = vm.parseJsonKeys(artifact, ".methodIdentifiers");

        assertEq(exported.length, (signatures.length - 1) * 4, "one selector per ABI function");
        for (uint256 i; i < signatures.length; ++i) {
            bytes4 selector = bytes4(keccak256(bytes(signatures[i])));
            if (selector == TokenSale.exportSelectors.selector) continue;
            assertTrue(_contains(exported, selector), string.concat(signatures[i], " is not exported"));
        }
    }

    function _contains(bytes memory packed, bytes4 selector) internal pure returns (bool) {
        for (uint256 i; i < packed.length; i += 4) {
            bytes4 chunk;
            assembly ("memory-safe") {
                chunk := mload(add(add(packed, 0x20), i))
            }
            if (chunk == selector) return true;
        }
        return false;
    }
}
```

Edit `packages/foundry/test/DeployDiamond.t.sol`.

Edit 1 of 4. After:

```solidity
import { Test } from "forge-std/Test.sol";
```

insert:

```solidity
import { ITokenSale } from "../contracts/interfaces/ITokenSale.sol";
```

Edit 2 of 4. After:

```solidity
        (address diamond,,) = _diamond(vm.readFile("diamond.recipe.json"));
```

insert:

```solidity
        assertTrue(IDiamondLoupe(diamond).facetAddress(ITokenSale.saleInfo.selector) != address(0), "TokenSale");
```

Edit 3 of 4. Replace:

```solidity
        assertEq(names.length, 8, "seven base facets and HTSAdapter");
        assertEq(names[7], "HTSAdapter");

        Facet[] memory facets = IDiamondLoupe(diamond).facets();
        assertEq(facets.length, 8);
```

with:

```solidity
        assertEq(names.length, 9, "seven base facets, HTSAdapter and TokenSale");
        assertEq(names[7], "HTSAdapter");
        assertEq(names[8], "TokenSale");

        Facet[] memory facets = IDiamondLoupe(diamond).facets();
        assertEq(facets.length, 9);
```

Edit 4 of 4. After:

```solidity
        assertTrue(IAccessControl(diamond).hasRole(keccak256("HTS_MANAGER_ROLE"), admin), "HTS_MANAGER_ROLE");
```

insert:

```solidity
        (,,, bytes32 feedKey,,) = ITokenSale(diamond).saleInfo();
        assertEq(feedKey, bytes32("HBAR/USD"), "TokenSaleInit ran");
```

**Step 2: Run test to verify it fails**

Run: `(cd packages/foundry && forge test)`

Expected: FAIL. The tests import `contracts/TokenSale.sol` and `contracts/interfaces/ITokenSale.sol`, which do not exist. Forge names one importing file per missing import and does not always pick the same one: in the second replay the last line named `test/SaleTestBase.sol`. Either is the expected failure.

```text
Unable to resolve imports:
"../contracts/TokenSale.sol" in "<repo>/packages/foundry/test/TokenSale.t.sol"
"../contracts/interfaces/ITokenSale.sol" in "<repo>/packages/foundry/test/DeployDiamond.t.sol"
```

**Step 3: Write minimal implementation**

Create `packages/foundry/contracts/interfaces/ITokenSale.sol`:

```solidity
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
```

Create `packages/foundry/contracts/libraries/TokenSaleLib.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { InitializableLib } from "@lattice/utils/libraries/InitializableLib.sol";

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice-hedera-template.storage.TokenSale")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant TOKEN_SALE_STORAGE_SLOT = 0x6e569de6c6a1948b3edf921eb24b1102436ae1d4a44d5296089020d12a122800;

/// @notice ERC-7201 namespaced storage for TokenSale. Append new fields at the end; never reorder.
/// @custom:storage-location erc7201:lattice-hedera-template.storage.TokenSale
struct TokenSaleStorage {
    address token;
    int32 decimals;
    int64 sold;
    bytes32 feedKey;
    uint256 priceUsd;
    uint256 raised;
}

/// @title TokenSaleLib
/// @notice Logic and storage for the TokenSale facet. The facet is a stateless forwarder, which is the Lattice
///         module pattern: an upgrade swaps the facet while this storage stays where it is.
library TokenSaleLib {
    function tokenSaleStorage() internal pure returns (TokenSaleStorage storage $) {
        assembly {
            $.slot := TOKEN_SALE_STORAGE_SLOT
        }
    }

    /// @notice Stores the oracle feed key. Runs once, inside the diamond's initializing window.
    function __TokenSale_init(bytes32 feedKey) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        tokenSaleStorage().feedKey = feedKey;
    }
}
```

Create `packages/foundry/contracts/TokenSale.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ITokenSale } from "./interfaces/ITokenSale.sol";
import { TokenSaleLib, TokenSaleStorage } from "./libraries/TokenSaleLib.sol";

/// @title TokenSale
/// @notice Diamond facet that sells the diamond's own HTS token for HBAR at a USD price.
/// @dev Stateless: every function forwards to TokenSaleLib. Cut it into a diamond that also carries
///      `HTSAdapter`, `AccessControl` and a price-feed facet such as `ChainlinkAdapter`.
contract TokenSale is ITokenSale {
    /// @inheritdoc ITokenSale
    function saleInfo()
        external
        view
        virtual
        returns (address token, int32 decimals, uint256 priceUsd, bytes32 feedKey, int64 sold, uint256 raised)
    {
        TokenSaleStorage storage $ = TokenSaleLib.tokenSaleStorage();
        return ($.token, $.decimals, $.priceUsd, $.feedKey, $.sold, $.raised);
    }

    /// @notice ERC-8153: the selectors this facet adds to a diamond, 4 bytes each.
    /// @dev Never includes `exportSelectors()` itself. `test/TokenSale.t.sol` checks this list against the ABI.
    ///      `saleInfo()` 0x8e3695b8
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"8e3695b8";
    }
}
```

Create `packages/foundry/contracts/TokenSaleInit.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { TokenSaleLib } from "./libraries/TokenSaleLib.sol";

/// @title TokenSaleInit
/// @notice Initializer for the TokenSale facet. The diamond delegatecalls it once, while it is being created.
contract TokenSaleInit {
    /// @param feedKey The key the sale passes to the diamond's `latestAnswer(bytes32)` for the HBAR/USD rate.
    function init(bytes32 feedKey) external {
        TokenSaleLib.__TokenSale_init(feedKey);
    }
}
```

Edit `packages/foundry/script/DeployDiamond.s.sol`.

Edit 1 of 4. After:

```solidity
import { DiamondIntrospectionInit } from "@lattice/utils/DiamondIntrospectionInit.sol";
```

insert:

```solidity
import { TokenSale } from "../contracts/TokenSale.sol";
import { TokenSaleInit } from "../contracts/TokenSaleInit.sol";
```

Edit 2 of 4. Replace:

```solidity
///         - The Hedera layer is fixed below: `HTSAdapter`. It stays out of the recipe because Studio's
///           catalog does not carry the Hedera facets yet.
/// @dev `build` and `assemble` take the recipe as a string and never broadcast, so tests call them directly.
contract DeployDiamond is BaseDeploy {
    /// @dev How many facets and initializers the Hedera layer appends to the recipe's.
    uint256 internal constant HEDERA_FACETS = 1;
    uint256 internal constant HEDERA_INITS = 2;
```

with:

```solidity
///         - The Hedera layer is fixed below: `HTSAdapter` and this project's `TokenSale` facet. It stays out
///           of the recipe because Studio's catalog does not carry the Hedera facets yet.
/// @dev `build` and `assemble` take the recipe as a string and never broadcast, so tests call them directly.
contract DeployDiamond is BaseDeploy {
    /// @dev The key the sale reads its HBAR/USD rate under, on whichever oracle facet the recipe cuts.
    bytes32 internal constant HBAR_USD = "HBAR/USD";

    /// @dev How many facets and initializers the Hedera layer appends to the recipe's.
    uint256 internal constant HEDERA_FACETS = 2;
    uint256 internal constant HEDERA_INITS = 3;
```

Edit 3 of 4. After:

```solidity
        cuts[base.length] = _cut(_facet("HTSAdapter"));
```

insert:

```solidity
        names[base.length + 1] = "TokenSale";
        cuts[base.length + 1] = _cut(address(new TokenSale()));
```

Edit 4 of 4. Replace:

```solidity
        inits[steps + 1] = address(new DiamondIntrospectionInit());
        calls[steps + 1] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
```

with:

```solidity
        inits[steps + 1] = address(new TokenSaleInit());
        calls[steps + 1] = abi.encodeCall(TokenSaleInit.init, (HBAR_USD));
        inits[steps + 2] = address(new DiamondIntrospectionInit());
        calls[steps + 2] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
```

**Step 4: Run test to verify it passes**

Run: `(cd packages/foundry && forge test)`

Expected: PASS. Six tests pass: three in `TokenSaleTest`, three in `DeployDiamondTest`.

```text
Ran 2 test suites in 14.23ms (21.91ms CPU time): 6 tests passed, 0 failed, 0 skipped (6 total tests)
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: add the TokenSale facet skeleton and cut it into the diamond"
```

---

### Task 7: Explain a recipe that cannot be built

**Files:**
- Test: `packages/foundry/test/DeployDiamond.t.sol`
- Modify: `packages/foundry/script/DeployDiamond.s.sol`

A developer will edit the recipe by hand or export one from Studio that this project cannot build. Each case must stop before anything is deployed, with a message that says what to change. The README's error table quotes these messages word for word.

**Step 1: Write the failing test**

Edit `packages/foundry/test/DeployDiamond.t.sol`.

After:

```solidity
        assertEq(feedKey, bytes32("HBAR/USD"), "TokenSaleInit ran");
    }
```

insert:

```solidity

    function test_build_revertsWhenAFacetIsNotCompiledIn() public {
        string memory json = vm.replace(recipe, '"ERC165Facet"', '"ERC165Facet", "RateLimiter"');

        vm.expectRevert(
            bytes(
                "Recipe: RateLimiter is in the recipe but not compiled into this project; add its import to contracts/LatticeFacets.sol"
            )
        );
        deployer.build(json, admin);
    }

    function test_build_revertsWhenAFacetIsNotALatticeFacet() public {
        // TokenSale is compiled into the project, but it is this project's facet, not one of Lattice's.
        string memory json = vm.replace(recipe, '"ERC165Facet"', '"ERC165Facet", "TokenSale"');

        vm.expectRevert(bytes("BaseDeploy: TokenSale is not in FacetInventory"));
        deployer.build(json, admin);
    }

    function test_build_revertsOnAFileThatIsNotARecipe() public {
        vm.expectRevert(bytes("Recipe: diamond.recipe.json must be valid JSON with a 'facets' list of facet names"));
        deployer.build("{}", admin);
    }
```

**Step 2: Run test to verify it fails**

Run: `(cd packages/foundry && forge test --match-contract DeployDiamondTest)`

Expected: FAIL. Two of the three new tests fail, because the script still lets Foundry's own errors through. `test_build_revertsWhenAFacetIsNotALatticeFacet` passes already: that message comes from Lattice's `BaseDeploy`. The test pins it because the README quotes it.

```text
[FAIL: Error != expected error: vm.parseJsonStringArray: path ".facets" must return exactly one JSON value != Recipe: diamond.recipe.json must be valid JSON with a 'facets' list of facet names] test_build_revertsOnAFileThatIsNotARecipe() (gas: 11788)
[PASS] test_build_revertsWhenAFacetIsNotALatticeFacet() (gas: 3740703)
[FAIL: Error != expected error: vm.getCode: no matching artifact found != Recipe: RateLimiter is in the recipe but not compiled into this project; add its import to contracts/LatticeFacets.sol] test_build_revertsWhenAFacetIsNotCompiledIn() (gas: 3734066)
Suite result: FAILED. 4 passed; 2 failed; 0 skipped; finished in 13.12ms (19.51ms CPU time)
```

**Step 3: Write minimal implementation**

Edit `packages/foundry/script/DeployDiamond.s.sol`.

Edit 1 of 3. After:

```solidity
        for (uint256 i; i < base.length; ++i) {
```

insert:

```solidity
            _requireWired(base[i]);
```

Edit 2 of 3. Replace:

```solidity
        return vm.parseJsonStringArray(json, ".facets");
```

with:

```solidity
        try vm.parseJsonStringArray(json, ".facets") returns (string[] memory names) {
            return names;
        } catch {
            revert("Recipe: diamond.recipe.json must be valid JSON with a 'facets' list of facet names");
        }
```

Edit 3 of 3. After:

```solidity
        data = abi.encodeWithSignature("init(address)", admin);
    }
```

insert:

```solidity

    /// @dev A facet can only be deployed by name if `contracts/LatticeFacets.sol` compiled it into this project.
    function _requireWired(string memory name) internal view {
        require(
            vm.exists(string.concat("out/", name, ".sol/", name, ".json")),
            string.concat(
                "Recipe: ",
                name,
                " is in the recipe but not compiled into this project; add its import to contracts/LatticeFacets.sol"
            )
        );
    }
```

**Step 4: Run test to verify it passes**

Run: `(cd packages/foundry && forge test --match-contract DeployDiamondTest)`

Expected: PASS. Six tests pass.

```text
Suite result: ok. 6 passed; 0 failed; 0 skipped; finished in 18.60ms (28.74ms CPU time)
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: explain a recipe the deploy script cannot build"
```

---

### Task 8: Create the sale token through HTS

**Files:**
- Test: `packages/foundry/test/SaleTestBase.sol`
- Test: `packages/foundry/test/TokenSale.t.sol`
- Modify: `packages/foundry/contracts/interfaces/ITokenSale.sol`
- Modify: `packages/foundry/contracts/libraries/TokenSaleLib.sol`
- Modify: `packages/foundry/contracts/TokenSale.sol`

`launchSale` is the admin's one call that creates the HTS token, with the diamond as treasury, and sets the price. It reuses `HTSAdapterLib.createFungibleToken`, so the token is created exactly as the `HTSAdapter` facet would create it, with `delegatableContractId` keys that work from inside a diamond. `HTSAdapterLib` checks `HTS_MANAGER_ROLE`; `launchSale` adds `DEFAULT_ADMIN_ROLE`.

**Step 1: Write the failing test**

Edit `packages/foundry/test/SaleTestBase.sol`.

Edit 1 of 3. After:

```solidity
    uint256 internal constant ONE_HBAR = 1e8; // tinybars, the unit of msg.value inside Hedera's EVM
```

insert:

```solidity
    int64 internal constant ONE_TOKEN = 1e8; // the sale token has 8 decimals
    int64 internal constant SUPPLY = 1_000_000 * ONE_TOKEN;
    uint256 internal constant PRICE_USD = 0.05e18; // $0.05 per token
    uint256 internal constant CREATION_FEE = 20 * ONE_HBAR;
```

Edit 2 of 3. Before:

```solidity
    DeployDiamond internal deployer;
```

insert:

```solidity
    MockHederaTokenService internal hts = MockHederaTokenService(payable(HTS_SYSTEM_CONTRACT));
```

Edit 3 of 3. After:

```solidity
        vm.deal(buyer, 100 * ONE_HBAR);
    }
```

insert:

```solidity

    function _launch() internal returns (address token) {
        vm.prank(admin);
        token = sale.launchSale{ value: CREATION_FEE }("Lattice Sale Token", "LST", "", 8, SUPPLY, PRICE_USD);
    }
```

Edit `packages/foundry/test/TokenSale.t.sol`.

Edit 1 of 2. Replace:

```solidity
import { TokenSale } from "../contracts/TokenSale.sol";
```

with:

```solidity
import { IAccessControl } from "@lattice/interfaces/access/IAccessControl.sol";
import { IHTSAdapter } from "@lattice/interfaces/tokens/IHTSAdapter.sol";
import { TokenSale } from "../contracts/TokenSale.sol";
import { ITokenSale } from "../contracts/interfaces/ITokenSale.sol";
```

Edit 2 of 2. After:

```solidity
        assertEq(raised, 0);
    }
```

insert:

```solidity

    function test_launchSale_createsATokenTheDiamondTreasuries() public {
        address token = _launch();

        assertEq(IHTSAdapter(diamond).createdTokens()[0], token, "created through HTSAdapter's storage");
        assertEq(hts.treasury(token), diamond, "diamond is the treasury");
        assertEq(hts.balanceOf(token, diamond), SUPPLY, "supply minted to the diamond");

        (address saleToken, int32 decimals, uint256 priceUsd, bytes32 feedKey, int64 sold, uint256 raised) =
            sale.saleInfo();
        assertEq(saleToken, token);
        assertEq(decimals, 8);
        assertEq(priceUsd, PRICE_USD);
        assertEq(feedKey, HBAR_USD);
        assertEq(sold, 0);
        assertEq(raised, 0);
    }

    function test_launchSale_revertsForAnyoneButTheAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, buyer, bytes32(0))
        );
        vm.prank(buyer);
        sale.launchSale{ value: CREATION_FEE }("Lattice Sale Token", "LST", "", 8, SUPPLY, PRICE_USD);
    }

    function test_launchSale_revertsASecondTime() public {
        address token = _launch();

        vm.expectRevert(abi.encodeWithSelector(ITokenSale.TokenSaleAlreadyLaunched.selector, token));
        vm.prank(admin);
        sale.launchSale{ value: CREATION_FEE }("Second Token", "SEC", "", 8, SUPPLY, PRICE_USD);
    }

    function test_launchSale_revertsOnBadInput() public {
        vm.startPrank(admin);
        vm.expectRevert(ITokenSale.TokenSaleInvalidPrice.selector);
        sale.launchSale{ value: CREATION_FEE }("Lattice Sale Token", "LST", "", 8, SUPPLY, 0);

        vm.expectRevert(abi.encodeWithSelector(ITokenSale.TokenSaleInvalidDecimals.selector, int32(19)));
        sale.launchSale{ value: CREATION_FEE }("Lattice Sale Token", "LST", "", 19, SUPPLY, PRICE_USD);
        vm.stopPrank();
    }
```

**Step 2: Run test to verify it fails**

Run: `(cd packages/foundry && forge test --match-contract TokenSaleTest)`

Expected: FAIL. Compilation stops: `ITokenSale` has no `launchSale`.

```text
Error (9582): Member "launchSale" not found or not visible after argument-dependent lookup in contract ITokenSale.
```

**Step 3: Write minimal implementation**

Edit `packages/foundry/contracts/interfaces/ITokenSale.sol`.

After:

```solidity
interface ITokenSale {
```

insert (the block ends with an empty line; keep it):

```solidity
    /// @notice Emitted once, when the sale token is created and its price set.
    event SaleLaunched(address indexed token, int32 decimals, int64 supply, uint256 priceUsd);

    /// @notice `launchSale` was called on a diamond that already sells `token`.
    error TokenSaleAlreadyLaunched(address token);
    /// @notice A price of zero, or an oracle answer that is not positive.
    error TokenSaleInvalidPrice();
    /// @notice Token decimals outside 0..18.
    error TokenSaleInvalidDecimals(int32 decimals);

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

```

Edit `packages/foundry/contracts/libraries/TokenSaleLib.sol`.

Edit 1 of 2. Replace:

```solidity
import { InitializableLib } from "@lattice/utils/libraries/InitializableLib.sol";
```

with:

```solidity
import { AccessControlLib, DEFAULT_ADMIN_ROLE } from "@lattice/access/libraries/AccessControlLib.sol";
import { HTSAdapterLib } from "@lattice/tokens/hedera/HTSAdapterLib.sol";
import { InitializableLib } from "@lattice/utils/libraries/InitializableLib.sol";
import { ITokenSale } from "../interfaces/ITokenSale.sol";
```

Edit 2 of 2. After:

```solidity
        tokenSaleStorage().feedKey = feedKey;
    }
```

insert:

```solidity

    function launchSale(
        string calldata name,
        string calldata symbol,
        string calldata memo,
        int32 decimals,
        int64 supply,
        uint256 priceUsd
    ) internal returns (address token) {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        TokenSaleStorage storage $ = tokenSaleStorage();
        if ($.token != address(0)) revert ITokenSale.TokenSaleAlreadyLaunched($.token);
        if (priceUsd == 0) revert ITokenSale.TokenSaleInvalidPrice();
        if (decimals < 0 || decimals > 18) revert ITokenSale.TokenSaleInvalidDecimals(decimals);

        // The diamond becomes the token's treasury and holds its admin and supply keys. Max supply 0 means
        // the supply is not capped, so `HTSAdapter.mintToken` can restock the sale.
        token = HTSAdapterLib.createFungibleToken(name, symbol, memo, decimals, supply, 0);
        $.token = token;
        $.decimals = decimals;
        $.priceUsd = priceUsd;
        emit ITokenSale.SaleLaunched(token, decimals, supply, priceUsd);
    }
```

Edit `packages/foundry/contracts/TokenSale.sol`.

Edit 1 of 2. After:

```solidity
contract TokenSale is ITokenSale {
```

insert (the block ends with an empty line; keep it):

```solidity
    /// @inheritdoc ITokenSale
    function launchSale(
        string calldata name,
        string calldata symbol,
        string calldata memo,
        int32 decimals,
        int64 supply,
        uint256 priceUsd
    ) external payable virtual returns (address token) {
        return TokenSaleLib.launchSale(name, symbol, memo, decimals, supply, priceUsd);
    }

```

Edit 2 of 2. Replace:

```solidity
    ///      `saleInfo()` 0x8e3695b8
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"8e3695b8";
```

with:

```solidity
    ///      `launchSale(string,string,string,int32,int64,uint256)` 0xdf1d74ae
    ///      `saleInfo()` 0x8e3695b8
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"df1d74ae8e3695b8";
```

**Step 4: Run test to verify it passes**

Run: `(cd packages/foundry && forge test --match-contract TokenSaleTest)`

Expected: PASS. Seven tests pass.

```text
Suite result: ok. 7 passed; 0 failed; 0 skipped; finished in 22.40ms (2.06ms CPU time)
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: create the sale token through HTS with the diamond as treasury"
```

---

### Task 9: Quote tokens for HBAR at the oracle rate

**Files:**
- Test: `packages/foundry/test/mocks/MockAggregatorV3.sol`
- Test: `packages/foundry/test/SaleTestBase.sol`
- Test: `packages/foundry/test/TokenSale.t.sol`
- Modify: `packages/foundry/contracts/interfaces/ITokenSale.sol`
- Modify: `packages/foundry/contracts/libraries/TokenSaleLib.sol`
- Modify: `packages/foundry/contracts/TokenSale.sol`

The sale reads HBAR/USD by calling the diamond's own `latestAnswer(bytes32)`, not `ChainlinkAdapterLib` directly. Every Lattice price-feed facet serves that selector, so a recipe can swap the oracle facet without touching this one. The test base now registers a mock Chainlink feed at $0.20 per HBAR with a one-hour staleness limit.

**Step 1: Write the failing test**

Create `packages/foundry/test/mocks/MockAggregatorV3.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IAggregatorV3 } from "@lattice/interfaces/external/chainlink/IAggregatorV3.sol";

/// @notice A Chainlink price feed stand-in: 8 decimals, and an answer the test sets.
contract MockAggregatorV3 is IAggregatorV3 {
    int256 internal _answer;
    uint256 internal _updatedAt;

    function setAnswer(int256 answer) external {
        _answer = answer;
        _updatedAt = block.timestamp;
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function description() external pure returns (string memory) {
        return "HBAR / USD";
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, _answer, _updatedAt, _updatedAt, 1);
    }
}
```

Edit `packages/foundry/test/SaleTestBase.sol`.

Edit 1 of 4. After:

```solidity
import { MockHederaTokenService } from "@lattice-test/mocks/hedera/MockHederaTokenService.sol";
```

insert:

```solidity
import { IChainlinkAdapter } from "@lattice/interfaces/oracles/IChainlinkAdapter.sol";
```

Edit 2 of 4. Replace:

```solidity
import { DeployDiamond } from "../script/DeployDiamond.s.sol";

/// @notice Builds the production diamond through the deploy script, with Lattice's HTS mock etched at 0x167.
///         Everything a test calls goes through the diamond, exactly as it does on Hedera.
```

with:

```solidity
import { DeployDiamond } from "../script/DeployDiamond.s.sol";
import { MockAggregatorV3 } from "./mocks/MockAggregatorV3.sol";

/// @notice Builds the production diamond through the deploy script, with Lattice's HTS mock etched at 0x167 and
///         a mock Chainlink feed registered under the sale's key. Everything a test calls goes through the
///         diamond, exactly as it does on Hedera.
```

Edit 3 of 4. After:

```solidity
    MockHederaTokenService internal hts = MockHederaTokenService(payable(HTS_SYSTEM_CONTRACT));
```

insert:

```solidity
    MockAggregatorV3 internal feed;
```

Edit 4 of 4. After:

```solidity
        sale = ITokenSale(diamond);
```

insert:

```solidity

        feed = new MockAggregatorV3();
        feed.setAnswer(0.2e8); // 1 HBAR = $0.20
        vm.prank(admin);
        IChainlinkAdapter(diamond).registerFeed(HBAR_USD, address(feed), 1 hours);
```

Edit `packages/foundry/test/TokenSale.t.sol`.

Edit 1 of 2. After:

```solidity
import { IAccessControl } from "@lattice/interfaces/access/IAccessControl.sol";
```

insert:

```solidity
import { IChainlinkAdapter } from "@lattice/interfaces/oracles/IChainlinkAdapter.sol";
```

Edit 2 of 2. After:

```solidity
        vm.stopPrank();
    }
```

insert:

```solidity

    function test_quote_convertsHbarToTokensAtTheOracleRate() public {
        _launch();

        // 1 HBAR is $0.20 and a token costs $0.05, so 1 HBAR buys 4 tokens.
        assertEq(sale.quote(ONE_HBAR), 4 * ONE_TOKEN);

        feed.setAnswer(0.1e8); // HBAR halves, so does what it buys
        assertEq(sale.quote(ONE_HBAR), 2 * ONE_TOKEN);
    }

    function test_quote_revertsBeforeLaunch() public {
        vm.expectRevert(ITokenSale.TokenSaleNotLaunched.selector);
        sale.quote(ONE_HBAR);
    }

    function test_quote_revertsWhenThePaymentBuysNothing() public {
        _launch();

        vm.expectRevert(ITokenSale.TokenSaleInvalidAmount.selector);
        sale.quote(0);
    }

    function test_quote_revertsOnAStaleOracleAnswer() public {
        _launch();
        skip(2 hours); // the feed was registered with a one-hour limit

        vm.expectRevert(abi.encodeWithSelector(IChainlinkAdapter.ChainlinkStaleData.selector, HBAR_USD, 1, 1 hours));
        sale.quote(ONE_HBAR);
    }
```

**Step 2: Run test to verify it fails**

Run: `(cd packages/foundry && forge test --match-contract TokenSaleTest)`

Expected: FAIL. Compilation stops: `ITokenSale` has no `quote`.

```text
Error (9582): Member "quote" not found or not visible after argument-dependent lookup in contract ITokenSale.
```

**Step 3: Write minimal implementation**

Edit `packages/foundry/contracts/interfaces/ITokenSale.sol`.

Edit 1 of 3. After:

```solidity
    error TokenSaleAlreadyLaunched(address token);
```

insert:

```solidity
    /// @notice The sale has no token yet: `launchSale` has not been called.
    error TokenSaleNotLaunched();
```

Edit 2 of 3. After:

```solidity
    error TokenSaleInvalidDecimals(int32 decimals);
```

insert:

```solidity
    /// @notice The payment buys no whole token unit, or more units than an `int64` can hold.
    error TokenSaleInvalidAmount();
```

Edit 3 of 3. After:

```solidity
    ) external payable returns (address token);
```

insert:

```solidity

    /// @notice Token units that `tinybars` buys at the current oracle rate.
    function quote(uint256 tinybars) external view returns (int64 tokens);
```

Edit `packages/foundry/contracts/libraries/TokenSaleLib.sol`.

Edit 1 of 3. After:

```solidity
bytes32 constant TOKEN_SALE_STORAGE_SLOT = 0x6e569de6c6a1948b3edf921eb24b1102436ae1d4a44d5296089020d12a122800;
```

insert:

```solidity

/// @dev Tinybars in one HBAR.
uint256 constant TINYBARS_PER_HBAR = 1e8;

/// @dev The largest amount an HTS `int64` can carry.
uint256 constant MAX_TOKEN_UNITS = 9_223_372_036_854_775_807;
```

Edit 2 of 3. After:

```solidity
    uint256 raised;
}
```

insert:

```solidity

/// @notice The read every Lattice price-feed facet serves under the same selector.
interface IPriceFeed {
    function latestAnswer(bytes32 key) external view returns (int256 answerWad);
}
```

Edit 3 of 3. After:

```solidity
        emit ITokenSale.SaleLaunched(token, decimals, supply, priceUsd);
    }
```

insert:

```solidity

    function quote(uint256 tinybars) internal view returns (int64 tokens) {
        TokenSaleStorage storage $ = tokenSaleStorage();
        return _tokensFor($, tinybars, _hbarUsd($));
    }

    /// @dev USD per HBAR, 18 decimals, read through the diamond's own `latestAnswer(bytes32)` selector rather
    ///      than from a specific adapter library. That is what lets a recipe swap the oracle facet without
    ///      touching this one.
    function _hbarUsd(TokenSaleStorage storage $) private view returns (uint256) {
        if ($.token == address(0)) revert ITokenSale.TokenSaleNotLaunched();
        int256 answer = IPriceFeed(address(this)).latestAnswer($.feedKey);
        if (answer <= 0) revert ITokenSale.TokenSaleInvalidPrice();
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(answer);
    }

    /// @dev units = tinybars * (USD per HBAR) * 10^decimals / (tinybars per HBAR * USD per token).
    ///      One division, so nothing is rounded away early. `decimals` is 0..18 and the result is
    ///      range-checked, which is what makes the casts safe.
    function _tokensFor(TokenSaleStorage storage $, uint256 tinybars, uint256 hbarUsd) private view returns (int64) {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 unit = 10 ** uint256(uint32($.decimals));
        uint256 units = (tinybars * hbarUsd * unit) / (TINYBARS_PER_HBAR * $.priceUsd);
        if (units == 0 || units > MAX_TOKEN_UNITS) revert ITokenSale.TokenSaleInvalidAmount();
        // forge-lint: disable-next-line(unsafe-typecast)
        return int64(uint64(units));
    }
```

Edit `packages/foundry/contracts/TokenSale.sol`.

Edit 1 of 2. After:

```solidity
        return TokenSaleLib.launchSale(name, symbol, memo, decimals, supply, priceUsd);
    }
```

insert:

```solidity

    /// @inheritdoc ITokenSale
    function quote(uint256 tinybars) external view virtual returns (int64 tokens) {
        return TokenSaleLib.quote(tinybars);
    }
```

Edit 2 of 2. Replace:

```solidity
    ///      `saleInfo()` 0x8e3695b8
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"df1d74ae8e3695b8";
```

with:

```solidity
    ///      `quote(uint256)` 0xed1bd76c
    ///      `saleInfo()` 0x8e3695b8
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"df1d74aeed1bd76c8e3695b8";
```

**Step 4: Run test to verify it passes**

Run: `(cd packages/foundry && forge test --match-contract TokenSaleTest)`

Expected: PASS. Eleven tests pass.

```text
Suite result: ok. 11 passed; 0 failed; 0 skipped; finished in 9.45ms (2.41ms CPU time)
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: quote tokens for HBAR at the Chainlink rate"
```

---

### Task 10: Sell tokens for HBAR

**Files:**
- Test: `packages/foundry/test/TokenSale.t.sol`
- Modify: `packages/foundry/contracts/interfaces/ITokenSale.sol`
- Modify: `packages/foundry/contracts/libraries/TokenSaleLib.sol`
- Modify: `packages/foundry/contracts/TokenSale.sol`

`buy` prices the HBAR sent, checks the buyer's minimum, records the sale and transfers the tokens out of the diamond's treasury. HTS returns a response code instead of reverting, so the code is checked and turned into a named error. Code 184 means the buyer has not associated with the token, which is the first thing a new Hedera user runs into.

**Step 1: Write the failing test**

Edit `packages/foundry/test/TokenSale.t.sol`.

Edit 1 of 2. After:

```solidity
import { IAccessControl } from "@lattice/interfaces/access/IAccessControl.sol";
```

insert:

```solidity
import { IHRC719 } from "@lattice/interfaces/external/hedera/IHRC719.sol";
```

Edit 2 of 2. Before:

```solidity

    function test_storageSlot_followsErc7201() public pure {
```

insert:

```solidity

    function test_buy_sendsTokensToTheBuyerAndKeepsTheHbar() public {
        address token = _launch();
        vm.startPrank(buyer);
        IHRC719(token).associate();

        vm.expectEmit(diamond);
        emit ITokenSale.TokensPurchased(buyer, 10 * ONE_HBAR, 40 * ONE_TOKEN, 0.2e18);
        int64 tokens = sale.buy{ value: 10 * ONE_HBAR }(40 * ONE_TOKEN);
        vm.stopPrank();

        assertEq(tokens, 40 * ONE_TOKEN);
        assertEq(hts.balanceOf(token, buyer), 40 * ONE_TOKEN);
        assertEq(hts.balanceOf(token, diamond), SUPPLY - 40 * ONE_TOKEN);
        assertEq(diamond.balance, 10 * ONE_HBAR);

        (,,,, int64 sold, uint256 raised) = sale.saleInfo();
        assertEq(sold, 40 * ONE_TOKEN);
        assertEq(raised, 10 * ONE_HBAR);
    }

    function test_buy_revertsUntilTheBuyerAssociates() public {
        _launch();

        vm.expectRevert(abi.encodeWithSelector(ITokenSale.TokenSaleBuyerNotAssociated.selector, buyer));
        vm.prank(buyer);
        sale.buy{ value: ONE_HBAR }(0);
    }

    function test_buy_revertsBelowTheBuyersMinimum() public {
        address token = _launch();
        vm.startPrank(buyer);
        IHRC719(token).associate();

        vm.expectRevert(abi.encodeWithSelector(ITokenSale.TokenSaleSlippage.selector, 4 * ONE_TOKEN, 5 * ONE_TOKEN));
        sale.buy{ value: ONE_HBAR }(5 * ONE_TOKEN);
        vm.stopPrank();
    }

    function test_buy_surfacesTheHtsResponseCodeWhenTheTreasuryRunsOut() public {
        address token = _launch();
        vm.deal(buyer, 300_000 * ONE_HBAR);
        vm.startPrank(buyer);
        IHRC719(token).associate();

        // 300,000 HBAR would buy 1.2M tokens; the treasury holds 1M. HTS answers INSUFFICIENT_TOKEN_BALANCE.
        vm.expectRevert(abi.encodeWithSelector(ITokenSale.TokenSaleTransferFailed.selector, int64(178)));
        sale.buy{ value: 300_000 * ONE_HBAR }(0);
        vm.stopPrank();
    }
```

**Step 2: Run test to verify it fails**

Run: `(cd packages/foundry && forge test --match-contract TokenSaleTest)`

Expected: FAIL. Compilation stops at the first thing the tests use that `ITokenSale` lacks, the `TokensPurchased` event.

```text
Error (9582): Member "TokensPurchased" not found or not visible after argument-dependent lookup in type(contract ITokenSale).
```

**Step 3: Write minimal implementation**

Edit `packages/foundry/contracts/interfaces/ITokenSale.sol`.

Edit 1 of 3. After:

```solidity
    event SaleLaunched(address indexed token, int32 decimals, int64 supply, uint256 priceUsd);
```

insert:

```solidity

    /// @notice Emitted on every purchase. `hbarUsd` is the oracle answer the purchase was priced at.
    event TokensPurchased(address indexed buyer, uint256 tinybars, int64 tokens, uint256 hbarUsd);
```

Edit 2 of 3. After:

```solidity
    error TokenSaleInvalidAmount();
```

insert:

```solidity
    /// @notice The payment buys fewer tokens than the buyer's `minTokens`.
    error TokenSaleSlippage(int64 tokens, int64 minTokens);
    /// @notice `buyer` must associate with the token before buying (HTS 184).
    error TokenSaleBuyerNotAssociated(address buyer);
    /// @notice HTS refused the transfer to the buyer with `responseCode`.
    error TokenSaleTransferFailed(int64 responseCode);
```

Edit 3 of 3. After:

```solidity
    ) external payable returns (address token);
```

insert:

```solidity

    /// @notice Buys tokens with the HBAR sent. Reverts if that buys fewer than `minTokens`.
    /// @return tokens Token units transferred to the caller.
    function buy(int64 minTokens) external payable returns (int64 tokens);
```

Edit `packages/foundry/contracts/libraries/TokenSaleLib.sol`.

Edit 1 of 3. Replace:

```solidity
import { HTSAdapterLib } from "@lattice/tokens/hedera/HTSAdapterLib.sol";
```

with:

```solidity
import { HederaResponseCodes } from "@lattice/interfaces/external/hedera/HederaResponseCodes.sol";
import { IHederaTokenService } from "@lattice/interfaces/external/hedera/IHederaTokenService.sol";
import { HTSAdapterLib, HTS_SYSTEM_CONTRACT } from "@lattice/tokens/hedera/HTSAdapterLib.sol";
```

Edit 2 of 3. After:

```solidity
        emit ITokenSale.SaleLaunched(token, decimals, supply, priceUsd);
    }
```

insert:

```solidity

    function buy(int64 minTokens) internal returns (int64 tokens) {
        TokenSaleStorage storage $ = tokenSaleStorage();
        uint256 hbarUsd = _hbarUsd($);
        tokens = _tokensFor($, msg.value, hbarUsd);
        if (tokens < minTokens) revert ITokenSale.TokenSaleSlippage(tokens, minTokens);

        $.sold += tokens;
        $.raised += msg.value;
        emit ITokenSale.TokensPurchased(msg.sender, msg.value, tokens, hbarUsd);
        _transferFromTreasury($.token, msg.sender, tokens);
    }
```

Edit 3 of 3. After:

```solidity
        return int64(uint64(units));
    }
```

insert:

```solidity

    /// @dev HTS returns a response code instead of reverting, so the code is checked here. The call is a plain
    ///      `call` from the diamond: HTS sees the diamond as sender, and the diamond holds the tokens.
    function _transferFromTreasury(address token, address to, int64 tokens) private {
        (bool ok, bytes memory ret) = HTS_SYSTEM_CONTRACT.call(
            abi.encodeCall(IHederaTokenService.transferToken, (token, address(this), to, tokens))
        );
        int64 code = ok ? abi.decode(ret, (int64)) : HederaResponseCodes.UNKNOWN;
        if (code == HederaResponseCodes.TOKEN_NOT_ASSOCIATED_TO_ACCOUNT) {
            revert ITokenSale.TokenSaleBuyerNotAssociated(to);
        }
        if (code != HederaResponseCodes.SUCCESS) revert ITokenSale.TokenSaleTransferFailed(code);
    }
```

Edit `packages/foundry/contracts/TokenSale.sol`.

Edit 1 of 3. After:

```solidity
        return TokenSaleLib.launchSale(name, symbol, memo, decimals, supply, priceUsd);
    }
```

insert:

```solidity

    /// @inheritdoc ITokenSale
    function buy(int64 minTokens) external payable virtual returns (int64 tokens) {
        return TokenSaleLib.buy(minTokens);
    }
```

Edit 2 of 3. After:

```solidity
    /// @dev Never includes `exportSelectors()` itself. `test/TokenSale.t.sol` checks this list against the ABI.
```

insert:

```solidity
    ///      `buy(int64)` 0x08bf598d
```

Edit 3 of 3. Replace:

```solidity
        selectors = hex"df1d74aeed1bd76c8e3695b8";
```

with:

```solidity
        selectors = hex"08bf598ddf1d74aeed1bd76c8e3695b8";
```

**Step 4: Run test to verify it passes**

Run: `(cd packages/foundry && forge test --match-contract TokenSaleTest)`

Expected: PASS. Fifteen tests pass.

```text
Suite result: ok. 15 passed; 0 failed; 0 skipped; finished in 8.63ms (2.97ms CPU time)
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: sell tokens for HBAR out of the diamond's treasury"
```

---

### Task 11: Stop sales while the emergency stop is active

**Files:**
- Test: `packages/foundry/test/TokenSale.t.sol`
- Modify: `packages/foundry/contracts/libraries/TokenSaleLib.sol`

The base recipe carries Lattice's `EmergencyStop` facet. It only protects functions that ask it, so `buy` asks. This is a one-line use of another module's library, which is how Lattice modules compose.

**Step 1: Write the failing test**

Edit `packages/foundry/test/TokenSale.t.sol`.

Edit 1 of 2. After:

```solidity
import { IChainlinkAdapter } from "@lattice/interfaces/oracles/IChainlinkAdapter.sol";
```

insert:

```solidity
import { IEmergencyStop } from "@lattice/interfaces/security/IEmergencyStop.sol";
```

Edit 2 of 2. Before:

```solidity

    function test_storageSlot_followsErc7201() public pure {
```

insert:

```solidity

    function test_buy_revertsWhileTheEmergencyStopIsActive() public {
        address token = _launch();
        vm.startPrank(admin);
        IEmergencyStop(diamond).addGuardian(admin);
        IEmergencyStop(diamond).emergencyStop("oracle incident");
        vm.stopPrank();

        vm.startPrank(buyer);
        IHRC719(token).associate();
        vm.expectRevert(IEmergencyStop.EmergencyStopActive.selector);
        sale.buy{ value: ONE_HBAR }(0);
        vm.stopPrank();
    }
```

**Step 2: Run test to verify it fails**

Run: `(cd packages/foundry && forge test --match-contract TokenSaleTest)`

Expected: FAIL. The new test fails: the purchase goes through although the stop is active.

```text
[FAIL: next call did not revert as expected] test_buy_revertsWhileTheEmergencyStopIsActive() (gas: 925070)
Suite result: FAILED. 15 passed; 1 failed; 0 skipped; finished in 7.93ms (3.16ms CPU time)
```

**Step 3: Write minimal implementation**

Edit `packages/foundry/contracts/libraries/TokenSaleLib.sol`.

Edit 1 of 2. After:

```solidity
import { IHederaTokenService } from "@lattice/interfaces/external/hedera/IHederaTokenService.sol";
```

insert:

```solidity
import { EmergencyStopLib } from "@lattice/security/libraries/EmergencyStopLib.sol";
```

Edit 2 of 2. After:

```solidity
    function buy(int64 minTokens) internal returns (int64 tokens) {
```

insert:

```solidity
        EmergencyStopLib.checkNotStopped();
```

**Step 4: Run test to verify it passes**

Run: `(cd packages/foundry && forge test --match-contract TokenSaleTest)`

Expected: PASS. Sixteen tests pass.

```text
Suite result: ok. 16 passed; 0 failed; 0 skipped; finished in 10.64ms (5.34ms CPU time)
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: refuse purchases while the emergency stop is active"
```

---

### Task 12: Let the admin change the price

**Files:**
- Test: `packages/foundry/test/TokenSale.t.sol`
- Modify: `packages/foundry/contracts/interfaces/ITokenSale.sol`
- Modify: `packages/foundry/contracts/libraries/TokenSaleLib.sol`
- Modify: `packages/foundry/contracts/TokenSale.sol`

**Step 1: Write the failing test**

Edit `packages/foundry/test/TokenSale.t.sol`.

Before:

```solidity

    function test_storageSlot_followsErc7201() public pure {
```

insert:

```solidity

    function test_setSalePrice_changesTheQuote() public {
        _launch();

        vm.expectEmit(diamond);
        emit ITokenSale.SalePriceSet(0.1e18);
        vm.prank(admin);
        sale.setSalePrice(0.1e18);

        assertEq(sale.quote(ONE_HBAR), 2 * ONE_TOKEN);
    }

    function test_setSalePrice_revertsForAnyoneButTheAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, buyer, bytes32(0))
        );
        vm.prank(buyer);
        sale.setSalePrice(0.1e18);
    }
```

**Step 2: Run test to verify it fails**

Run: `(cd packages/foundry && forge test --match-contract TokenSaleTest)`

Expected: FAIL. Compilation stops at the first thing the tests use that `ITokenSale` lacks, the `SalePriceSet` event.

```text
Error (9582): Member "SalePriceSet" not found or not visible after argument-dependent lookup in type(contract ITokenSale).
```

**Step 3: Write minimal implementation**

Edit `packages/foundry/contracts/interfaces/ITokenSale.sol`.

Edit 1 of 2. After:

```solidity
    event SaleLaunched(address indexed token, int32 decimals, int64 supply, uint256 priceUsd);
```

insert:

```solidity

    /// @notice Emitted when the admin changes the price.
    event SalePriceSet(uint256 priceUsd);
```

Edit 2 of 2. After:

```solidity
    ) external payable returns (address token);
```

insert:

```solidity

    /// @notice Sets the price in USD per whole token, 18 decimals. Caller must hold `DEFAULT_ADMIN_ROLE`.
    function setSalePrice(uint256 priceUsd) external;
```

Edit `packages/foundry/contracts/libraries/TokenSaleLib.sol`.

After:

```solidity
        emit ITokenSale.SaleLaunched(token, decimals, supply, priceUsd);
    }
```

insert:

```solidity

    function setSalePrice(uint256 priceUsd) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (priceUsd == 0) revert ITokenSale.TokenSaleInvalidPrice();
        tokenSaleStorage().priceUsd = priceUsd;
        emit ITokenSale.SalePriceSet(priceUsd);
    }
```

Edit `packages/foundry/contracts/TokenSale.sol`.

Edit 1 of 2. After:

```solidity
        return TokenSaleLib.launchSale(name, symbol, memo, decimals, supply, priceUsd);
    }
```

insert:

```solidity

    /// @inheritdoc ITokenSale
    function setSalePrice(uint256 priceUsd) external virtual {
        TokenSaleLib.setSalePrice(priceUsd);
    }
```

Edit 2 of 2. Replace:

```solidity
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"08bf598ddf1d74aeed1bd76c8e3695b8";
```

with:

```solidity
    ///      `setSalePrice(uint256)` 0x1919fed7
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"08bf598ddf1d74aeed1bd76c8e3695b81919fed7";
```

**Step 4: Run test to verify it passes**

Run: `(cd packages/foundry && forge test --match-contract TokenSaleTest)`

Expected: PASS. Eighteen tests pass.

```text
Suite result: ok. 18 passed; 0 failed; 0 skipped; finished in 8.76ms (3.33ms CPU time)
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: let the admin change the sale price"
```

---

### Task 13: Let the admin withdraw the proceeds

**Files:**
- Test: `packages/foundry/test/TokenSale.t.sol`
- Modify: `packages/foundry/contracts/interfaces/ITokenSale.sol`
- Modify: `packages/foundry/contracts/libraries/TokenSaleLib.sol`
- Modify: `packages/foundry/contracts/TokenSale.sol`

The HBAR buyers pay stays in the diamond. `withdrawProceeds` takes an amount in tinybars, the unit the EVM sees on Hedera.

**Step 1: Write the failing test**

Edit `packages/foundry/test/TokenSale.t.sol`.

After:

```solidity
        sale.setSalePrice(0.1e18);
    }
```

insert:

```solidity

    function test_withdrawProceeds_paysTheRecipient() public {
        address token = _launch();
        vm.startPrank(buyer);
        IHRC719(token).associate();
        sale.buy{ value: 10 * ONE_HBAR }(0);
        vm.stopPrank();
        address payable treasury = payable(makeAddr("treasury"));

        vm.expectEmit(diamond);
        emit ITokenSale.ProceedsWithdrawn(treasury, 10 * ONE_HBAR);
        vm.prank(admin);
        sale.withdrawProceeds(treasury, 10 * ONE_HBAR);

        assertEq(treasury.balance, 10 * ONE_HBAR);
        assertEq(diamond.balance, 0);
    }

    function test_withdrawProceeds_revertsForAnyoneButTheAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, buyer, bytes32(0))
        );
        vm.prank(buyer);
        sale.withdrawProceeds(payable(buyer), 1);
    }
```

**Step 2: Run test to verify it fails**

Run: `(cd packages/foundry && forge test --match-contract TokenSaleTest)`

Expected: FAIL. Compilation stops at the first thing the tests use that `ITokenSale` lacks, the `ProceedsWithdrawn` event.

```text
Error (9582): Member "ProceedsWithdrawn" not found or not visible after argument-dependent lookup in type(contract ITokenSale).
```

**Step 3: Write minimal implementation**

Edit `packages/foundry/contracts/interfaces/ITokenSale.sol`.

Edit 1 of 3. After:

```solidity
    event TokensPurchased(address indexed buyer, uint256 tinybars, int64 tokens, uint256 hbarUsd);
```

insert:

```solidity

    /// @notice Emitted when the admin withdraws sale proceeds.
    event ProceedsWithdrawn(address indexed to, uint256 tinybars);
```

Edit 2 of 3. After:

```solidity
    error TokenSaleTransferFailed(int64 responseCode);
```

insert:

```solidity
    /// @notice The HBAR transfer to the withdrawal recipient failed.
    error TokenSaleWithdrawFailed();
```

Edit 3 of 3. After:

```solidity
    function setSalePrice(uint256 priceUsd) external;
```

insert:

```solidity

    /// @notice Sends `tinybars` of the diamond's HBAR to `to`. Caller must hold `DEFAULT_ADMIN_ROLE`.
    function withdrawProceeds(address payable to, uint256 tinybars) external;
```

Edit `packages/foundry/contracts/libraries/TokenSaleLib.sol`.

After:

```solidity
        emit ITokenSale.SalePriceSet(priceUsd);
    }
```

insert:

```solidity

    function withdrawProceeds(address payable to, uint256 tinybars) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        emit ITokenSale.ProceedsWithdrawn(to, tinybars);
        (bool ok,) = to.call{ value: tinybars }("");
        if (!ok) revert ITokenSale.TokenSaleWithdrawFailed();
    }
```

Edit `packages/foundry/contracts/TokenSale.sol`.

Edit 1 of 2. After:

```solidity
        TokenSaleLib.setSalePrice(priceUsd);
    }
```

insert:

```solidity

    /// @inheritdoc ITokenSale
    function withdrawProceeds(address payable to, uint256 tinybars) external virtual {
        TokenSaleLib.withdrawProceeds(to, tinybars);
    }
```

Edit 2 of 2. Replace:

```solidity
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"08bf598ddf1d74aeed1bd76c8e3695b81919fed7";
```

with:

```solidity
    ///      `withdrawProceeds(address,uint256)` 0x970ea83e
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"08bf598ddf1d74aeed1bd76c8e3695b81919fed7970ea83e";
```

**Step 4: Run test to verify it passes**

Run: `(cd packages/foundry && forge test --match-contract TokenSaleTest)`

Expected: PASS. Twenty tests pass.

```text
Suite result: ok. 20 passed; 0 failed; 0 skipped; finished in 11.97ms (5.82ms CPU time)
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: let the admin withdraw sale proceeds"
```

---

### Task 14: Upgrade the sale with TokenSaleV2

**Files:**
- Test: `packages/foundry/test/TokenSaleUpgrade.t.sol`
- Modify: `packages/foundry/contracts/libraries/TokenSaleLib.sol`
- Modify: `packages/foundry/contracts/TokenSale.sol`
- Create: `packages/foundry/contracts/TokenSaleV2.sol`

The README's walkthrough ends with a live `diamondCut`. This is the facet it cuts in: the same sale with a 5% bonus and one new function, `bonusBps()`. The test is the walkthrough itself: buy, cut, and check that the token, the price and the totals survived while the quote grew by 5%.

The library gains a `bonusBps` parameter and the facet gains an internal `_bonusBps()` hook that `TokenSaleV2` overrides. `TokenSale` passes zero, so its behaviour does not change and its twenty tests stay green.

**Step 1: Write the failing test**

Create `packages/foundry/test/TokenSaleUpgrade.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IDiamondCut } from "@diamond/interfaces/IDiamondCut.sol";
import { IDiamondLoupe } from "@diamond/interfaces/IDiamondLoupe.sol";
import { FacetCut, FacetCutAction } from "@diamond/libraries/DiamondLib.sol";
import { IAccessControl } from "@lattice/interfaces/access/IAccessControl.sol";
import { IHRC719 } from "@lattice/interfaces/external/hedera/IHRC719.sol";
import { TokenSaleV2 } from "../contracts/TokenSaleV2.sol";
import { ITokenSale } from "../contracts/interfaces/ITokenSale.sol";
import { SaleTestBase } from "./SaleTestBase.sol";

/// @notice The README's upgrade walkthrough as a test: cut TokenSaleV2 into a diamond that is already selling.
contract TokenSaleUpgradeTest is SaleTestBase {
    address internal token;
    TokenSaleV2 internal v2;

    function setUp() public override {
        super.setUp();
        token = _launch();
        vm.startPrank(buyer);
        IHRC719(token).associate();
        sale.buy{ value: 10 * ONE_HBAR }(0);
        vm.stopPrank();
        v2 = new TokenSaleV2();
    }

    function test_cut_keepsTheSaleAndAddsTheBonus() public {
        FacetCut[] memory cuts = _cutsFor(address(v2));

        vm.prank(admin);
        IDiamondCut(diamond).diamondCut(cuts, address(0), "");

        (address saleToken,, uint256 priceUsd,, int64 sold, uint256 raised) = sale.saleInfo();
        assertEq(saleToken, token, "same token");
        assertEq(priceUsd, PRICE_USD, "same price");
        assertEq(sold, 40 * ONE_TOKEN, "same total sold");
        assertEq(raised, 10 * ONE_HBAR, "same total raised");

        assertEq(IDiamondLoupe(diamond).facetAddress(ITokenSale.buy.selector), address(v2), "buy replaced");
        assertEq(TokenSaleV2(diamond).bonusBps(), 500, "bonusBps added");
        assertEq(sale.quote(ONE_HBAR), 4.2e8, "4 tokens plus 5%");

        vm.prank(buyer);
        assertEq(sale.buy{ value: ONE_HBAR }(0), 4.2e8);
        assertEq(hts.balanceOf(token, buyer), 44.2e8);
    }

    function test_cut_revertsForAnyoneButTheAdmin() public {
        FacetCut[] memory cuts = _cutsFor(address(v2));

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, buyer, bytes32(0))
        );
        vm.prank(buyer);
        IDiamondCut(diamond).diamondCut(cuts, address(0), "");
    }

    function test_exportSelectors_listsTheSaleSelectorsThenTheNewOne() public view {
        bytes memory exported = v2.exportSelectors();
        assertEq(exported.length, 7 * 4);
        assertEq(_selectorAt(exported, 0), ITokenSale.buy.selector);
        assertEq(_selectorAt(exported, 6), TokenSaleV2.bonusBps.selector);
    }

    /// @dev The same rule the app's Diamond page applies: a selector the diamond already serves is replaced,
    ///      a new one is added.
    function _cutsFor(address facet) internal view returns (FacetCut[] memory cuts) {
        bytes memory exported = TokenSaleV2(facet).exportSelectors();
        uint256 count = exported.length / 4;
        bytes4[] memory replaced = new bytes4[](count);
        bytes4[] memory added = new bytes4[](count);
        uint256 replaces;
        uint256 adds;
        for (uint256 i; i < count; ++i) {
            bytes4 selector = _selectorAt(exported, i);
            if (IDiamondLoupe(diamond).facetAddress(selector) == address(0)) added[adds++] = selector;
            else replaced[replaces++] = selector;
        }
        assembly ("memory-safe") {
            mstore(replaced, replaces)
            mstore(added, adds)
        }
        cuts = new FacetCut[](2);
        cuts[0] = FacetCut({ facetAddress: facet, action: FacetCutAction.Replace, functionSelectors: replaced });
        cuts[1] = FacetCut({ facetAddress: facet, action: FacetCutAction.Add, functionSelectors: added });
    }

    function _selectorAt(bytes memory packed, uint256 index) internal pure returns (bytes4 selector) {
        assembly ("memory-safe") {
            selector := mload(add(add(packed, 0x20), mul(index, 4)))
        }
    }
}
```

**Step 2: Run test to verify it fails**

Run: `(cd packages/foundry && forge test)`

Expected: FAIL. The test imports `contracts/TokenSaleV2.sol`, which does not exist.

```text
Unable to resolve imports:
"../contracts/TokenSaleV2.sol" in "<repo>/packages/foundry/test/TokenSaleUpgrade.t.sol"
```

**Step 3: Write minimal implementation**

Edit `packages/foundry/contracts/libraries/TokenSaleLib.sol`.

Edit 1 of 5. After:

```solidity
uint256 constant TINYBARS_PER_HBAR = 1e8;
```

insert:

```solidity

/// @dev Basis points in 100%.
uint256 constant BPS = 10_000;
```

Edit 2 of 5. Replace:

```solidity
    function buy(int64 minTokens) internal returns (int64 tokens) {
```

with:

```solidity
    /// @param bonusBps Extra tokens on top of the quote, in basis points. The facet decides it.
    function buy(int64 minTokens, uint256 bonusBps) internal returns (int64 tokens) {
```

Edit 3 of 5. Replace:

```solidity
        tokens = _tokensFor($, msg.value, hbarUsd);
```

with:

```solidity
        tokens = _tokensFor($, msg.value, hbarUsd, bonusBps);
```

Edit 4 of 5. Replace:

```solidity
    function quote(uint256 tinybars) internal view returns (int64 tokens) {
        TokenSaleStorage storage $ = tokenSaleStorage();
        return _tokensFor($, tinybars, _hbarUsd($));
```

with:

```solidity
    function quote(uint256 tinybars, uint256 bonusBps) internal view returns (int64 tokens) {
        TokenSaleStorage storage $ = tokenSaleStorage();
        return _tokensFor($, tinybars, _hbarUsd($), bonusBps);
```

Edit 5 of 5. Replace:

```solidity
    /// @dev units = tinybars * (USD per HBAR) * 10^decimals / (tinybars per HBAR * USD per token).
    ///      One division, so nothing is rounded away early. `decimals` is 0..18 and the result is
    ///      range-checked, which is what makes the casts safe.
    function _tokensFor(TokenSaleStorage storage $, uint256 tinybars, uint256 hbarUsd) private view returns (int64) {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 unit = 10 ** uint256(uint32($.decimals));
        uint256 units = (tinybars * hbarUsd * unit) / (TINYBARS_PER_HBAR * $.priceUsd);
```

with:

```solidity
    /// @dev units = tinybars * (USD per HBAR) * 10^decimals * (1 + bonus) / (tinybars per HBAR * USD per token).
    ///      One division, so nothing is rounded away before the bonus is applied. `decimals` is 0..18 and the
    ///      result is range-checked, which is what makes the casts safe.
    function _tokensFor(TokenSaleStorage storage $, uint256 tinybars, uint256 hbarUsd, uint256 bonusBps)
        private
        view
        returns (int64)
    {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 unit = 10 ** uint256(uint32($.decimals));
        uint256 units = (tinybars * hbarUsd * unit * (BPS + bonusBps)) / (TINYBARS_PER_HBAR * $.priceUsd * BPS);
```

Edit `packages/foundry/contracts/TokenSale.sol`.

Edit 1 of 3. Replace:

```solidity
        return TokenSaleLib.buy(minTokens);
```

with:

```solidity
        return TokenSaleLib.buy(minTokens, _bonusBps());
```

Edit 2 of 3. Replace:

```solidity
        return TokenSaleLib.quote(tinybars);
```

with:

```solidity
        return TokenSaleLib.quote(tinybars, _bonusBps());
```

Edit 3 of 3. After:

```solidity
        return ($.token, $.decimals, $.priceUsd, $.feedKey, $.sold, $.raised);
    }
```

insert:

```solidity

    /// @dev Bonus applied to every quote and purchase, in basis points. An upgraded facet overrides it.
    function _bonusBps() internal view virtual returns (uint256) {
        return 0;
    }
```

Create `packages/foundry/contracts/TokenSaleV2.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { TokenSale } from "./TokenSale.sol";

/// @title TokenSaleV2
/// @notice The upgrade used in the README walkthrough: the same sale with a 5% early-bird bonus. Cutting it
///         into a live diamond replaces TokenSale's selectors and adds `bonusBps()`. The token, the price,
///         the totals and the diamond's address are untouched, because all of that lives in the diamond.
contract TokenSaleV2 is TokenSale {
    uint256 internal constant BONUS_BPS = 500;

    /// @notice The bonus added to every quote and purchase, in basis points.
    function bonusBps() external pure virtual returns (uint256) {
        return BONUS_BPS;
    }

    function _bonusBps() internal pure virtual override returns (uint256) {
        return BONUS_BPS;
    }

    /// @notice ERC-8153: TokenSale's selectors, then `bonusBps()` 0x404f21a5.
    function exportSelectors() external pure virtual override returns (bytes memory selectors) {
        selectors = hex"08bf598ddf1d74aeed1bd76c8e3695b81919fed7970ea83e404f21a5";
    }
}
```

**Step 4: Run test to verify it passes**

Run: `(cd packages/foundry && forge test)`

Expected: PASS. Twenty-nine tests pass across the three suites.

```text
Ran 3 test suites in 31.64ms (53.67ms CPU time): 29 tests passed, 0 failed, 0 skipped (29 total tests)
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: add TokenSaleV2, the facet the upgrade walkthrough cuts in"
```

---

### Task 15: Deploy script for the upgrade facet

**Files:**
- Create: `packages/foundry/script/DeployTokenSaleV2.s.sol`

A facet deployed on its own changes nothing until it is cut in. This script deploys `TokenSaleV2` with the stock Scaffold-HBAR helper, which records the address under the contract's name. The frontend generator then lists it, and the app's Upgrade box finds it.

**Step 1: Write the failing test**

A deploy script has no unit test. The check is a dry run on Foundry's local EVM: the script runs and records the facet by name.

```bash
(cd packages/foundry && mkdir -p deployments && forge script script/DeployTokenSaleV2.s.sol && grep TokenSaleV2 deployments/31337.json; status=$?; rm -f deployments/31337.json; exit $status)
```

**Step 2: Run test to verify it fails**

Run:

```bash
(cd packages/foundry && mkdir -p deployments && forge script script/DeployTokenSaleV2.s.sol && grep TokenSaleV2 deployments/31337.json; status=$?; rm -f deployments/31337.json; exit $status)
```

Expected: FAIL. The script does not exist, which Forge reports like this:

```text
Error: contract source info format must be `<path>:<contractname>` or `<contractname>`
```

**Step 3: Write minimal implementation**

Create `packages/foundry/script/DeployTokenSaleV2.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { TokenSaleV2 } from "../contracts/TokenSaleV2.sol";
import { ScaffoldETHDeploy } from "./DeployHelpers.s.sol";

/// @notice Deploys the TokenSaleV2 facet on its own. It changes nothing until the diamond's admin cuts it
///         in, which the app's Diamond page does (see the README's upgrade walkthrough).
contract DeployTokenSaleV2 is ScaffoldETHDeploy {
    function run() external ScaffoldEthDeployerRunner {
        TokenSaleV2 facet = new TokenSaleV2();
        deployments.push(Deployment({ name: "TokenSaleV2", addr: address(facet) }));
    }
}
```

**Step 4: Run test to verify it passes**

Run:

```bash
(cd packages/foundry && mkdir -p deployments && forge script script/DeployTokenSaleV2.s.sol && grep TokenSaleV2 deployments/31337.json; status=$?; rm -f deployments/31337.json; exit $status)
```

Expected: PASS. `Script ran successfully.` and a JSON line that maps an address to `TokenSaleV2`.

```text
Script ran successfully.
"0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496": "TokenSaleV2",
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: add a deploy script for the TokenSaleV2 facet"
```

---

### Task 16: The deploy entry point and its chain guard

**Files:**
- Test: `packages/foundry/test/DeployDiamond.t.sol`
- Modify: `packages/foundry/script/DeployDiamond.s.sol`
- Create: `packages/foundry/script/Deploy.s.sol`

`run()` is what `forge script` executes. The diamond needs HTS and a Chainlink feed, which exist only on Hedera, so `run()` refuses any other chain with a message that names the fix. `Deploy.s.sol` is the file `yarn foundry:deploy` runs when no `--file` is given.

**Step 1: Write the failing test**

Edit `packages/foundry/test/DeployDiamond.t.sol`.

After:

```solidity
        deployer.build("{}", admin);
    }
```

insert:

```solidity

    function test_run_refusesAChainThatIsNotHedera() public {
        vm.expectRevert(
            bytes(
                "DeployDiamond: this diamond needs Hedera (HTS and a Chainlink feed). Deploy with --network hedera_testnet"
            )
        );
        deployer.run();
    }
```

**Step 2: Run test to verify it fails**

Run: `(cd packages/foundry && forge test --match-contract DeployDiamondTest)`

Expected: FAIL. Compilation stops: `DeployDiamond` has no `run`.

```text
Error (9582): Member "run" not found or not visible after argument-dependent lookup in contract DeployDiamond.
```

**Step 3: Write minimal implementation**

Edit `packages/foundry/script/DeployDiamond.s.sol`.

Edit 1 of 3. After:

```solidity
import { DiamondIntrospectionInit } from "@lattice/utils/DiamondIntrospectionInit.sol";
```

insert:

```solidity
import { console } from "forge-std/console.sol";
```

Edit 2 of 3. After:

```solidity
contract DeployDiamond is BaseDeploy {
```

insert (the block ends with an empty line; keep it):

```solidity
    string internal constant RECIPE = "diamond.recipe.json";

```

Edit 3 of 3. After:

```solidity
    uint256 internal constant HEDERA_INITS = 3;
```

insert:

```solidity

    function run() external returns (address diamond) {
        require(
            block.chainid == 295 || block.chainid == 296,
            "DeployDiamond: this diamond needs Hedera (HTS and a Chainlink feed). Deploy with --network hedera_testnet"
        );
        string memory json = vm.readFile(RECIPE);

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        diamond = assemble(json, deployer);
        vm.stopBroadcast();

        console.log("Diamond deployed at", diamond);
    }
```

Create `packages/foundry/script/Deploy.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { DeployDiamond } from "./DeployDiamond.s.sol";

/// @notice What `yarn foundry:deploy` runs when no `--file` is given: the recipe-driven diamond deploy.
contract DeployScript is DeployDiamond { }
```

**Step 4: Run test to verify it passes**

Run: `(cd packages/foundry && forge test --match-contract DeployDiamondTest)`

Expected: PASS. Seven tests pass.

```text
Suite result: ok. 7 passed; 0 failed; 0 skipped; finished in 22.95ms (30.99ms CPU time)
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: add the deploy entry point and refuse chains that are not Hedera"
```

---

### Task 17: Register the Chainlink HBAR/USD feed at deploy time

**Files:**
- Test: `packages/foundry/test/DeployDiamond.t.sol`
- Modify: `packages/foundry/script/DeployDiamond.s.sol`

A diamond without a registered feed cannot quote. `run()` registers Chainlink's HBAR/USD feed under the key the sale reads, in the same broadcast. Testnet feeds are not kept on a production heartbeat, so the testnet default for the staleness limit is deliberately loose; `HBAR_USD_MAX_STALENESS` overrides it. The test puts a mock at the real feed address, so no network is involved.

**Step 1: Write the failing test**

Edit `packages/foundry/test/DeployDiamond.t.sol`.

Edit 1 of 4. After:

```solidity
import { IAccessControl } from "@lattice/interfaces/access/IAccessControl.sol";
```

insert:

```solidity
import { IChainlinkAdapter } from "@lattice/interfaces/oracles/IChainlinkAdapter.sol";
```

Edit 2 of 4. Replace:

```solidity
import { DeployDiamond } from "../script/DeployDiamond.s.sol";

contract DeployDiamondTest is Test {
    address internal admin = makeAddr("admin");
    DeployDiamond internal deployer;
```

with:

```solidity
import { DeployDiamond } from "../script/DeployDiamond.s.sol";
import { MockAggregatorV3 } from "./mocks/MockAggregatorV3.sol";

/// @dev Opens the step `run()` performs after the diamond exists, so it can be tested without a broadcast.
contract DeployDiamondHarness is DeployDiamond {
    function registerHbarUsdFeed(address diamond) external {
        _registerHbarUsdFeed(diamond);
    }
}

contract DeployDiamondTest is Test {
    address internal constant HBAR_USD_FEED_TESTNET = 0x59bC155EB6c6C415fE43255aF66EcF0523c92B4a;

    address internal admin = makeAddr("admin");
    DeployDiamondHarness internal deployer;
```

Edit 3 of 4. Replace:

```solidity
        deployer = new DeployDiamond();
```

with:

```solidity
        deployer = new DeployDiamondHarness();
```

Edit 4 of 4. After:

```solidity
        deployer.run();
    }
```

insert:

```solidity

    function test_registerHbarUsdFeed_registersTheChainlinkFeedUnderTheSalesKey() public {
        vm.etch(HBAR_USD_FEED_TESTNET, address(new MockAggregatorV3()).code);
        address diamond = deployer.assemble(recipe, address(deployer));

        deployer.registerHbarUsdFeed(diamond);

        (address feed, uint48 maxStaleness) = IChainlinkAdapter(diamond).getFeed("HBAR/USD");
        assertEq(feed, HBAR_USD_FEED_TESTNET);
        // 365 days on testnet, unless your .env sets HBAR_USD_MAX_STALENESS.
        assertEq(maxStaleness, vm.envOr("HBAR_USD_MAX_STALENESS", uint256(365 days)));
    }
```

**Step 2: Run test to verify it fails**

Run: `(cd packages/foundry && forge test --match-contract DeployDiamondTest)`

Expected: FAIL. Compilation stops: `_registerHbarUsdFeed` is not declared.

```text
Error (7576): Undeclared identifier. Did you mean "registerHbarUsdFeed"?
19 |         _registerHbarUsdFeed(diamond);
```

**Step 3: Write minimal implementation**

Edit `packages/foundry/script/DeployDiamond.s.sol`.

Edit 1 of 4. Replace:

```solidity
import { FacetCut } from "@diamond/libraries/DiamondLib.sol";
import { BaseDeploy } from "@lattice-script/base/BaseDeploy.s.sol";
```

with:

```solidity
import { IDiamondLoupe } from "@diamond/interfaces/IDiamondLoupe.sol";
import { FacetCut } from "@diamond/libraries/DiamondLib.sol";
import { BaseDeploy } from "@lattice-script/base/BaseDeploy.s.sol";
import { IChainlinkAdapter } from "@lattice/interfaces/oracles/IChainlinkAdapter.sol";
```

Edit 2 of 4. After:

```solidity
    bytes32 internal constant HBAR_USD = "HBAR/USD";
```

insert:

```solidity

    /// @dev Chainlink HBAR/USD price feeds (https://docs.chain.link/data-feeds/price-feeds/addresses?network=hedera).
    address internal constant HBAR_USD_FEED_TESTNET = 0x59bC155EB6c6C415fE43255aF66EcF0523c92B4a;
    address internal constant HBAR_USD_FEED_MAINNET = 0xAF685FB45C12b92b5054ccb9313e135525F9b5d5;
```

Edit 3 of 4. After:

```solidity
        diamond = assemble(json, deployer);
```

insert:

```solidity
        _registerHbarUsdFeed(diamond);
```

Edit 4 of 4. After:

```solidity
                " is in the recipe but not compiled into this project; add its import to contracts/LatticeFacets.sol"
            )
        );
    }
```

insert:

```solidity

    // ── after the diamond exists ────────────────────────────────────────────────────────────────────

    /// @dev Chainlink only. Another oracle facet registers its feed with its own arguments (see the README).
    function _registerHbarUsdFeed(address diamond) internal {
        if (IDiamondLoupe(diamond).facetAddress(IChainlinkAdapter.registerFeed.selector) == address(0)) {
            console.log(
                "No ChainlinkAdapter in this recipe: register an HBAR/USD feed under the key 'HBAR/USD' yourself."
            );
            return;
        }
        bool mainnet = block.chainid == 295;
        // Testnet feeds are not kept on a production heartbeat, so the testnet default is deliberately loose.
        uint256 maxStaleness = vm.envOr("HBAR_USD_MAX_STALENESS", mainnet ? uint256(25 hours) : uint256(365 days));
        IChainlinkAdapter(diamond)
            .registerFeed(HBAR_USD, mainnet ? HBAR_USD_FEED_MAINNET : HBAR_USD_FEED_TESTNET, uint48(maxStaleness));
    }
```

**Step 4: Run test to verify it passes**

Run: `(cd packages/foundry && forge test --match-contract DeployDiamondTest)`

Expected: PASS. Eight tests pass.

```text
Suite result: ok. 8 passed; 0 failed; 0 skipped; finished in 15.17ms (21.40ms CPU time)
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: register the Chainlink HBAR/USD feed when the diamond is deployed"
```

---

### Task 18: Record the deployment for the frontend

**Files:**
- Test: `packages/foundry/test/DeployDiamond.t.sol`
- Modify: `packages/foundry/script/DeployDiamond.s.sol`

Scaffold-HBAR's generator finds contracts in Forge's broadcast files. A Lattice diamond is created inside a factory call, so it never appears there. The deploy script therefore writes its own record: the diamond's address, its facet names, and the selectors cut for each one. Task 20 turns that record into the frontend's `Diamond` contract.

**Step 1: Write the failing test**

Edit `packages/foundry/test/DeployDiamond.t.sol`.

Edit 1 of 3. Replace:

```solidity
/// @dev Opens the step `run()` performs after the diamond exists, so it can be tested without a broadcast.
```

with:

```solidity
/// @dev Opens the two steps `run()` performs after the diamond exists, so they can be tested without a broadcast.
```

Edit 2 of 3. After:

```solidity
        _registerHbarUsdFeed(diamond);
    }
```

insert:

```solidity

    function writeRecord(address diamond, string[] memory names, FacetCut[] memory cuts) external {
        _writeRecord(diamond, names, cuts);
    }
```

Edit 3 of 3. After:

```solidity
        assertEq(maxStaleness, vm.envOr("HBAR_USD_MAX_STALENESS", uint256(365 days)));
    }
```

insert:

```solidity

    function test_writeRecord_savesWhatTheFrontendNeeds() public {
        (address diamond, string[] memory names, FacetCut[] memory cuts) = _diamond(recipe);
        string memory path = string.concat("deployments/diamond/", vm.toString(block.chainid), ".json");

        deployer.writeRecord(diamond, names, cuts);
        string memory record = vm.readFile(path);
        vm.removeFile(path);

        assertEq(vm.parseJsonAddress(record, ".address"), diamond);
        assertEq(vm.parseJsonUint(record, ".deployedOnBlock"), block.number);
        assertEq(vm.parseJsonStringArray(record, ".facets").length, 9);
        string[] memory htsSelectors = vm.parseJsonStringArray(record, ".selectors.HTSAdapter");
        assertEq(htsSelectors.length, 13);
        assertEq(htsSelectors[0], vm.toString(abi.encodePacked(IHTSAdapter.associateToken.selector)));
        assertEq(vm.parseJsonStringArray(record, ".selectors.TokenSale").length, 6);
    }
```

**Step 2: Run test to verify it fails**

Run: `(cd packages/foundry && forge test --match-contract DeployDiamondTest)`

Expected: FAIL. Compilation stops: `_writeRecord` is not declared.

```text
Error (7576): Undeclared identifier. Did you mean "writeRecord"?
23 |         _writeRecord(diamond, names, cuts);
```

**Step 3: Write minimal implementation**

Edit `packages/foundry/script/DeployDiamond.s.sol`.

Edit 1 of 3. Replace:

```solidity
        diamond = assemble(json, deployer);
```

with:

```solidity
        (string[] memory names, FacetCut[] memory cuts, address[] memory inits, bytes[] memory calls) =
            build(json, deployer);
        diamond = _assembleMulti(cuts, inits, calls);
```

Edit 2 of 3. Before:

```solidity
        console.log("Diamond deployed at", diamond);
```

insert:

```solidity
        _writeRecord(diamond, names, cuts);
```

Edit 3 of 3. After:

```solidity
            .registerFeed(HBAR_USD, mainnet ? HBAR_USD_FEED_MAINNET : HBAR_USD_FEED_TESTNET, uint48(maxStaleness));
    }
```

insert:

```solidity

    /// @dev What `scripts-js/generateTsAbis.js` needs to give the frontend one `Diamond` contract: the address,
    ///      the facet names, and the selectors each facet serves after `exclude` and `owners` were applied.
    function _writeRecord(address diamond, string[] memory names, FacetCut[] memory cuts) internal {
        string memory selectors;
        for (uint256 i; i < names.length; ++i) {
            bytes4[] memory cut = cuts[i].functionSelectors;
            string[] memory hexes = new string[](cut.length);
            for (uint256 j; j < cut.length; ++j) {
                hexes[j] = vm.toString(abi.encodePacked(cut[j]));
            }
            selectors = vm.serializeString("selectors", names[i], hexes);
        }
        vm.serializeAddress("record", "address", diamond);
        vm.serializeUint("record", "deployedOnBlock", block.number);
        vm.serializeString("record", "facets", names);
        string memory record = vm.serializeString("record", "selectors", selectors);

        vm.createDir("deployments/diamond", true);
        vm.writeJson(record, string.concat("deployments/diamond/", vm.toString(block.chainid), ".json"));
    }
```

**Step 4: Run test to verify it passes**

Run: `(cd packages/foundry && forge test)`

Expected: PASS. Thirty-two tests pass across the three suites.

```text
Ran 3 test suites in 34.05ms (45.45ms CPU time): 32 tests passed, 0 failed, 0 skipped (32 total tests)
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: record the deployed diamond for the frontend generator"
```

---

## Phase 2: One contract for the frontend, and the first testnet deployment

### Task 19: Merge facet ABIs into one Diamond ABI

**Files:**
- Modify: `packages/foundry/package.json`
- Test: `packages/foundry/scripts-js/diamondAbi.test.js`
- Create: `packages/foundry/scripts-js/diamondAbi.js`

The frontend should see the diamond as one contract named `Diamond`. Its ABI is the union of the facets' ABIs, restricted to the selectors that were actually cut: a function a recipe excluded, or gave to another facet, must not appear, and `exportSelectors()` is never cut at all.

Script helpers are plain ES modules in `scripts-js`, tested with Node's built-in test runner. Keep that folder flat: `yarn lint` checks it with the shell glob `./scripts-js/**/*.js`.

**Step 1: Write the failing test**

`yarn foundry:test` should run the script tests after the Forge tests.

Edit `packages/foundry/package.json`.

Replace:

```json
    "test": "forge test",
```

with:

```json
    "test": "forge test && yarn test:scripts",
    "test:scripts": "node --test scripts-js/*.test.js",
```

Create `packages/foundry/scripts-js/diamondAbi.test.js`:

```javascript
import { test } from "node:test";
import assert from "node:assert/strict";
import { mergeDiamondAbi, signatureOf } from "./diamondAbi.js";

const fn = (name, inputs = []) => ({
  type: "function",
  name,
  inputs,
  outputs: [],
  stateMutability: "nonpayable",
});
const event = (name) => ({ type: "event", name, inputs: [], anonymous: false });

test("signatureOf expands tuples the way Solidity does", () => {
  const diamondCut = fn("diamondCut", [
    {
      name: "_diamondCut",
      type: "tuple[]",
      components: [
        { name: "facetAddress", type: "address" },
        { name: "action", type: "uint8" },
        { name: "functionSelectors", type: "bytes4[]" },
      ],
    },
    { name: "_init", type: "address" },
    { name: "_calldata", type: "bytes" },
  ]);

  assert.equal(
    signatureOf(diamondCut),
    "diamondCut((address,uint8,bytes4[])[],address,bytes)"
  );
});

test("mergeDiamondAbi keeps only the functions each facet serves", () => {
  const oracle = {
    abi: [
      fn("latestAnswer", [{ name: "key", type: "bytes32" }]),
      fn("unregisterFeed", [{ name: "key", type: "bytes32" }]),
      fn("exportSelectors"),
      event("FeedRegistered"),
    ],
    methodIdentifiers: {
      "latestAnswer(bytes32)": "084d4783",
      "unregisterFeed(bytes32)": "2a589908",
      "exportSelectors()": "0ef22643",
    },
    selectors: ["0x084D4783"], // unregisterFeed was excluded by the recipe
  };

  const names = mergeDiamondAbi([oracle]).map((entry) => entry.name);

  assert.deepEqual(names, ["latestAnswer", "FeedRegistered"]);
});

test("mergeDiamondAbi lists an event or error shared by two facets once", () => {
  const facet = (selector, name) => ({
    abi: [fn(name), event("RoleGranted")],
    methodIdentifiers: { [`${name}()`]: selector },
    selectors: [`0x${selector}`],
  });

  const merged = mergeDiamondAbi([
    facet("aaaaaaaa", "pause"),
    facet("bbbbbbbb", "unpause"),
  ]);

  assert.deepEqual(
    merged.map((entry) => entry.name),
    ["pause", "RoleGranted", "unpause"]
  );
});

test("mergeDiamondAbi drops constructors", () => {
  const facet = {
    abi: [{ type: "constructor", inputs: [] }, { type: "receive" }],
    methodIdentifiers: {},
    selectors: ["0x00000000"],
  };

  assert.deepEqual(mergeDiamondAbi([facet]), [{ type: "receive" }]);
});
```

**Step 2: Run test to verify it fails**

Run: `yarn workspace @sh/foundry test:scripts`

Expected: FAIL. `diamondAbi.js` does not exist.

```text
# Error [ERR_MODULE_NOT_FOUND]: Cannot find module '<repo>/packages/foundry/scripts-js/diamondAbi.js' imported from <repo>/packages/foundry/scripts-js/diamondAbi.test.js
# fail 1
```

**Step 3: Write minimal implementation**

Create `packages/foundry/scripts-js/diamondAbi.js`:

```javascript
// A Lattice diamond is many facets behind one address. These helpers turn the deploy script's record of
// that diamond into what the frontend wants: a single contract with a single ABI.

function canonicalType(parameter) {
  if (!parameter.type.startsWith("tuple")) return parameter.type;
  const components = parameter.components.map(canonicalType).join(",");
  return `(${components})${parameter.type.slice("tuple".length)}`;
}

/** The signature Solidity hashes into a selector, e.g. `diamondCut((address,uint8,bytes4[])[],address,bytes)`. */
export function signatureOf(abiFunction) {
  return `${abiFunction.name}(${abiFunction.inputs
    .map(canonicalType)
    .join(",")})`;
}

/**
 * One ABI for the whole diamond: every function a facet actually serves, plus all events and errors.
 * A function a recipe excluded, or gave to another facet, is left out, and so is `exportSelectors()`,
 * because neither is among the facet's cut selectors.
 *
 * @param facets `{ abi, methodIdentifiers, selectors }` per facet, where `abi` and `methodIdentifiers`
 *   come from the facet's Forge artifact and `selectors` are the ones cut into the diamond.
 */
export function mergeDiamondAbi(facets) {
  const seen = new Set();
  const merged = [];
  for (const { abi, methodIdentifiers, selectors } of facets) {
    const served = new Set(selectors.map((selector) => selector.toLowerCase()));
    for (const entry of abi) {
      if (entry.type === "constructor") continue;
      if (entry.type === "function") {
        const selector = `0x${methodIdentifiers[signatureOf(entry)]}`;
        if (!served.has(selector)) continue;
      }
      const key = JSON.stringify(entry);
      if (seen.has(key)) continue;
      seen.add(key);
      merged.push(entry);
    }
  }
  return merged;
}
```

**Step 4: Run test to verify it passes**

Run: `yarn workspace @sh/foundry test:scripts`

Expected: PASS. Four tests pass.

```text
# pass 4
# fail 0
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: merge facet ABIs into one Diamond ABI"
```

---

### Task 20: Give the frontend one Diamond contract

**Files:**
- Test: `packages/foundry/scripts-js/diamondAbi.test.js`
- Modify: `packages/foundry/scripts-js/diamondAbi.js`
- Modify: `packages/foundry/scripts-js/generateTsAbis.js`

`withDiamond` turns the deploy script's record into the chain's contract list: `Diamond` first, then whatever was deployed on its own, such as an upgrade facet waiting to be cut in. Deploy plumbing, initializers and the diamond's own facets are left out, because Forge's broadcast file lists every one of them as a contract creation. `generateTsAbis.js` keeps only the file handling.

**Step 1: Write the failing test**

Edit `packages/foundry/scripts-js/diamondAbi.test.js`.

Edit 1 of 2. Replace:

```javascript
import { mergeDiamondAbi, signatureOf } from "./diamondAbi.js";
```

with:

```javascript
import {
  isPlumbing,
  mergeDiamondAbi,
  signatureOf,
  withDiamond,
} from "./diamondAbi.js";
```

Edit 2 of 2. After:

```javascript
  assert.deepEqual(mergeDiamondAbi([facet]), [{ type: "receive" }]);
});
```

insert:

```javascript

test("isPlumbing hides deploy helpers, initializers and the diamond's own facets", () => {
  const facets = ["HTSAdapter", "TokenSale"];

  assert.equal(isPlumbing("LatticeFactory", facets), true);
  assert.equal(isPlumbing("TokenSaleInit", facets), true);
  assert.equal(isPlumbing("TokenSale", facets), true);
  assert.equal(isPlumbing("TokenSaleV2", facets), false);
});

test("withDiamond gives the chain one Diamond and keeps what was deployed on its own", () => {
  const artifacts = {
    TokenSale: {
      abi: [fn("buy"), event("TokensPurchased")],
      methodIdentifiers: { "buy()": "08bf598d" },
    },
  };
  const record = {
    address: "0xD1a0000000000000000000000000000000000000",
    deployedOnBlock: 42,
    facets: ["TokenSale"],
    selectors: { TokenSale: ["0x08bf598d"] },
  };
  const broadcast = {
    TokenSale: { address: "0x1" },
    TokenSaleInit: { address: "0x2" },
    LatticeFactory: { address: "0x3" },
    TokenSaleV2: { address: "0x4" },
  };

  const contracts = withDiamond(broadcast, record, (name) => artifacts[name]);

  assert.deepEqual(Object.keys(contracts), ["Diamond", "TokenSaleV2"]);
  assert.deepEqual(contracts.Diamond, {
    address: record.address,
    abi: artifacts.TokenSale.abi,
    inheritedFunctions: {},
    deployedOnBlock: 42,
  });
});
```

**Step 2: Run test to verify it fails**

Run: `yarn workspace @sh/foundry test:scripts`

Expected: FAIL. `diamondAbi.js` exports neither `isPlumbing` nor `withDiamond`.

```text
# SyntaxError: The requested module './diamondAbi.js' does not provide an export named 'isPlumbing'
# fail 1
```

**Step 3: Write minimal implementation**

Edit `packages/foundry/scripts-js/diamondAbi.js`.

Edit 1 of 2. After:

```javascript
// that diamond into what the frontend wants: a single contract with a single ABI.
```

insert:

```javascript

/** Contracts a Lattice deploy creates along the way that the app never calls. */
const DEPLOY_PLUMBING = new Set([
  "LatticeRegistry",
  "LatticeFactory",
  "MultiInit",
]);

/**
 * True for a contract the frontend should not list on its own: deploy plumbing, an initializer,
 * or a facet that is already reachable through the diamond.
 */
export function isPlumbing(contractName, facetNames) {
  return (
    DEPLOY_PLUMBING.has(contractName) ||
    contractName.endsWith("Init") ||
    facetNames.includes(contractName)
  );
}
```

Edit 2 of 2. After:

```javascript
  return merged;
}
```

insert:

```javascript

/**
 * A chain's contracts as the frontend should see them: one `Diamond`, followed by whatever was deployed
 * on its own (an upgrade facet waiting to be cut in, for example).
 *
 * @param contracts what the broadcast files list for the chain, keyed by contract name
 * @param record the deploy script's `deployments/diamond/<chainId>.json`
 * @param artifactOf returns a contract's Forge artifact by name
 */
export function withDiamond(contracts, record, artifactOf) {
  const facets = record.facets.map((name) => {
    const { abi, methodIdentifiers } = artifactOf(name);
    return { abi, methodIdentifiers, selectors: record.selectors[name] };
  });
  const standalone = Object.entries(contracts).filter(
    ([name]) => !isPlumbing(name, record.facets)
  );
  return {
    Diamond: {
      address: record.address,
      abi: mergeDiamondAbi(facets),
      inheritedFunctions: {},
      deployedOnBlock: record.deployedOnBlock,
    },
    ...Object.fromEntries(standalone),
  };
}
```

Edit `packages/foundry/scripts-js/generateTsAbis.js`.

Edit 1 of 2. After:

```javascript
import { format } from "prettier";
```

insert:

```javascript
import { withDiamond } from "./diamondAbi.js";
```

Edit 2 of 2. Before:

```javascript

  // Resolve nextjs contracts dir from this package (packages/foundry/scripts-js -> packages/nextjs/contracts)
```

insert:

```javascript

  // A Lattice diamond is created inside a factory call, so the broadcast never lists it as a contract
  // creation. The deploy script records it in deployments/diamond/<chainId>.json instead. Give the
  // frontend one `Diamond` contract per chain whose ABI is the union of what its facets serve.
  const diamondRecordsPath = join(current_path_to_deployments, "diamond");
  if (existsSync(diamondRecordsPath)) {
    getFiles(diamondRecordsPath).forEach((file) => {
      if (!file.endsWith(".json")) return;
      const chainId = file.slice(0, -5);
      const record = JSON.parse(readFileSync(join(diamondRecordsPath, file)));
      allGeneratedContracts[chainId] = withDiamond(
        allGeneratedContracts[chainId] ?? {},
        record,
        getArtifactOfContract
      );
    });
  }
```

**Step 4: Run test to verify it passes**

Run: `yarn workspace @sh/foundry test:scripts`

Expected: PASS. Six tests pass. The file handling in `generateTsAbis.js` is exercised by the deployment in Task 22.

```text
# pass 6
# fail 0
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: give the frontend one Diamond contract built from the deployment record"
```

---

### Task 21: Warn before a deploy that Foundry 1.8 cannot finish

**Files:**
- Test: `packages/foundry/scripts-js/forgeVersion.test.js`
- Create: `packages/foundry/scripts-js/forgeVersion.js`
- Modify: `packages/foundry/scripts-js/parseArgs.js`

On Foundry 1.8 `forge script` asks Hedera's relay for account state by block hash, the relay answers `-32602 Invalid parameter 1`, and nothing is sent. A developer who has never seen that error will not connect it to their Foundry version, so the deploy command says so first. It warns and carries on, because a later relay release may accept the request.

**Step 1: Write the failing test**

Create `packages/foundry/scripts-js/forgeVersion.test.js`:

```javascript
import { test } from "node:test";
import assert from "node:assert/strict";
import { relayWarning } from "./forgeVersion.js";

const forge = (version) =>
  `forge Version: ${version}\nCommit SHA: 982849d3140c01fd3b72905759581a132df7aa98`;

test("warns when forge 1.8 or newer deploys to Hedera", () => {
  assert.match(relayWarning(forge("1.8.1"), "hedera_testnet"), /forge 1\.8\.1/);
  assert.match(relayWarning(forge("1.8.0"), "hedera_mainnet"), /v1\.7\.1/);
  assert.match(relayWarning(forge("2.0.0"), "hedera_testnet"), /forge 2\.0\.0/);
});

test("stays quiet for a forge that can reach the relay", () => {
  assert.equal(relayWarning(forge("1.7.1"), "hedera_testnet"), null);
  assert.equal(relayWarning(forge("1.5.1-stable"), "hedera_testnet"), null);
});

test("stays quiet off Hedera and when the version cannot be read", () => {
  assert.equal(relayWarning(forge("1.8.1"), "localhost"), null);
  assert.equal(relayWarning("", "hedera_testnet"), null);
});
```

**Step 2: Run test to verify it fails**

Run: `yarn workspace @sh/foundry test:scripts`

Expected: FAIL. `forgeVersion.js` does not exist.

```text
# Error [ERR_MODULE_NOT_FOUND]: Cannot find module '<repo>/packages/foundry/scripts-js/forgeVersion.js' imported from <repo>/packages/foundry/scripts-js/forgeVersion.test.js
# fail 1
```

**Step 3: Write minimal implementation**

Create `packages/foundry/scripts-js/forgeVersion.js`:

```javascript
// Forge 1.8 asks Hedera's JSON-RPC relay for account state by block hash (EIP-1898). The relay only accepts
// a block number or tag, so `forge script` fails before it sends anything. Forge 1.7.1 is unaffected.
// Tracked in https://github.com/hiero-ledger/hiero-json-rpc-relay/issues/5826.
const FIRST_AFFECTED = [1, 8, 0];

/**
 * A warning to print before deploying, or null when there is nothing to warn about.
 *
 * @param forgeVersionOutput what `forge --version` printed
 * @param network the `--network` being deployed to
 */
export function relayWarning(forgeVersionOutput, network) {
  if (!network.startsWith("hedera_")) return null;
  const match = forgeVersionOutput.match(/(\d+)\.(\d+)\.(\d+)/);
  if (!match) return null;

  const version = match.slice(1).map(Number);
  for (let i = 0; i < FIRST_AFFECTED.length; i++) {
    if (version[i] > FIRST_AFFECTED[i]) break;
    if (version[i] < FIRST_AFFECTED[i]) return null;
  }

  return [
    `Warning: forge ${version.join(".")} may not be able to deploy to Hedera.`,
    "   If the deploy stops with `-32602 Invalid parameter 1`, switch to Foundry 1.7.1 and run it again:",
    "     foundryup --install v1.7.1",
    "   Details: https://github.com/hiero-ledger/hiero-json-rpc-relay/issues/5826",
  ].join("\n");
}
```

Print the warning just before the deploy starts, and make the `--help` examples name scripts that exist in this template.

Edit `packages/foundry/scripts-js/parseArgs.js`.

Edit 1 of 3. After:

```javascript
import { selectOrCreateKeystore } from "./selectOrCreateKeystore.js";
```

insert:

```javascript
import { relayWarning } from "./forgeVersion.js";
```

Edit 2 of 3. Replace:

```javascript
  yarn deploy --file DeployHederaToken.s.sol --network hedera_testnet
  yarn deploy --network hedera_testnet --keystore my-account
  yarn deploy --file DeployHederaToken.s.sol
  yarn deploy
```

with:

```javascript
  yarn deploy --network hedera_testnet
  yarn deploy --network hedera_testnet --keystore my-account
  yarn deploy --file DeployTokenSaleV2.s.sol --network hedera_testnet
```

Edit 3 of 3. Before:

```javascript

// Set environment variables for the make command
```

insert:

```javascript

const forgeVersion = spawnSync("forge", ["--version"], { encoding: "utf8" });
const warning = relayWarning(forgeVersion.stdout ?? "", network);
if (warning) console.log(`\n${warning}\n`);
```

**Step 4: Run test to verify it passes**

Run: `yarn workspace @sh/foundry test:scripts && yarn foundry:deploy --help`

Expected: PASS. Nine tests pass, and the help text still prints, which shows `parseArgs.js` loads.

```text
# pass 9
# fail 0
yarn deploy --file DeployTokenSaleV2.s.sol --network hedera_testnet
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: warn when the installed Foundry cannot deploy to Hedera"
```

---

### Task 22: Deploy the reference diamond to Hedera testnet

**Files:**
- Modify: `packages/nextjs/contracts/deployedContracts.ts` (generated)
- Not committed: `packages/foundry/.env`, `packages/foundry/broadcast/`, `packages/foundry/deployments/`

This is the first contact with the real network, placed here on purpose: everything after it (the app, the documents, the evidence) depends on a working deployment, and this is where anything the sandbox could not check will show up. The diamond deployed here is the one the template ships pointing at.

**Needs David:** a funded testnet key. Ask him to put `HEDERA_TESTNET_PK=0x<key>` in `packages/foundry/.env`: the hex form of an ECDSA key, 64 characters after `0x`, not the DER form. The install created that file; the line is added to it. It is git-ignored. Never print the key, never pass it as a literal on a command line, never commit it, and do not open the file to check it: step 3a checks the key by deriving its address. This task spends about 35 to 40 HBAR, and the README will tell users to have about 60; the [faucet](https://portal.hedera.com/faucet) gives 100 per day. Lattice's probe reads the same variable from `../lattice/.env`, so David may have a funded key there to copy across himself.

Every command block in this task starts from the repository root with this line, which loads the key into the shell without showing it:

```bash
cd packages/foundry && set -a && . ./.env && set +a && RPC=https://testnet.hashio.io/api
```

**Step 1: Write the failing test**

The check is the gate's evidence line:

```bash
bash scripts/gate.sh static | grep 'points at'
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/gate.sh static | grep 'points at'`

Expected: FAIL. `FAIL  the app points at a diamond on Hedera testnet`.

**Step 3: Write minimal implementation**

**3a. Confirm the toolchain, the account and the feed.** Nothing here costs HBAR.

```bash
cd packages/foundry && set -a && . ./.env && set +a && RPC=https://testnet.hashio.io/api
forge --version | head -n 1
DEPLOYER=$(cast wallet address --private-key "$HEDERA_TESTNET_PK")
echo "$DEPLOYER"
cast balance "$DEPLOYER" --ether --rpc-url $RPC
cast call 0x59bC155EB6c6C415fE43255aF66EcF0523c92B4a "decimals()(uint8)" --rpc-url $RPC
cast call 0x59bC155EB6c6C415fE43255aF66EcF0523c92B4a \
  "latestRoundData()(uint80,int256,uint256,uint256,uint80)" --rpc-url $RPC
```

Expected: `forge Version: 1.7.1`; a balance of 60 or more (write it down: Task 35 checks the README's `about 60 HBAR` against what this task spends); `8`; and a round whose second value is positive (HBAR/USD with 8 decimals) and whose fourth value, `updatedAt`, is a Unix time within the last 365 days. If the feed has no usable answer, stop and tell David: the sale cannot quote without it.

**3b. Deploy.** This is the command `yarn foundry:deploy --network hedera_testnet` runs, with the key from `.env` in place of the keystore password prompt, which needs a terminal.

```bash
cd packages/foundry && set -a && . ./.env && set +a && RPC=https://testnet.hashio.io/api
mkdir -p deployments
forge script script/Deploy.s.sol --rpc-url $RPC --private-key "$HEDERA_TESTNET_PK" \
  --broadcast --ffi --slow --legacy > deployments/deploy.log 2>&1; tail -n 25 deployments/deploy.log
node scripts-js/generateTsAbis.js
```

Expected: `Diamond deployed at 0x...`, `ONCHAIN EXECUTION COMPLETE & SUCCESSFUL.`, then the generator's `Updated TypeScript contract definition file` line. The run sends up to 18 transactions and takes a few minutes with `--slow`.

If it does not succeed:

| You see | Do |
| --- | --- |
| `-32602 Invalid parameter 1` | The shell is not using Foundry 1.7.1. Run `foundryup --use v1.7.1` and retry. |
| `Requested resource not found. address '0x...'` | The account does not exist on Hedera yet. Fund it from the faucet and retry. |
| A transaction to `0x4e59b44847b379578588920cA78FbF26c0B4956C` fails, or `BaseDeploy: facet deployed != predicted` | Facet deployment through the deterministic proxy did not work through the relay. In `build()` replace `_facet(base[i])` with `deployCode(string.concat(base[i], ".sol:", base[i]))` and `_facet("HTSAdapter")` with `deployCode("HTSAdapter.sol:HTSAdapter")`, delete `test_build_revertsWhenAFacetIsNotALatticeFacet` (its message came from `_facet`) together with its row in the README's error table, rerun `yarn foundry:test`, then retry. Tell David: this is a Lattice finding. |
| It stops part-way (rate limit, timeout) | Rerun the same command. Facets that already exist at their addresses are reused. |
| A transaction fails with `INSUFFICIENT_GAS`, or the log shows it used its whole gas limit | Forge sets each limit to 130% of what its local simulation used, and the network counted more. Testnet moved from version 0.76 to 0.77 after Lattice's probe ran. Rerun the same command with `--gas-estimate-multiplier 200` added. Only gas that is used is charged. |
| Anything else | Stop and show David the last 40 lines of `deployments/deploy.log`. |

**3c. Create the token.** `forge script` simulates locally before it sends, and no local EVM can run the Hedera Token Service, so the token is created by its own transaction. `--value 20ether` sends 20 HBAR: over JSON-RPC a value is in weibars, 18 decimals. Hedera deducts only the creation fee ([HIP-358](https://hips.hedera.com/hip/hip-358)); the rest should stay in the diamond.

```bash
cd packages/foundry && set -a && . ./.env && set +a && RPC=https://testnet.hashio.io/api
DIAMOND=$(node -p "require('./deployments/diamond/296.json').address")
cast send "$DIAMOND" "launchSale(string,string,string,int32,int64,uint256)" \
  "Lattice Sale Token" LST "Launched with Lattice Hedera Template" 8 100000000000000 50000000000000000 \
  --value 20ether --gas-limit 1000000 --legacy --rpc-url $RPC --private-key "$HEDERA_TESTNET_PK" \
  --json > deployments/launch.json
node -p "const r = require('./deployments/launch.json'); r.status + ' ' + r.transactionHash"
cast call "$DIAMOND" "saleInfo()(address,int32,uint256,bytes32,int64,uint256)" --rpc-url $RPC
cast call "$DIAMOND" "quote(uint256)(int64)" 100000000 --rpc-url $RPC
cast balance "$DIAMOND" --ether --rpc-url $RPC
```

Expected: `0x1` and a transaction hash; a first `saleInfo` value that is not the zero address (the HTS token); a positive quote, the token units one HBAR buys, which proves the diamond is reading Chainlink; and a diamond balance of 20 HBAR less the creation fee, about 4 HBAR if the fee is the 15.9 HBAR Lattice's probe paid. That is 1,000,000 LST with 8 decimals at $0.05 each. At the feed's price on 3 October, $0.1016, the quote for one HBAR is about `203000000`, which is 2.03 LST. If the diamond's balance is 0, the unused HBAR did not stay with it: tell David, and in Task 35 drop the README sentence that says it does, together with the matching sentence under the Admin card's launch button.

**3d. Buy once from the terminal.** An account must associate with an HTS token before it can receive it.

```bash
cd packages/foundry && set -a && . ./.env && set +a && RPC=https://testnet.hashio.io/api
DIAMOND=$(node -p "require('./deployments/diamond/296.json').address")
DEPLOYER=$(cast wallet address --private-key "$HEDERA_TESTNET_PK")
TOKEN=$(cast call "$DIAMOND" "saleInfo()(address,int32,uint256,bytes32,int64,uint256)" --rpc-url $RPC | head -n 1)
cast send "$TOKEN" "associate()" --gas-limit 1000000 --legacy --rpc-url $RPC \
  --private-key "$HEDERA_TESTNET_PK" --json > deployments/associate.json
cast send "$DIAMOND" "buy(int64)" 0 --value 1ether --gas-limit 1000000 --legacy --rpc-url $RPC \
  --private-key "$HEDERA_TESTNET_PK" --json > deployments/buy.json
node -p "require('./deployments/buy.json').status"
cast call "$TOKEN" "balanceOf(address)(uint256)" "$DEPLOYER" --rpc-url $RPC
cast balance "$DEPLOYER" --ether --rpc-url $RPC
```

Expected: `0x1`, then a token balance equal to the quote from 3c (give or take an oracle update between the two calls). Write down the last balance too: the difference from 3a is what a full first deployment and launch cost.

**If a transaction in 3c or 3d fails.** A reverted transaction still has a receipt, with status `0x0`, but the relay does not say why it reverted. The mirror node does, a few seconds later. This lists the diamond's five most recent calls, newest first, each with its selector, its revert data or `ok`, its gas and its hash:

```bash
cd packages/foundry && MIRROR=https://testnet.mirrornode.hedera.com/api/v1
DIAMOND=$(node -p "require('./deployments/diamond/296.json').address")
curl -s "$MIRROR/contracts/$DIAMOND/results?limit=5&order=desc" | node -p "JSON.parse(require('fs').readFileSync(0, 'utf8')).results.map(r => [r.function_parameters.slice(0, 10), r.error_message || 'ok', 'gas ' + r.gas_used + ' of ' + r.gas_limit, r.hash].join(' ')).join('\n')"
```

`associate()` is sent to the token, not to the diamond, so look that one up by the hash in `deployments/associate.json`: `curl -s "$MIRROR/contracts/results/<hash>"`, and read `result` and `error_message`.

The revert data is hex and starts with an error's 4-byte selector. `forge inspect TokenSale errors` lists every error the sale can raise with its selector, Lattice's HTS errors included, and `cast decode-error --sig "<error signature>" <data>` prints the arguments. `HTSCallFailed(bytes4,int64)` is `0xa6cf79a0`; its last argument is the HTS response code. If the hex starts with no selector in that list, it may be a status name: `cast to-ascii <data>` shows it.

| You see | Cause | Do |
| --- | --- | --- |
| `launchSale` reverts with `HTSCallFailed(<selector>, 9)` | Code 9 is `INSUFFICIENT_TX_FEE`: creating a token costs more than 20 HBAR at the network's current rate. Lattice's probe paid about 15.9 on 12 September. | Send it again with `--value 40ether`. What is not used stays in the diamond. Then write 40 where later tasks write 20 for this fee: `CREATION_FEE_HBAR` in `AdminCard.tsx` (Task 27), and `--value 20ether` and `sends 20 HBAR` in the README (Task 35). Tell David. |
| `launchSale` fails with `INSUFFICIENT_GAS`, or `gas_used` equals `gas_limit` | The limit was too low. The probe's creation used 239,060 gas, on an earlier network version. | Send it again with `--gas-limit 3000000`. |
| `buy` reverts with `TokenSaleBuyerNotAssociated` | `associate()` did not succeed. | Read `deployments/associate.json` and its result on the mirror node, then send `associate()` again. |
| `buy` reverts with `TokenSaleTransferFailed(<code>)` although the buyer is associated | HTS refused a transfer made from inside a facet. This is the first live run of that path. | Stop and show David the code. The first thing to try is in `TokenSaleLib._transferFromTreasury`: send the tokens with the token's own ERC-20 `transfer(to, amount)` in place of `transferToken` on `0x167`. The tests' HTS mock must then answer `transfer` as well, so with the deadline in view this is David's call. |
| `quote` or `buy` reverts with `ChainlinkStaleData` | The feed's last report is older than the limit registered at deploy time. | Check that `HBAR_USD_MAX_STALENESS` is not set in `.env`. With the 365-day default this should not happen: the feed reported on 3 October. |

**3e. See what changed.** Only the generated contract file should be modified:

```bash
git status --short packages/nextjs/contracts
```

Expected: ` M packages/nextjs/contracts/deployedContracts.ts`.

**Step 4: Run test to verify it passes**

Run:

```bash
bash scripts/gate.sh static | grep 'points at' && yarn next:check-types
```

Expected: PASS. `PASS  the app points at a diamond on Hedera testnet`, and the type check exits 0 against the generated ABI.

**Step 5: Commit**

```bash
git add packages/nextjs/contracts/deployedContracts.ts
git commit -m "feat: point the app at the reference diamond on Hedera testnet"
```

---

## Phase 3: The app

### Task 23: HBAR unit conversion, test-first

**Files:**
- Modify: `packages/nextjs/package.json`
- Modify: `package.json`
- Create: `packages/nextjs/vitest.config.ts`
- Test: `packages/nextjs/utils/sale/units.test.ts`
- Create: `packages/nextjs/utils/sale/units.ts`
- Modify: `yarn.lock` (by Yarn)

The classic first bug on Hedera is mixing the two units of HBAR: contracts see tinybars (8 decimals), a transaction's `value` is weibars (18 decimals). The app converts in exactly one module, and that module is tested. Vitest is pinned to major 3 because the project supports Node 20.

The Next.js package has no test runner yet, so adding one is part of writing the first test.

**Step 1: Write the failing test**

Install Vitest in the Next.js package:

```bash
yarn workspace @sh/nextjs add -D vitest@^3.2.4
```

Add the `test` script:

Edit `packages/nextjs/package.json`.

Replace:

```json
    "start": "next dev"
```

with:

```json
    "start": "next dev",
    "test": "vitest run"
```

And a root alias, beside the other `next:` scripts:

Edit `package.json`.

After:

```json
    "next:start": "yarn workspace @sh/nextjs start",
```

insert:

```json
    "next:test": "yarn workspace @sh/nextjs test",
```

Create `packages/nextjs/vitest.config.ts`:

```typescript
import path from "path";
import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    alias: { "~~": path.resolve(__dirname) },
  },
  test: {
    include: ["utils/**/*.test.ts"],
  },
});
```

Create `packages/nextjs/utils/sale/units.test.ts`:

```typescript
import { formatAmount, hbarToTinybars, minTokensOut, parsePositive, tinybarsToWeibars } from "./units";
import { parseEther } from "viem";
import { describe, expect, it } from "vitest";

describe("hbarToTinybars", () => {
  it("parses a decimal HBAR amount into 8-decimal tinybars", () => {
    expect(hbarToTinybars("1.5")).toBe(150_000_000n);
  });

  it("returns undefined for input that is not a positive amount", () => {
    expect(hbarToTinybars("")).toBeUndefined();
    expect(hbarToTinybars("0")).toBeUndefined();
    expect(hbarToTinybars("abc")).toBeUndefined();
  });

  it("rounds away more precision than a tinybar holds", () => {
    expect(hbarToTinybars("0.000000019")).toBe(2n);
  });
});

describe("tinybarsToWeibars", () => {
  it("gives the 18-decimal value a wallet sends for that many tinybars", () => {
    expect(tinybarsToWeibars(150_000_000n)).toBe(parseEther("1.5"));
  });
});

describe("parsePositive", () => {
  it("scales by the given decimals", () => {
    expect(parsePositive("0.05", 18)).toBe(50_000_000_000_000_000n);
    expect(parsePositive(" 1000 ", 8)).toBe(100_000_000_000n);
  });
});

describe("minTokensOut", () => {
  it("takes the slippage off the quote", () => {
    expect(minTokensOut(400_000_000n, 100n)).toBe(396_000_000n);
  });

  it("keeps the whole quote at zero slippage", () => {
    expect(minTokensOut(400_000_000n, 0n)).toBe(400_000_000n);
  });
});

describe("formatAmount", () => {
  it("shows an amount in whole units with a few decimals", () => {
    expect(formatAmount(123_456_789n, 8)).toBe("1.2346");
    expect(formatAmount(100_000_000_000_000n, 8)).toBe("1,000,000");
  });

  it("takes the number of decimals to show", () => {
    expect(formatAmount(50_000_000_000_000_000n, 18, 2)).toBe("0.05");
  });
});
```

**Step 2: Run test to verify it fails**

Run: `yarn next:test`

Expected: FAIL. `units.ts` does not exist.

```text
Error: Cannot find module './units' imported from '<repo>/packages/nextjs/utils/sale/units.test.ts'
Test Files  1 failed (1)
```

**Step 3: Write minimal implementation**

Create `packages/nextjs/utils/sale/units.ts`:

```typescript
import { formatUnits, parseUnits } from "viem";

/**
 * Hedera has two units for HBAR, and mixing them up is the classic first bug:
 * - inside the EVM, `msg.value` and every amount the sale contract takes or returns is in tinybars (8 decimals);
 * - over JSON-RPC, a transaction's `value` is in weibars (18 decimals), and the relay converts it.
 */
export const TINYBAR_DECIMALS = 8;
const WEIBARS_PER_TINYBAR = 10_000_000_000n;
const BPS = 10_000n;

/** Parses what a user typed, e.g. "1.5", into tinybars. Undefined for anything that is not a positive amount. */
export function hbarToTinybars(hbar: string): bigint | undefined {
  return parsePositive(hbar, TINYBAR_DECIMALS);
}

/** The `value` to put on a transaction that should arrive in the contract as `tinybars`. */
export function tinybarsToWeibars(tinybars: bigint): bigint {
  return tinybars * WEIBARS_PER_TINYBAR;
}

/** Parses a decimal amount, e.g. a token count or a USD price, into its smallest unit. */
export function parsePositive(amount: string, decimals: number): bigint | undefined {
  try {
    const value = parseUnits(amount.trim(), decimals);
    return value > 0n ? value : undefined;
  } catch {
    return undefined;
  }
}

/** The fewest tokens a buyer accepts when the quote may move by `slippageBps` before the transaction lands. */
export function minTokensOut(quotedTokens: bigint, slippageBps: bigint): bigint {
  return (quotedTokens * (BPS - slippageBps)) / BPS;
}

/** Formats an amount held in its smallest unit for display, e.g. 123456789n with 8 decimals as "1.2346". */
export function formatAmount(value: bigint, decimals: number, maximumFractionDigits = 4): string {
  return Number(formatUnits(value, decimals)).toLocaleString("en-US", { maximumFractionDigits });
}
```

**Step 4: Run test to verify it passes**

Run: `yarn next:test`

Expected: PASS. One test file passes.

```text
Test Files  1 passed (1)
Tests  9 passed (9)
```

**Step 5: Commit**

```bash
git add package.json yarn.lock packages/nextjs
git commit -m "feat: convert between HBAR units in one tested module"
```

---

### Task 24: Plan a diamond cut from a facet's exported selectors

**Files:**
- Test: `packages/nextjs/utils/diamond/planCut.test.ts`
- Create: `packages/nextjs/utils/diamond/planCut.ts`

The Upgrade box needs to turn "this facet" into `FacetCut` structs. A facet reports its selectors through ERC-8153 `exportSelectors()` as packed bytes. A selector the diamond already routes must be replaced, a new one added, and one that already points at the facet left alone. That decision is pure logic, so it lives in a tested module and the component only does the reading and the sending.

**Step 1: Write the failing test**

Create `packages/nextjs/utils/diamond/planCut.test.ts`:

```typescript
import { FacetCutAction, planCut, unpackSelectors } from "./planCut";
import { zeroAddress } from "viem";
import { describe, expect, it } from "vitest";

const OLD_FACET = "0x1111111111111111111111111111111111111111";
const NEW_FACET = "0x2222222222222222222222222222222222222222";

describe("unpackSelectors", () => {
  it("splits packed bytes into 4-byte selectors", () => {
    expect(unpackSelectors("0x08bf598ded1bd76c404f21a5")).toEqual(["0x08bf598d", "0xed1bd76c", "0x404f21a5"]);
  });

  it("returns nothing for empty bytes", () => {
    expect(unpackSelectors("0x")).toEqual([]);
  });

  it("rejects bytes that are not a whole number of selectors", () => {
    expect(() => unpackSelectors("0x08bf598ded")).toThrow("whole number of 4-byte selectors");
  });
});

describe("planCut", () => {
  it("replaces selectors the diamond already routes and adds the new ones", () => {
    const cuts = planCut(NEW_FACET, ["0x08bf598d", "0xed1bd76c", "0x404f21a5"], [OLD_FACET, OLD_FACET, zeroAddress]);

    expect(cuts).toEqual([
      { facetAddress: NEW_FACET, action: FacetCutAction.Replace, functionSelectors: ["0x08bf598d", "0xed1bd76c"] },
      { facetAddress: NEW_FACET, action: FacetCutAction.Add, functionSelectors: ["0x404f21a5"] },
    ]);
  });

  it("leaves out an action with no selectors", () => {
    const cuts = planCut(NEW_FACET, ["0x404f21a5"], [zeroAddress]);

    expect(cuts).toEqual([{ facetAddress: NEW_FACET, action: FacetCutAction.Add, functionSelectors: ["0x404f21a5"] }]);
  });

  it("plans nothing for a facet that is already mounted", () => {
    expect(planCut(NEW_FACET, ["0x08bf598d"], [NEW_FACET])).toEqual([]);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `yarn next:test`

Expected: FAIL. `planCut.ts` does not exist.

```text
Error: Cannot find module './planCut' imported from '<repo>/packages/nextjs/utils/diamond/planCut.test.ts'
Test Files  1 failed | 1 passed (2)
```

**Step 3: Write minimal implementation**

Create `packages/nextjs/utils/diamond/planCut.ts`:

```typescript
import { Address, Hex, isAddressEqual, size, slice, zeroAddress } from "viem";

/** EIP-2535 `FacetCutAction`. */
export const FacetCutAction = { Add: 0, Replace: 1, Remove: 2 } as const;

export type FacetCut = {
  facetAddress: Address;
  action: number;
  functionSelectors: Hex[];
};

/** Splits the bytes a facet returns from ERC-8153 `exportSelectors()` into its 4-byte selectors. */
export function unpackSelectors(packed: Hex): Hex[] {
  const count = size(packed) / 4;
  if (!Number.isInteger(count)) throw new Error("exportSelectors() must return a whole number of 4-byte selectors");
  return Array.from({ length: count }, (_, index) => slice(packed, index * 4, index * 4 + 4));
}

/**
 * The cuts that mount `facet` on a diamond: a selector the diamond already routes is replaced, a new one is
 * added, and one that already points at `facet` is left alone.
 *
 * @param selectors what the facet exports
 * @param routes where the diamond routes each of those selectors today (`facetAddress(selector)`), index-aligned
 */
export function planCut(facet: Address, selectors: Hex[], routes: Address[]): FacetCut[] {
  const add = selectors.filter((_, index) => isAddressEqual(routes[index], zeroAddress));
  const replace = selectors.filter(
    (_, index) => !isAddressEqual(routes[index], zeroAddress) && !isAddressEqual(routes[index], facet),
  );
  const cuts: FacetCut[] = [];
  if (replace.length > 0)
    cuts.push({ facetAddress: facet, action: FacetCutAction.Replace, functionSelectors: replace });
  if (add.length > 0) cuts.push({ facetAddress: facet, action: FacetCutAction.Add, functionSelectors: add });
  return cuts;
}
```

**Step 4: Run test to verify it passes**

Run: `yarn next:test`

Expected: PASS. Two test files pass.

```text
Test Files  2 passed (2)
Tests  15 passed (15)
```

**Step 5: Commit**

```bash
git add packages/nextjs
git commit -m "feat: plan Add and Replace cuts from a facet's exported selectors"
```

---

### Task 25: Name the selectors a diamond routes

**Files:**
- Test: `packages/nextjs/utils/diamond/selectorNames.test.ts`
- Create: `packages/nextjs/utils/diamond/selectorNames.ts`

The diamond's loupe reports raw 4-byte selectors. The facet table shows names instead, looked up in the ABIs the project already has.

**Step 1: Write the failing test**

Create `packages/nextjs/utils/diamond/selectorNames.test.ts`:

```typescript
import { selectorNames } from "./selectorNames";
import { parseAbi } from "viem";
import { describe, expect, it } from "vitest";

describe("selectorNames", () => {
  it("names the functions of every ABI it is given", () => {
    const names = selectorNames([
      parseAbi(["function buy(int64 minTokens) payable returns (int64)", "event SalePriceSet(uint256 priceUsd)"]),
      parseAbi(["function bonusBps() pure returns (uint256)"]),
    ]);

    expect(names.get("0x08bf598d")).toBe("buy");
    expect(names.get("0x404f21a5")).toBe("bonusBps");
    expect(names.size).toBe(3);
  });

  it("names the selector a diamond routes plain transfers through", () => {
    expect(selectorNames([]).get("0x00000000")).toBe("receive");
  });
});
```

**Step 2: Run test to verify it fails**

Run: `yarn next:test`

Expected: FAIL. `selectorNames.ts` does not exist.

```text
Error: Cannot find module './selectorNames' imported from '<repo>/packages/nextjs/utils/diamond/selectorNames.test.ts'
Test Files  1 failed | 2 passed (3)
```

**Step 3: Write minimal implementation**

Create `packages/nextjs/utils/diamond/selectorNames.ts`:

```typescript
import { Abi, Hex, toFunctionSelector } from "viem";

/** A Lattice diamond routes a plain HBAR transfer through this selector, to its Receive facet. */
const RECEIVE_SELECTOR = "0x00000000";

/** Maps every function selector found in `abis` to the function's name, for showing a diamond's routes. */
export function selectorNames(abis: Abi[]): Map<Hex, string> {
  const names = new Map<Hex, string>([[RECEIVE_SELECTOR, "receive"]]);
  for (const abi of abis) {
    for (const item of abi) {
      if (item.type === "function") names.set(toFunctionSelector(item), item.name);
    }
  }
  return names;
}
```

**Step 4: Run test to verify it passes**

Run: `yarn next:test`

Expected: PASS. Three test files, seventeen tests.

```text
Test Files  3 passed (3)
Tests  17 passed (17)
```

**Step 5: Commit**

```bash
git add packages/nextjs
git commit -m "feat: map function selectors to names for the facet table"
```

---

### Task 26: The sale page

**Files:**
- Modify: `packages/nextjs/app/page.tsx`
- Create: `packages/nextjs/utils/sale/hrc719.ts`
- Create: `packages/nextjs/hooks/useSale.ts`
- Create: `packages/nextjs/components/diamond/DiamondNotDeployed.tsx`
- Create: `packages/nextjs/components/sale/SaleCard.tsx`
- Modify: `packages/nextjs/app/layout.tsx`

Components have no unit tests in this project. What can go wrong in them is the wiring to the contract, and the compiler checks that: every hook call below is typed against the generated `Diamond` ABI, so a wrong function name or argument fails `yarn next:check-types`. The page that uses a component is written first, and the missing component is the failing check. Behaviour against the live diamond is checked by hand in Task 30.

Three things in `SaleCard` are specific to Hedera. The token's name, symbol and balances are read with the ERC-20 ABI at the token's own address, which every HTS token answers. Association uses the HIP-719 functions at that same address. And `bonusBps()` is read with an inline ABI, because a function added by a later cut is not in the generated ABI.

**Step 1: Write the failing test**

Replace the whole of `packages/nextjs/app/page.tsx` with:

```tsx
import Link from "next/link";
import type { NextPage } from "next";
import { SaleCard } from "~~/components/sale/SaleCard";

const Home: NextPage = () => {
  return (
    <div className="flex items-center flex-col grow">
      <div className="hedera-gradient dark:bg-none dark:bg-hedera-charcoal w-full py-12 px-5">
        <div className="max-w-2xl mx-auto text-center text-white">
          <h1 className="text-3xl font-bold m-0">An upgradeable token sale on Hedera</h1>
          <p className="m-0 mt-3 text-white/80">
            One Lattice diamond creates an HTS token, sells it for HBAR at a USD price from Chainlink, and can be
            upgraded while it runs.
          </p>
        </div>
      </div>

      <div className="w-full max-w-4xl mx-auto px-5 -mt-6 pb-16 flex flex-col gap-6">
        <SaleCard />

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300">
            <h3 className="font-bold text-lg m-0 mb-2">Inspect and upgrade the diamond</h3>
            <p className="text-base-content/70 text-sm m-0 mb-4">
              See which facet serves each function, then cut a new facet into the live contract.
            </p>
            <Link href="/diamond" className="btn btn-primary btn-sm">
              Open Diamond
            </Link>
          </div>
          <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300">
            <h3 className="font-bold text-lg m-0 mb-2">Call any function</h3>
            <p className="text-base-content/70 text-sm m-0 mb-4">
              Debug Contracts lists every function of every facet under one contract, <code>Diamond</code>.
            </p>
            <Link href="/debug" className="btn btn-primary btn-sm">
              Open Debug
            </Link>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Home;
```

**Step 2: Run test to verify it fails**

Run: `yarn next:check-types`

Expected: FAIL. The page imports a component that does not exist.

```text
app/page.tsx(3,26): error TS2307: Cannot find module '~~/components/sale/SaleCard' or its corresponding type declarations.
```

**Step 3: Write minimal implementation**

Create `packages/nextjs/utils/sale/hrc719.ts`:

```typescript
/**
 * HIP-719: every HTS token address answers these calls for the account that makes them, so a wallet can
 * associate itself with a token through an ordinary contract call.
 */
export const hrc719Abi = [
  {
    type: "function",
    name: "associate",
    inputs: [],
    outputs: [{ name: "responseCode", type: "uint256" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "isAssociated",
    inputs: [],
    outputs: [{ name: "associated", type: "bool" }],
    stateMutability: "view",
  },
] as const;
```

Create `packages/nextjs/hooks/useSale.ts`:

```typescript
import { Address, zeroAddress } from "viem";
import { useScaffoldReadContract } from "~~/hooks/scaffold-hbar";

/** The sale's on-chain configuration and totals, read from the diamond's `saleInfo()`. */
export function useSale() {
  const { data, isLoading } = useScaffoldReadContract({ contractName: "Diamond", functionName: "saleInfo" });
  const [token, decimals, priceUsd, feedKey, sold, raised] = data ?? [];

  return {
    isLoading,
    /** False until the admin has called `launchSale`. */
    isLaunched: token !== undefined && token !== zeroAddress,
    token: token as Address | undefined,
    decimals: decimals ?? 0,
    priceUsd: priceUsd ?? 0n,
    feedKey,
    sold: sold ?? 0n,
    raised: raised ?? 0n,
  };
}
```

Create `packages/nextjs/components/diamond/DiamondNotDeployed.tsx`:

```tsx
"use client";

import { useTargetNetwork } from "~~/hooks/scaffold-hbar";

/** Shown instead of a page's content when the wallet is on a network this project has no diamond on. */
export const DiamondNotDeployed = () => {
  const { targetNetwork } = useTargetNetwork();

  return (
    <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300 text-center">
      <h2 className="font-bold text-xl m-0">No diamond on {targetNetwork.name}</h2>
      <p className="text-base-content/70 m-0 mt-2">
        Switch your wallet to Hedera Testnet, or deploy your own with{" "}
        <code className="bg-base-200 px-1.5 py-0.5 rounded">yarn foundry:deploy --network hedera_testnet</code>.
      </p>
    </div>
  );
};
```

Create `packages/nextjs/components/sale/SaleCard.tsx`:

```tsx
"use client";

import { useState } from "react";
import { HbarInput, HederaPortalFaucet } from "@scaffold-hbar-ui/components";
import { erc20Abi, parseAbi, zeroAddress } from "viem";
import { useAccount, useReadContract, useReadContracts, useWriteContract } from "wagmi";
import { DiamondNotDeployed } from "~~/components/diamond/DiamondNotDeployed";
import {
  useDeployedContractInfo,
  useScaffoldReadContract,
  useScaffoldWriteContract,
  useTransactor,
} from "~~/hooks/scaffold-hbar";
import { useSale } from "~~/hooks/useSale";
import { hrc719Abi } from "~~/utils/sale/hrc719";
import { TINYBAR_DECIMALS, formatAmount, hbarToTinybars, minTokensOut, tinybarsToWeibars } from "~~/utils/sale/units";

/** Accept up to 1% fewer tokens than quoted if the oracle moves before the transaction lands. */
const SLIPPAGE_BPS = 100n;

/** Only a diamond that has been upgraded to TokenSaleV2 answers this; see the README's upgrade walkthrough. */
const bonusAbi = parseAbi(["function bonusBps() pure returns (uint256)"]);

export const SaleCard = () => {
  const { address } = useAccount();
  const sale = useSale();
  const { data: diamond, isLoading: isDiamondLoading } = useDeployedContractInfo({ contractName: "Diamond" });
  const [hbar, setHbar] = useState("");
  const tinybars = hbarToTinybars(hbar);

  const { data: hbarUsd } = useScaffoldReadContract({
    contractName: "Diamond",
    functionName: "latestAnswer",
    args: [sale.feedKey],
    query: { enabled: sale.isLaunched },
  });
  const { data: quote } = useScaffoldReadContract({
    contractName: "Diamond",
    functionName: "quote",
    args: [tinybars],
    query: { enabled: sale.isLaunched && tinybars !== undefined },
  });

  // An HTS token answers the ERC-20 read functions at its own address.
  const token = { address: sale.token, abi: erc20Abi } as const;
  const { data: tokenData, refetch: refetchToken } = useReadContracts({
    contracts: [
      { ...token, functionName: "name" },
      { ...token, functionName: "symbol" },
      { ...token, functionName: "balanceOf", args: [diamond?.address ?? zeroAddress] },
      { ...token, functionName: "balanceOf", args: [address ?? zeroAddress] },
    ],
    query: { enabled: sale.isLaunched && diamond !== undefined },
  });
  const [name, symbol, available, owned] = tokenData?.map(read => read.result) ?? [];

  const { data: isAssociated, refetch: refetchAssociation } = useReadContract({
    address: sale.token,
    abi: hrc719Abi,
    functionName: "isAssociated",
    account: address,
    query: { enabled: sale.isLaunched && address !== undefined },
  });

  const { data: bonusBps } = useReadContract({
    address: diamond?.address,
    abi: bonusAbi,
    functionName: "bonusBps",
    query: { enabled: diamond !== undefined, retry: false },
  });

  const transactor = useTransactor();
  const { writeContractAsync: writeToken, isPending: isAssociating } = useWriteContract();
  const { writeContractAsync: writeDiamond, isMining: isBuying } = useScaffoldWriteContract({
    contractName: "Diamond",
  });

  const associate = async () => {
    if (!sale.token) return;
    const tokenAddress = sale.token;
    await transactor(() => writeToken({ address: tokenAddress, abi: hrc719Abi, functionName: "associate" }));
    await refetchAssociation();
  };

  const buy = async () => {
    if (tinybars === undefined || quote === undefined) return;
    await writeDiamond({
      functionName: "buy",
      args: [minTokensOut(quote, SLIPPAGE_BPS)],
      // The contract sees tinybars; a transaction's value is denominated in weibars.
      value: tinybarsToWeibars(tinybars),
    });
    await refetchToken();
  };

  if (isDiamondLoading || sale.isLoading) {
    return <div className="h-64 rounded-2xl bg-base-200 animate-pulse" aria-hidden />;
  }

  if (!diamond) return <DiamondNotDeployed />;

  if (!sale.isLaunched) {
    return (
      <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300 text-center">
        <h2 className="font-bold text-xl m-0">No token on sale yet</h2>
        <p className="text-base-content/70 m-0 mt-2">
          The diamond is deployed, but its admin has not launched a sale. Connect the admin wallet to create the token.
        </p>
      </div>
    );
  }

  return (
    <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="font-bold text-xl m-0">
          {name ?? "Token"} <span className="text-base-content/60 font-normal">{symbol}</span>
        </h2>
        <div className="flex flex-wrap gap-2">
          {bonusBps !== undefined && <span className="badge badge-secondary">+{formatAmount(bonusBps, 2)}% bonus</span>}
          <span className="badge badge-primary badge-outline">
            ${formatAmount(sale.priceUsd, 18)} per {symbol ?? "token"}
          </span>
        </div>
      </div>

      <dl className="grid grid-cols-2 md:grid-cols-4 gap-4 my-6 text-sm">
        <Stat label="HBAR / USD (Chainlink)" value={hbarUsd !== undefined ? `$${formatAmount(hbarUsd, 18)}` : "…"} />
        <Stat label="Available" value={typeof available === "bigint" ? formatAmount(available, sale.decimals) : "…"} />
        <Stat label="Sold" value={formatAmount(sale.sold, sale.decimals)} />
        <Stat label="Raised" value={`${formatAmount(sale.raised, TINYBAR_DECIMALS)} HBAR`} />
      </dl>

      <label className="text-sm font-medium" htmlFor="hbar-amount">
        Pay with HBAR
      </label>
      <HbarInput name="hbar-amount" placeholder="0.0" onValueChange={({ valueInNative }) => setHbar(valueInNative)} />
      <p className="text-sm text-base-content/70 mt-2 mb-4">
        {quote !== undefined ? `You receive about ${formatAmount(quote, sale.decimals)} ${symbol ?? ""}` : " "}
      </p>

      <div className="flex flex-wrap items-center gap-3">
        {address && isAssociated !== true && (
          <button className="btn btn-secondary btn-sm" onClick={associate} disabled={isAssociating}>
            1. Associate {symbol ?? "token"}
          </button>
        )}
        <button className="btn btn-primary btn-sm" onClick={buy} disabled={!address || quote === undefined || isBuying}>
          {isAssociated === true ? "Buy" : "2. Buy"}
        </button>
        {address && typeof owned === "bigint" && (
          <span className="text-sm text-base-content/70">
            You hold {formatAmount(owned, sale.decimals)} {symbol}
          </span>
        )}
      </div>

      {address && isAssociated !== true && (
        <p className="text-xs text-base-content/60 mt-4 mb-0">
          On Hedera an account must associate with a token before it can receive it. Need testnet HBAR?{" "}
          <HederaPortalFaucet variant="link" label="Use the faucet" showIcon={false} />
        </p>
      )}
    </div>
  );
};

const Stat = ({ label, value }: { label: string; value: string }) => (
  <div>
    <dt className="text-base-content/60">{label}</dt>
    <dd className="m-0 font-semibold">{value}</dd>
  </div>
);
```

Give the app its own title:

Edit `packages/nextjs/app/layout.tsx`.

Replace:

```tsx
  title: "Scaffold-HBAR",
  description: "Built with Scaffold-HBAR",
```

with:

```tsx
  title: "Lattice Hedera Template",
  description: "An upgradeable HTS token sale on a Lattice diamond, priced by Chainlink",
```

**Step 4: Run test to verify it passes**

Run: `yarn next:check-types && yarn next:lint --max-warnings=0`

Expected: PASS. The type check exits 0 and the linter prints `No ESLint warnings or errors`.

**Step 5: Commit**

```bash
git add packages/nextjs
git commit -m "feat: add the sale page"
```

---

### Task 27: The admin card

**Files:**
- Modify: `packages/nextjs/app/page.tsx`
- Create: `packages/nextjs/components/sale/AdminCard.tsx`

The admin card renders only for an account that holds the diamond's `DEFAULT_ADMIN_ROLE`. Before the sale is launched it creates the token; afterwards it sets the price and withdraws proceeds. `launchSale` is payable and its value goes through the unit conversion; `withdrawProceeds` takes tinybars as an argument and sends no value.

**Step 1: Write the failing test**

Edit `packages/nextjs/app/page.tsx`.

Edit 1 of 2. After:

```tsx
import type { NextPage } from "next";
```

insert:

```tsx
import { AdminCard } from "~~/components/sale/AdminCard";
```

Edit 2 of 2. After:

```tsx
        <SaleCard />
```

insert:

```tsx
        <AdminCard />
```

**Step 2: Run test to verify it fails**

Run: `yarn next:check-types`

Expected: FAIL. The page imports a component that does not exist.

```text
app/page.tsx(3,27): error TS2307: Cannot find module '~~/components/sale/AdminCard' or its corresponding type declarations.
```

**Step 3: Write minimal implementation**

Create `packages/nextjs/components/sale/AdminCard.tsx`:

```tsx
"use client";

import { useState } from "react";
import { zeroHash } from "viem";
import { useAccount, useBalance } from "wagmi";
import { useDeployedContractInfo, useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-hbar";
import { useSale } from "~~/hooks/useSale";
import { formatAmount, hbarToTinybars, parsePositive, tinybarsToWeibars } from "~~/utils/sale/units";

/** Lattice's `DEFAULT_ADMIN_ROLE`. */
const ADMIN_ROLE = zeroHash;
const TOKEN_DECIMALS = 8;
/** HTS charges about $1 to create a token. Hedera deducts only the fee, and the rest stays in the diamond. */
const CREATION_FEE_HBAR = "20";

export const AdminCard = () => {
  const { address } = useAccount();
  const sale = useSale();
  const { data: diamond } = useDeployedContractInfo({ contractName: "Diamond" });
  const { data: isAdmin } = useScaffoldReadContract({
    contractName: "Diamond",
    functionName: "hasRole",
    args: [ADMIN_ROLE, address],
  });
  const { data: balance } = useBalance({ address: diamond?.address });
  const { writeContractAsync, isMining } = useScaffoldWriteContract({ contractName: "Diamond" });

  const [name, setName] = useState("Lattice Sale Token");
  const [symbol, setSymbol] = useState("LST");
  const [supply, setSupply] = useState("1000000");
  const [price, setPrice] = useState("0.05");
  const [withdrawal, setWithdrawal] = useState("");

  if (!isAdmin || sale.isLoading) return null;

  const priceUsd = parsePositive(price, 18);
  const supplyUnits = parsePositive(supply, TOKEN_DECIMALS);
  const withdrawalTinybars = hbarToTinybars(withdrawal);

  const launch = async () => {
    if (priceUsd === undefined || supplyUnits === undefined) return;
    await writeContractAsync({
      functionName: "launchSale",
      args: [name, symbol, "Launched with Lattice Hedera Template", TOKEN_DECIMALS, supplyUnits, priceUsd],
      value: tinybarsToWeibars(hbarToTinybars(CREATION_FEE_HBAR) ?? 0n),
    });
  };

  const setSalePrice = async () => {
    if (priceUsd === undefined) return;
    await writeContractAsync({ functionName: "setSalePrice", args: [priceUsd] });
  };

  const withdraw = async () => {
    if (withdrawalTinybars === undefined) return;
    // `withdrawProceeds` takes tinybars as an argument; it is not a payable call.
    await writeContractAsync({ functionName: "withdrawProceeds", args: [address, withdrawalTinybars] });
    setWithdrawal("");
  };

  return (
    <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-primary/40">
      <h2 className="font-bold text-xl m-0">Admin</h2>
      <p className="text-sm text-base-content/70 mt-1">
        You hold the diamond&apos;s admin role. Every action here is a call to a facet of the same contract.
      </p>

      {!sale.isLaunched ? (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
          <Field label="Token name" value={name} onChange={setName} />
          <Field label="Symbol" value={symbol} onChange={setSymbol} />
          <Field label="Supply (whole tokens)" value={supply} onChange={setSupply} />
          <Field label="Price per token (USD)" value={price} onChange={setPrice} />
          <div className="md:col-span-2">
            <button
              className="btn btn-primary btn-sm"
              onClick={launch}
              disabled={isMining || priceUsd === undefined || supplyUnits === undefined}
            >
              Create the token and open the sale
            </button>
            <p className="text-xs text-base-content/60 mt-2 mb-0">
              Sends {CREATION_FEE_HBAR} HBAR to cover the Hedera Token Service creation fee. Only the fee is deducted.
              The rest stays in the diamond, where you can withdraw it.
            </p>
          </div>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mt-4">
          <div>
            <Field label="Price per token (USD)" value={price} onChange={setPrice} />
            <button
              className="btn btn-primary btn-sm mt-3"
              onClick={setSalePrice}
              disabled={isMining || priceUsd === undefined}
            >
              Set price
            </button>
          </div>
          <div>
            <Field
              label={`Withdraw HBAR (diamond holds ${balance ? formatAmount(balance.value, balance.decimals) : "…"})`}
              value={withdrawal}
              onChange={setWithdrawal}
            />
            <button
              className="btn btn-primary btn-sm mt-3"
              onClick={withdraw}
              disabled={isMining || withdrawalTinybars === undefined}
            >
              Withdraw to my wallet
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

type FieldProps = { label: string; value: string; onChange: (value: string) => void };

const Field = ({ label, value, onChange }: FieldProps) => (
  <label className="flex flex-col gap-1 text-sm">
    <span className="font-medium">{label}</span>
    <input className="input input-bordered w-full" value={value} onChange={event => onChange(event.target.value)} />
  </label>
);
```

**Step 4: Run test to verify it passes**

Run: `yarn next:check-types && yarn next:lint --max-warnings=0`

Expected: PASS. The type check exits 0 and the linter prints `No ESLint warnings or errors`.

**Step 5: Commit**

```bash
git add packages/nextjs
git commit -m "feat: add the admin card to the sale page"
```

---

### Task 28: The Diamond page and its facet table

**Files:**
- Create: `packages/nextjs/app/diamond/page.tsx`
- Modify: `packages/nextjs/components/Header.tsx`
- Create: `packages/nextjs/hooks/useSelectorNames.ts`
- Create: `packages/nextjs/components/diamond/FacetTable.tsx`

The table is read live from the diamond's loupe (`facets()`), so it shows what the diamond routes now, not what was deployed. After a cut it changes without a redeploy or a regenerated ABI.

**Step 1: Write the failing test**

Create `packages/nextjs/app/diamond/page.tsx`:

```tsx
import type { NextPage } from "next";
import { FacetTable } from "~~/components/diamond/FacetTable";
import { getMetadata } from "~~/utils/scaffold-hbar/getMetadata";

export const metadata = getMetadata({
  title: "Diamond",
  description: "The facets behind this project's diamond, and a tool to cut a new one in",
});

const Diamond: NextPage = () => {
  return (
    <div className="w-full max-w-4xl mx-auto px-5 py-10 flex flex-col gap-6">
      <div>
        <h1 className="text-3xl font-bold m-0">Diamond</h1>
        <p className="text-base-content/70 m-0 mt-2">
          One address, many facets. The table is read live from the diamond&apos;s loupe, so it changes the moment a cut
          lands.
        </p>
      </div>
      <FacetTable />
    </div>
  );
};

export default Diamond;
```

Link the page from the header, and call the home page what it is:

Edit `packages/nextjs/components/Header.tsx`.

Edit 1 of 2. Replace:

```tsx
import { Bars3Icon, BugAntIcon, MagnifyingGlassIcon } from "@heroicons/react/24/outline";
```

with:

```tsx
import { Bars3Icon, BugAntIcon, CubeTransparentIcon, MagnifyingGlassIcon } from "@heroicons/react/24/outline";
```

Edit 2 of 2. Replace:

```tsx
    label: "Home",
    href: "/",
```

with:

```tsx
    label: "Sale",
    href: "/",
  },
  {
    label: "Diamond",
    href: "/diamond",
    icon: <CubeTransparentIcon className="h-4 w-4" />,
```

**Step 2: Run test to verify it fails**

Run: `yarn next:check-types`

Expected: FAIL. The page imports a component that does not exist.

```text
app/diamond/page.tsx(2,28): error TS2307: Cannot find module '~~/components/diamond/FacetTable' or its corresponding type declarations.
```

**Step 3: Write minimal implementation**

Create `packages/nextjs/hooks/useSelectorNames.ts`:

```typescript
import { useMemo } from "react";
import { Abi } from "viem";
import { useTargetNetwork } from "~~/hooks/scaffold-hbar";
import { selectorNames } from "~~/utils/diamond/selectorNames";
import { GenericContract, contracts } from "~~/utils/scaffold-hbar/contract";

/** Selector to function name, from the ABI of every contract this project has deployed on the current network. */
export function useSelectorNames() {
  const { targetNetwork } = useTargetNetwork();

  return useMemo(() => {
    const deployed = (contracts?.[targetNetwork.id] ?? {}) as Record<string, GenericContract>;
    return selectorNames(Object.values(deployed).map(contract => contract.abi as Abi));
  }, [targetNetwork.id]);
}
```

Create `packages/nextjs/components/diamond/FacetTable.tsx`:

```tsx
"use client";

import { Address, Hex } from "viem";
import { DiamondNotDeployed } from "~~/components/diamond/DiamondNotDeployed";
import { HederaAddress } from "~~/components/scaffold-hbar";
import { useDeployedContractInfo, useScaffoldReadContract, useTargetNetwork } from "~~/hooks/scaffold-hbar";
import { useSelectorNames } from "~~/hooks/useSelectorNames";

type Facet = { facetAddress: string; functionSelectors: readonly Hex[] };

/** The diamond as its loupe reports it: every facet address and the functions routed to it. */
export const FacetTable = () => {
  const { targetNetwork } = useTargetNetwork();
  const { data: diamond, isLoading } = useDeployedContractInfo({ contractName: "Diamond" });
  const { data } = useScaffoldReadContract({ contractName: "Diamond", functionName: "facets" });
  const facets = data as readonly Facet[] | undefined;
  const names = useSelectorNames();

  if (isLoading) return <div className="h-64 rounded-2xl bg-base-200 animate-pulse" aria-hidden />;
  if (!diamond) return <DiamondNotDeployed />;

  return (
    <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300">
      <div className="flex flex-wrap items-center justify-between gap-2 mb-4">
        <h2 className="font-bold text-xl m-0">Facets</h2>
        <HederaAddress address={diamond.address as Address} chain={targetNetwork} />
      </div>
      <div className="overflow-x-auto">
        <table className="table table-sm">
          <thead>
            <tr>
              <th>Facet</th>
              <th>Functions it serves</th>
            </tr>
          </thead>
          <tbody>
            {facets?.map(facet => (
              <tr key={facet.facetAddress}>
                <td className="align-top">
                  <HederaAddress address={facet.facetAddress as Address} chain={targetNetwork} />
                </td>
                <td>
                  <div className="flex flex-wrap gap-1">
                    {facet.functionSelectors.map(selector => (
                      <span key={selector} className="badge badge-ghost font-mono text-xs" title={selector}>
                        {names.get(selector) ?? selector}
                      </span>
                    ))}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="text-xs text-base-content/60 mt-4 mb-0">
        A selector shown as hex is served by the diamond but belongs to no contract in{" "}
        <code>contracts/deployedContracts.ts</code>. Deploying its facet with <code>yarn foundry:deploy</code> adds it.
      </p>
    </div>
  );
};
```

**Step 4: Run test to verify it passes**

Run: `yarn next:check-types && yarn next:lint --max-warnings=0`

Expected: PASS. The type check exits 0 and the linter prints `No ESLint warnings or errors`.

**Step 5: Commit**

```bash
git add packages/nextjs
git commit -m "feat: add the Diamond page with a live facet table"
```

---

### Task 29: Cut a facet into the live diamond from the app

**Files:**
- Modify: `packages/nextjs/app/diamond/page.tsx`
- Create: `packages/nextjs/components/diamond/UpgradeCard.tsx`

This is the end of the README's walkthrough. The box is pre-filled with the `TokenSaleV2` address when the generator has recorded one. Preview reads the facet's `exportSelectors()`, asks the diamond where each selector points today, and shows the planned Add and Replace. Cut sends one `diamondCut` with no initializer. Only the diamond's admin can send it; anyone else gets Lattice's access-control revert in the wallet.

**Step 1: Write the failing test**

Edit `packages/nextjs/app/diamond/page.tsx`.

Edit 1 of 2. After:

```tsx
import { FacetTable } from "~~/components/diamond/FacetTable";
```

insert:

```tsx
import { UpgradeCard } from "~~/components/diamond/UpgradeCard";
```

Edit 2 of 2. After:

```tsx
      <FacetTable />
```

insert:

```tsx
      <UpgradeCard />
```

**Step 2: Run test to verify it fails**

Run: `yarn next:check-types`

Expected: FAIL. The page imports a component that does not exist.

```text
app/diamond/page.tsx(3,29): error TS2307: Cannot find module '~~/components/diamond/UpgradeCard' or its corresponding type declarations.
```

**Step 3: Write minimal implementation**

Create `packages/nextjs/components/diamond/UpgradeCard.tsx`:

```tsx
"use client";

import { useState } from "react";
import { Address, isAddress, parseAbi, zeroAddress } from "viem";
import { usePublicClient } from "wagmi";
import { useDeployedContractInfo, useScaffoldWriteContract, useTargetNetwork } from "~~/hooks/scaffold-hbar";
import { useSelectorNames } from "~~/hooks/useSelectorNames";
import { FacetCut, FacetCutAction, planCut, unpackSelectors } from "~~/utils/diamond/planCut";
import { notification } from "~~/utils/scaffold-hbar";
import { GenericContract, contracts } from "~~/utils/scaffold-hbar/contract";

/** ERC-8153 on the facet, and the loupe on the diamond: all an upgrade needs to read. */
const upgradeAbi = parseAbi([
  "function exportSelectors() pure returns (bytes)",
  "function facetAddress(bytes4 selector) view returns (address)",
]);

const ACTION_LABELS = { [FacetCutAction.Add]: "Add", [FacetCutAction.Replace]: "Replace" } as Record<number, string>;

/** Cuts one facet into the live diamond: reads what it exports, plans Add and Replace, and sends `diamondCut`. */
export const UpgradeCard = () => {
  const { targetNetwork } = useTargetNetwork();
  const publicClient = usePublicClient({ chainId: targetNetwork.id });
  const { data: diamond } = useDeployedContractInfo({ contractName: "Diamond" });
  const { writeContractAsync, isMining } = useScaffoldWriteContract({ contractName: "Diamond" });
  const names = useSelectorNames();

  // `yarn foundry:deploy --file DeployTokenSaleV2.s.sol` records the walkthrough's facet here.
  const deployed = contracts?.[targetNetwork.id] as Record<string, GenericContract> | undefined;
  const [facet, setFacet] = useState<string>(deployed?.TokenSaleV2?.address ?? "");
  const [cuts, setCuts] = useState<FacetCut[]>();

  const preview = async () => {
    if (!publicClient || !diamond || !isAddress(facet)) return;
    try {
      const packed = await publicClient.readContract({
        address: facet,
        abi: upgradeAbi,
        functionName: "exportSelectors",
      });
      const selectors = unpackSelectors(packed);
      const routes = await Promise.all(
        selectors.map(selector =>
          publicClient.readContract({
            address: diamond.address as Address,
            abi: upgradeAbi,
            functionName: "facetAddress",
            args: [selector],
          }),
        ),
      );
      setCuts(planCut(facet, selectors, routes));
    } catch {
      setCuts(undefined);
      notification.error("That address does not answer exportSelectors(). Is it a deployed Lattice facet?");
    }
  };

  const cut = async () => {
    if (!cuts) return;
    await writeContractAsync({ functionName: "diamondCut", args: [cuts, zeroAddress, "0x"] });
    setCuts(undefined);
  };

  if (!diamond) return null;

  return (
    <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300">
      <h2 className="font-bold text-xl m-0">Upgrade</h2>
      <p className="text-sm text-base-content/70 mt-1">
        Paste the address of a deployed facet. The diamond keeps its address and its storage; only the code behind the
        listed functions changes. Only the diamond&apos;s admin can send the cut.
      </p>

      <div className="flex flex-wrap gap-3 mt-4">
        <input
          className="input input-bordered grow font-mono text-sm"
          placeholder="0x… facet address"
          value={facet}
          onChange={event => {
            setFacet(event.target.value);
            setCuts(undefined);
          }}
        />
        <button className="btn btn-secondary btn-sm" onClick={preview} disabled={!isAddress(facet)}>
          Preview cut
        </button>
      </div>

      {cuts && cuts.length === 0 && <p className="text-sm mt-4 mb-0">This facet is already mounted. Nothing to cut.</p>}

      {cuts && cuts.length > 0 && (
        <div className="mt-4">
          <ul className="text-sm m-0 p-0 list-none flex flex-col gap-2">
            {cuts.map(planned => (
              <li key={planned.action}>
                <span className="font-semibold">{ACTION_LABELS[planned.action]}</span>{" "}
                <span className="font-mono text-xs">
                  {planned.functionSelectors.map(selector => names.get(selector) ?? selector).join(", ")}
                </span>
              </li>
            ))}
          </ul>
          <button className="btn btn-primary btn-sm mt-4" onClick={cut} disabled={isMining}>
            Cut into the diamond
          </button>
        </div>
      )}
    </div>
  );
};
```

**Step 4: Run test to verify it passes**

Run:

```bash
yarn next:check-types && yarn next:lint --max-warnings=0 && yarn next:build
```

Expected: PASS. The type check and the linter pass, and the build lists the routes `/`, `/diamond`, `/debug` and `/blockexplorer`.

```text
┌ ○ /                                                                        6.62 kB         463 kB
└ ○ /diamond                                                                 2.42 kB         462 kB
├ ○ /debug                                                                   16.9 kB         470 kB
├ ○ /blockexplorer                                                           4.41 kB         402 kB
```

**Step 5: Commit**

```bash
git add packages/nextjs
git commit -m "feat: cut a facet into the live diamond from the Diamond page"
```

---

### Task 30: Try the app against the reference diamond

**Files:**
- None, unless a check fails.

The compiler has checked the wiring. This task checks the behaviour that only the real relay can show: reads through Hashio, association through HIP-719, and a purchase that moves an HTS token. It needs a browser and a wallet, so it is David's, or Claude Code's if a browser tool is connected. Do not skip it: several of the things it exercises could not be run in the sandbox this plan was verified in (they are listed under "Not verified" at the top).

**Step 1: Write the failing test**

The check has two parts. The first is a probe of the four routes:

```bash
for route in / /diamond /debug /blockexplorer; do curl -s -o /dev/null -w "%{http_code} $route\n" "http://localhost:3000$route"; done
```

The second is this walkthrough, done by hand:

1. Open `http://localhost:3000`. The sale card shows `Lattice Sale Token LST`, `$0.05 per LST`, an `HBAR / USD (Chainlink)` value in dollars, and `Raised 1 HBAR` from Task 22.
2. Connect a wallet on Hedera Testnet that is not the deployer. The app's burner wallet will do; the faucet link on the card funds it.
3. Type `1` under `Pay with HBAR`. `You receive about ... LST` appears.
4. Click `2. Buy` before associating. The purchase is refused and the app names the error `TokenSaleBuyerNotAssociated`.
5. Click `1. Associate LST` and confirm. The button goes away.
6. Click `Buy` and confirm. `You hold ... LST` appears, and `Sold` and `Raised` grow.
7. Open `/diamond`. Nine facets are listed with function names, not hex selectors.
8. Connect as the deployer. The `Admin` card appears on the sale page with the price and the withdraw form. This step is David's, because it handles the key: Claude Code does not read it from `.env` or type it into a browser. To use the deployer key without a wallet extension, David runs `localStorage.setItem("burnerWallet.pk", "<key>")` in the browser console and reloads. It is a testnet key; remove it afterwards with `localStorage.removeItem("burnerWallet.pk")`.

**Step 2: Run test to verify it fails**

Run:

```bash
for route in / /diamond /debug /blockexplorer; do curl -s -o /dev/null -w "%{http_code} $route\n" "http://localhost:3000$route"; done
```

Expected: FAIL. Four lines starting with `000`. Nothing is listening on port 3000.

**Step 3: Write minimal implementation**

Start the app and leave it running in its own terminal:

```bash
yarn next:dev
```

Do the walkthrough. If a step does not behave as written:

| You see | Cause | Do |
| --- | --- | --- |
| `HBAR / USD` shows `…` and no quote appears | The feed's last update is older than the registered limit (`ChainlinkStaleData`), or the relay is throttling reads. | Run `cast call <diamond> "latestAnswer(bytes32)(int256)" $(cast format-bytes32-string "HBAR/USD") --rpc-url https://testnet.hashio.io/api`. If it reverts with `ChainlinkStaleData`, tell David: the feed is stale beyond 365 days and the sale cannot quote. |
| The wallet refuses `Buy` or `Associate` before sending, with a gas estimation error | The relay could not estimate a call into HTS. | Pass an explicit limit. In `SaleCard.tsx` add `gas: 1_000_000n` to the `writeDiamond({ ... })` call in `buy` and to the `writeToken({ ... })` call in `associate`. In `AdminCard.tsx` add `gas: 1_000_000n` to the `launchSale` call. |
| `1. Associate LST` stays after a successful association | The relay does not answer HIP-719 `isAssociated()` over `eth_call`. | Cosmetic: `Buy` still works. Add this line under `## Limits` in the README when you write it: `- The Associate button stays visible after you associate, because Hedera's relay does not answer isAssociated() yet. Associating twice is harmless.` |
| In step 4 the error is `TokenSaleTransferFailed` with code `21`, not `TokenSaleBuyerNotAssociated` | HTS failed the call frame instead of returning code 184. | The purchase is still refused, which is what matters. When you write the README, replace ``An unassociated buyer gets `TokenSaleBuyerNotAssociated`.`` with `An unassociated buyer's purchase reverts.`, and name `TokenSaleTransferFailed` in the troubleshooting row. Tell David: Lattice's `HTSAdapter` maps codes the same way. |
| Anything else | | Stop and show David the browser console and the failing request. |

Every fix is a small edit to a component. Rerun `yarn next:check-types && yarn next:lint --max-warnings=0` after it.

**Step 4: Run test to verify it passes**

Run:

```bash
for route in / /diamond /debug /blockexplorer; do curl -s -o /dev/null -w "%{http_code} $route\n" "http://localhost:3000$route"; done
```

Expected: PASS. `200 /`, `200 /diamond`, `200 /debug`, `200 /blockexplorer`, and all eight walkthrough steps behave as written.

**Step 5: Commit**

If a fix was needed, commit it: `git add packages/nextjs && git commit -m "fix: <what the relay needed>"`. Otherwise there is nothing to commit.

---

## Phase 4: The rest of the Lattice Studio seam

### Task 31: Read every init shape a Studio recipe can carry

**Files:**
- Test: `packages/foundry/test/fixtures/pyth.recipe.json`
- Test: `packages/foundry/test/DeployDiamond.t.sol`
- Modify: `packages/foundry/script/DeployDiamond.s.sol`

So far every init step was called as `init(admin)`. A Studio recipe says more: `init.kind` can be `steps`, `none` or `bundle`; an argument can be a literal address or a `{"$ref": ...}`; and an initializer can take more than the admin. This task reads the arguments. `PythAdapterInit` is the one two-argument initializer among the wired facets, and it makes the README's oracle swap work. Anything the script cannot encode stops the build with a message that names the function to extend.

**Step 1: Write the failing test**

A recipe as Studio exports it after `ChainlinkAdapter` is replaced with `PythAdapter`:

Create `packages/foundry/test/fixtures/pyth.recipe.json`:

```json
{
  "schemaVersion": 1,
  "name": "Hedera diamond base",
  "catalog": {
    "tag": "dev-f4a32c8",
    "hash": "0x2ab42999bbfac307417b4265a7e9dbb8e004a8473bc9fc532b9bf33efa1d20c1"
  },
  "facets": [
    "PythAdapter",
    "AccessControlDiamondCut",
    "AccessControl",
    "Receive",
    "DiamondLoupeFacet",
    "ERC165Facet",
    "EmergencyStop"
  ],
  "owners": {},
  "exclude": [],
  "init": {
    "kind": "steps",
    "steps": [
      {
        "spec": "PythAdapterInit",
        "args": {
          "admin": {
            "$ref": "deployer"
          },
          "pyth": "0xA2aa501b19aff244D90cc15a4Cf739D2725B5729"
        }
      }
    ]
  }
}
```

Edit `packages/foundry/test/DeployDiamond.t.sol`.

Edit 1 of 6. After:

```solidity
import { IChainlinkAdapter } from "@lattice/interfaces/oracles/IChainlinkAdapter.sol";
```

insert:

```solidity
import { IPythAdapter } from "@lattice/interfaces/oracles/IPythAdapter.sol";
```

Edit 2 of 6. After:

```solidity
contract DeployDiamondTest is Test {
```

insert:

```solidity
    bytes4 internal constant LATEST_ANSWER = 0x084d4783;
```

Edit 3 of 6. After:

```solidity
        assertEq(feedKey, bytes32("HBAR/USD"), "TokenSaleInit ran");
    }
```

insert:

```solidity

    function test_oracleSwap_routesLatestAnswerToThePythFacet() public {
        (address diamond,, FacetCut[] memory cuts) = _diamond(vm.readFile("test/fixtures/pyth.recipe.json"));

        address pythFacet = cuts[0].facetAddress; // PythAdapter is first in the fixture
        assertEq(IDiamondLoupe(diamond).facetAddress(LATEST_ANSWER), pythFacet);
        assertEq(IDiamondLoupe(diamond).facetAddress(IPythAdapter.updatePriceFeeds.selector), pythFacet);
        assertEq(IPythAdapter(diamond).pyth(), 0xA2aa501b19aff244D90cc15a4Cf739D2725B5729, "PythAdapterInit ran");
    }
```

Edit 4 of 6. Before:

```solidity

    function test_build_revertsOnAFileThatIsNotARecipe() public {
```

insert:

```solidity

    function test_build_revertsOnABundleInit() public {
        string memory json = vm.replace(recipe, '"kind": "steps"', '"kind": "bundle"');

        vm.expectRevert(bytes("Recipe: init.kind must be 'steps' or 'none'; 'bundle' inits are not supported yet"));
        deployer.build(json, admin);
    }

    function test_build_revertsOnASelfReference() public {
        string memory json = vm.replace(recipe, '"$ref": "deployer"', '"$ref": "self"');

        vm.expectRevert(bytes('Recipe: only {"$ref": "deployer"} is supported; {"$ref": "self"} is not yet'));
        deployer.build(json, admin);
    }

    function test_build_revertsOnAnInitItCannotEncode() public {
        string memory json = vm.replace(
            recipe,
            '"spec": "ChainlinkAdapterInit",\n        "args": {',
            '"spec": "ChainlinkAdapterInit",\n        "args": {\n          "extra": "0x0000000000000000000000000000000000000001",'
        );

        vm.expectRevert(
            bytes(
                "Recipe: ChainlinkAdapterInit takes arguments this template cannot encode yet; add an encoder in _initStep"
            )
        );
        deployer.build(json, admin);
    }
```

Edit 5 of 6. After:

```solidity
        deployer.build("{}", admin);
    }
```

insert:

```solidity

    function test_build_acceptsARecipeWithNoInitSteps() public {
        string memory json =
            vm.replace(vm.readFile("test/fixtures/pyth.recipe.json"), '"kind": "steps"', '"kind": "none"');

        (,, address[] memory inits,) = deployer.build(json, admin);

        assertEq(inits.length, 3, "only the Hedera layer's initializers");
    }
```

Edit 6 of 6. After:

```solidity
        assertEq(maxStaleness, vm.envOr("HBAR_USD_MAX_STALENESS", uint256(365 days)));
    }
```

insert:

```solidity

    function test_registerHbarUsdFeed_skipsADiamondWithoutChainlink() public {
        address diamond = deployer.assemble(vm.readFile("test/fixtures/pyth.recipe.json"), address(deployer));

        deployer.registerHbarUsdFeed(diamond); // must not revert

        (bytes32 priceId,,) = IPythAdapter(diamond).getFeed("HBAR/USD");
        assertEq(priceId, bytes32(0));
    }
```

**Step 2: Run test to verify it fails**

Run: `(cd packages/foundry && forge test --match-contract DeployDiamondTest)`

Expected: FAIL. The six new tests fail: the script calls `PythAdapterInit` as `init(admin)`, and it ignores `init.kind` and `$ref`.

```text
Suite result: FAILED. 9 passed; 6 failed; 0 skipped; finished in 26.87ms (47.11ms CPU time)
```

**Step 3: Write minimal implementation**

Edit `packages/foundry/script/DeployDiamond.s.sol`.

Edit 1 of 5. After:

```solidity
import { IChainlinkAdapter } from "@lattice/interfaces/oracles/IChainlinkAdapter.sol";
```

insert:

```solidity
import { PythAdapterInit } from "@lattice/oracles/pyth/PythAdapterInit.sol";
```

Edit 2 of 5. After:

```solidity
    function _stepCount(string memory json) internal view returns (uint256 n) {
```

insert:

```solidity
        string memory kind = vm.parseJsonString(json, ".init.kind");
        if (_eq(kind, "none")) return 0;
        require(_eq(kind, "steps"), "Recipe: init.kind must be 'steps' or 'none'; 'bundle' inits are not supported yet");
```

Edit 3 of 5. Replace:

```solidity
    /// @dev Every initializer the recipe lists is called as `init(admin)`.
    function _initStep(string memory json, uint256 i, address admin)
```

with:

```solidity
    function _initStep(string memory json, uint256 i, address deployer)
```

Edit 4 of 5. Replace:

```solidity
        string memory spec = vm.parseJsonString(json, string.concat(".init.steps[", vm.toString(i), "].spec"));
        init = deployCode(string.concat(spec, ".sol:", spec));
        data = abi.encodeWithSignature("init(address)", admin);
```

with:

```solidity
        string memory step = string.concat(".init.steps[", vm.toString(i), "]");
        string memory spec = vm.parseJsonString(json, string.concat(step, ".spec"));
        _requireWired(spec);
        string memory args = string.concat(step, ".args");
        string[] memory keys = vm.parseJsonKeys(json, args);
        init = deployCode(string.concat(spec, ".sol:", spec));

        // Generic: any init whose only argument is `admin`.
        if (keys.length == 1 && _eq(keys[0], "admin")) {
            return
                (init, abi.encodeWithSignature("init(address)", _addr(json, string.concat(args, ".admin"), deployer)));
        }
        if (_eq(spec, "PythAdapterInit")) {
            return (
                init,
                abi.encodeCall(
                    PythAdapterInit.init,
                    (
                        _addr(json, string.concat(args, ".admin"), deployer),
                        _addr(json, string.concat(args, ".pyth"), deployer)
                    )
                )
            );
        }
        revert(
            string.concat(
                "Recipe: ", spec, " takes arguments this template cannot encode yet; add an encoder in _initStep"
            )
        );
    }

    /// @dev A literal address, or `{"$ref": "deployer"}`.
    function _addr(string memory json, string memory path, address deployer) internal view returns (address) {
        string memory ref = string.concat(path, "['$ref']");
        if (vm.keyExistsJson(json, ref)) {
            require(
                _eq(vm.parseJsonString(json, ref), "deployer"),
                "Recipe: only {\"$ref\": \"deployer\"} is supported; {\"$ref\": \"self\"} is not yet"
            );
            return deployer;
        }
        return vm.parseJsonAddress(json, path);
```

Edit 5 of 5. Before:

```solidity

    // ── after the diamond exists ────────────────────────────────────────────────────────────────────
```

insert:

```solidity

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
```

**Step 4: Run test to verify it passes**

Run: `(cd packages/foundry && forge test --match-contract DeployDiamondTest)`

Expected: PASS. Fifteen tests pass.

```text
Suite result: ok. 15 passed; 0 failed; 0 skipped; finished in 28.07ms (48.92ms CPU time)
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: read init kinds, references and Pyth's initializer from the recipe"
```

---

### Task 32: Honour the recipe's owners and exclude fields

**Files:**
- Test: `packages/foundry/test/fixtures/both-oracles.recipe.json`
- Test: `packages/foundry/test/fixtures/more-facets.recipe.json`
- Test: `packages/foundry/test/DeployDiamond.t.sol`
- Modify: `packages/foundry/script/DeployDiamond.s.sol`

Two Lattice facets can export the same selector: `ChainlinkAdapter` and `PythAdapter` share four. A diamond routes each selector to one facet, so Studio records the decision in `owners` (who gets a contested selector) and `exclude` (selectors nobody gets). The script applies both through `BaseDeploy._cutExcept`. If a collision is left undecided, it stops and names the two facets, which the diamond's own revert would not.

**Step 1: Write the failing test**

Create `packages/foundry/test/fixtures/both-oracles.recipe.json`:

```json
{
  "$schema": "https://lattice-studio.invalid/schema/recipe.v1.json",
  "schemaVersion": 1,
  "name": "Hedera diamond base",
  "catalog": {
    "tag": "dev-f4a32c8",
    "hash": "0x2ab42999bbfac307417b4265a7e9dbb8e004a8473bc9fc532b9bf33efa1d20c1"
  },
  "facets": [
    "ChainlinkAdapter",
    "PythAdapter",
    "AccessControlDiamondCut",
    "EmergencyStop",
    "AccessControl",
    "Receive",
    "DiamondLoupeFacet",
    "ERC165Facet"
  ],
  "owners": {
    "0x084d4783": "PythAdapter",
    "0x280aebcf": "PythAdapter",
    "0x2a589908": "PythAdapter",
    "0xad0ddbee": "PythAdapter"
  },
  "exclude": [],
  "init": {
    "kind": "steps",
    "steps": [
      {
        "spec": "ChainlinkAdapterInit",
        "args": {
          "admin": {
            "$ref": "deployer"
          }
        }
      },
      {
        "spec": "PythAdapterInit",
        "args": {
          "admin": {
            "$ref": "deployer"
          },
          "pyth": "0xA2aa501b19aff244D90cc15a4Cf739D2725B5729"
        }
      }
    ]
  }
}
```

Create `packages/foundry/test/fixtures/more-facets.recipe.json`:

```json
{
  "$schema": "https://lattice-studio.invalid/schema/recipe.v1.json",
  "schemaVersion": 1,
  "name": "Hedera diamond base",
  "catalog": {
    "tag": "dev-f4a32c8",
    "hash": "0x2ab42999bbfac307417b4265a7e9dbb8e004a8473bc9fc532b9bf33efa1d20c1"
  },
  "facets": [
    "ChainlinkAdapter",
    "AccessControlDiamondCut",
    "EmergencyStop",
    "AccessControl",
    "Receive",
    "DiamondLoupeFacet",
    "ERC165Facet",
    "Pausable",
    "Multicall"
  ],
  "owners": {},
  "exclude": [
    "0x2a589908"
  ],
  "init": {
    "kind": "steps",
    "steps": [
      {
        "spec": "ChainlinkAdapterInit",
        "args": {
          "admin": {
            "$ref": "deployer"
          }
        }
      }
    ]
  }
}
```

Edit `packages/foundry/test/DeployDiamond.t.sol`.

Edit 1 of 3. After:

```solidity
    bytes4 internal constant LATEST_ANSWER = 0x084d4783;
```

insert:

```solidity
    bytes4 internal constant UNREGISTER_FEED = 0x2a589908;
```

Edit 2 of 3. After:

```solidity
        assertEq(IPythAdapter(diamond).pyth(), 0xA2aa501b19aff244D90cc15a4Cf739D2725B5729, "PythAdapterInit ran");
    }
```

insert:

```solidity

    function test_owners_routeAContestedSelectorToItsOwner() public {
        (address diamond,, FacetCut[] memory cuts) = _diamond(vm.readFile("test/fixtures/both-oracles.recipe.json"));

        // The fixture lists ChainlinkAdapter then PythAdapter, and gives the four shared selectors to Pyth.
        assertEq(cuts[0].functionSelectors.length, 1, "Chainlink keeps only its own registerFeed");
        assertEq(cuts[0].functionSelectors[0], IChainlinkAdapter.registerFeed.selector);
        assertEq(IDiamondLoupe(diamond).facetAddress(LATEST_ANSWER), cuts[1].facetAddress);
    }

    function test_exclude_leavesTheSelectorOutOfTheDiamond() public {
        (address diamond, string[] memory names,) = _diamond(vm.readFile("test/fixtures/more-facets.recipe.json"));

        assertEq(names.length, 11, "nine base facets plus the Hedera layer");
        assertEq(IDiamondLoupe(diamond).facetAddress(UNREGISTER_FEED), address(0));
        assertTrue(IDiamondLoupe(diamond).facetAddress(LATEST_ANSWER) != address(0));
    }
```

Edit 3 of 3. Before:

```solidity

    function test_build_revertsOnABundleInit() public {
```

insert:

```solidity

    function test_build_revertsWhenTwoFacetsExportTheSameSelector() public {
        string memory json = vm.replace(recipe, '"ChainlinkAdapter",', '"ChainlinkAdapter", "PythAdapter",');

        vm.expectRevert(
            bytes(
                "Recipe: selector 0x280aebcf is exported by both ChainlinkAdapter and PythAdapter; give it one owner in Lattice Studio (owners) or drop it (exclude)"
            )
        );
        deployer.build(json, admin);
    }
```

**Step 2: Run test to verify it fails**

Run: `(cd packages/foundry && forge test --match-contract DeployDiamondTest)`

Expected: FAIL. The three new tests fail: `owners` and `exclude` are ignored, and a collision is only caught inside the diamond.

```text
Suite result: FAILED. 15 passed; 3 failed; 0 skipped; finished in 33.61ms (60.47ms CPU time)
```

**Step 3: Write minimal implementation**

Edit `packages/foundry/script/DeployDiamond.s.sol`.

Edit 1 of 4. Replace:

```solidity
            cuts[i] = _cut(_facet(base[i]));
```

with:

```solidity
            cuts[i] = _cutExcept(_facet(base[i]), _excludedFor(json, base[i]));
```

Edit 2 of 4. After:

```solidity
        cuts[base.length + 1] = _cut(address(new TokenSale()));
```

insert:

```solidity
        _requireDistinctSelectors(names, cuts);
```

Edit 3 of 4. Before:

```solidity

    function _stepCount(string memory json) internal view returns (uint256 n) {
```

insert:

```solidity

    /// @dev `exclude`, plus every contested selector that `owners` gives to a different facet.
    function _excludedFor(string memory json, string memory facet) internal view returns (bytes4[] memory out) {
        string[] memory excluded =
            vm.keyExistsJson(json, ".exclude") ? vm.parseJsonStringArray(json, ".exclude") : new string[](0);
        string[] memory contested =
            vm.keyExistsJson(json, ".owners") ? vm.parseJsonKeys(json, ".owners") : new string[](0);
        out = new bytes4[](excluded.length + contested.length);
        uint256 n;
        for (uint256 i; i < excluded.length; ++i) {
            out[n++] = bytes4(vm.parseBytes(excluded[i]));
        }
        for (uint256 i; i < contested.length; ++i) {
            string memory owner = vm.parseJsonString(json, string.concat(".owners['", contested[i], "']"));
            if (!_eq(owner, facet)) out[n++] = bytes4(vm.parseBytes(contested[i]));
        }
        assembly ("memory-safe") {
            mstore(out, n)
        }
    }
```

Edit 4 of 4. Before:

```solidity

    function _eq(string memory a, string memory b) internal pure returns (bool) {
```

insert:

```solidity

    /// @dev A diamond routes each selector to exactly one facet. Checking here names both facets, where the
    ///      diamond's own error would name neither.
    function _requireDistinctSelectors(string[] memory names, FacetCut[] memory cuts) internal pure {
        for (uint256 a; a < cuts.length; ++a) {
            for (uint256 b = a + 1; b < cuts.length; ++b) {
                bytes4[] memory left = cuts[a].functionSelectors;
                bytes4[] memory right = cuts[b].functionSelectors;
                for (uint256 i; i < left.length; ++i) {
                    for (uint256 j; j < right.length; ++j) {
                        if (left[i] == right[j]) {
                            revert(
                                string.concat(
                                    "Recipe: selector ",
                                    vm.toString(abi.encodePacked(left[i])),
                                    " is exported by both ",
                                    names[a],
                                    " and ",
                                    names[b],
                                    "; give it one owner in Lattice Studio (owners) or drop it (exclude)"
                                )
                            );
                        }
                    }
                }
            }
        }
    }
```

**Step 4: Run test to verify it passes**

Run: `(cd packages/foundry && forge test --match-contract DeployDiamondTest)`

Expected: PASS. Eighteen tests pass.

```text
Suite result: ok. 18 passed; 0 failed; 0 skipped; finished in 46.41ms (82.80ms CPU time)
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: apply the recipe's owners and exclude fields to the cuts"
```

---

### Task 33: Warn about a recipe that deploys but deserves a second look

**Files:**
- Test: `packages/foundry/test/DeployDiamond.t.sol`
- Modify: `packages/foundry/script/DeployDiamond.s.sol`

Two things do not stop a deploy but should be said out loud: a recipe pinned to a different Studio catalog than the Lattice this project compiles, and a recipe with no facet that serves `diamondCut`, which produces a diamond nobody can upgrade.

**Step 1: Write the failing test**

Edit `packages/foundry/test/DeployDiamond.t.sol`.

After:

```solidity
        assertEq(inits.length, 3, "only the Hedera layer's initializers");
    }
```

insert:

```solidity

    function test_warnings_areEmptyForTheDefaultRecipe() public {
        (, FacetCut[] memory cuts,,) = deployer.build(recipe, admin);

        assertEq(deployer.warnings(recipe, cuts).length, 0);
    }

    function test_warnings_flagAnotherCatalogAndAMissingCutFacet() public {
        string memory json = vm.replace(recipe, '"dev-f4a32c8"', '"v9.9.9"');
        json = vm.replace(json, '"AccessControlDiamondCut",', "");
        (, FacetCut[] memory cuts,,) = deployer.build(json, admin);

        string[] memory notes = deployer.warnings(json, cuts);

        assertEq(notes.length, 2);
        assertEq(notes[0], "the recipe is pinned to catalog v9.9.9 but this template's Lattice matches dev-f4a32c8");
        assertEq(notes[1], "no facet in the recipe serves diamondCut, so this diamond cannot be upgraded");
    }
```

**Step 2: Run test to verify it fails**

Run: `(cd packages/foundry && forge test --match-contract DeployDiamondTest)`

Expected: FAIL. Compilation stops: `DeployDiamond` has no `warnings`.

```text
Error (9582): Member "warnings" not found or not visible after argument-dependent lookup in contract DeployDiamondHarness.
```

**Step 3: Write minimal implementation**

Edit `packages/foundry/script/DeployDiamond.s.sol`.

Edit 1 of 5. After:

```solidity
    string internal constant RECIPE = "diamond.recipe.json";
```

insert:

```solidity

    /// @dev The Studio catalog the pinned Lattice sources match. A recipe from another catalog still deploys;
    ///      it only earns a warning.
    string internal constant CATALOG_TAG = "dev-f4a32c8";
```

Edit 2 of 5. After:

```solidity
    address internal constant HBAR_USD_FEED_MAINNET = 0xAF685FB45C12b92b5054ccb9313e135525F9b5d5;
```

insert:

```solidity

    bytes4 internal constant DIAMOND_CUT = 0x1f931c1c;
```

Edit 3 of 5. Before:

```solidity
        _writeRecord(diamond, names, cuts);
```

insert:

```solidity
        string[] memory notes = warnings(json, cuts);
        for (uint256 i; i < notes.length; ++i) {
            console.log(string.concat("Warning: ", notes[i]));
        }
```

Edit 4 of 5. After:

```solidity
        calls[steps + 2] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }
```

insert:

```solidity

    /// @notice Problems that do not stop a deploy but that the developer should hear about.
    function warnings(string memory json, FacetCut[] memory cuts) public view returns (string[] memory notes) {
        notes = new string[](2);
        uint256 n;
        if (vm.keyExistsJson(json, ".catalog.tag")) {
            string memory tag = vm.parseJsonString(json, ".catalog.tag");
            if (!_eq(tag, CATALOG_TAG)) {
                notes[n++] = string.concat(
                    "the recipe is pinned to catalog ", tag, " but this template's Lattice matches ", CATALOG_TAG
                );
            }
        }
        if (!_serves(cuts, DIAMOND_CUT)) {
            notes[n++] = "no facet in the recipe serves diamondCut, so this diamond cannot be upgraded";
        }
        assembly ("memory-safe") {
            mstore(notes, n)
        }
    }
```

Edit 5 of 5. Before:

```solidity

    function _eq(string memory a, string memory b) internal pure returns (bool) {
```

insert:

```solidity

    function _serves(FacetCut[] memory cuts, bytes4 selector) internal pure returns (bool) {
        for (uint256 i; i < cuts.length; ++i) {
            bytes4[] memory selectors = cuts[i].functionSelectors;
            for (uint256 j; j < selectors.length; ++j) {
                if (selectors[j] == selector) return true;
            }
        }
        return false;
    }
```

**Step 4: Run test to verify it passes**

Run: `(cd packages/foundry && forge test)`

Expected: PASS. Forty-three tests pass across the three suites.

```text
Ran 3 test suites in 63.92ms (92.40ms CPU time): 43 tests passed, 0 failed, 0 skipped (43 total tests)
```

**Step 5: Commit**

```bash
git add packages/foundry
git commit -m "feat: warn about catalog drift and diamonds that cannot be upgraded"
```

---

### Task 34: Print an Open in Lattice Studio link

**Files:**
- Test: `packages/foundry/scripts-js/studioLink.test.js`
- Create: `packages/foundry/scripts-js/studioLink.js`
- Modify: `packages/foundry/package.json`
- Modify: `package.json`

Studio opens a recipe from the URL fragment: `#s=1.` followed by the recipe JSON without `$schema`, raw-deflated and base64url-encoded. Nothing is uploaded, and the template makes no network call. The third test decodes a link produced by Studio's own encoder for the same recipe, so the two implementations are checked against each other.

**Step 1: Write the failing test**

Create `packages/foundry/scripts-js/studioLink.test.js`:

```javascript
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "fs";
import { inflateRawSync } from "zlib";
import { studioLink } from "./studioLink.js";

// The default recipe, frozen as a fixture so this test keeps passing after you customize yours.
const recipe = JSON.parse(
  readFileSync(
    new URL("../test/fixtures/default.recipe.json", import.meta.url),
    "utf8"
  )
);

// The same recipe encoded by Lattice Studio's own share-link encoder (lattice-studio@9c9d9eb).
const STUDIO_ENCODED =
  "https://lattice-studio-topaz.vercel.app/#s=1.XU_JbsIwEP0VNOqRStkgJDeUtmqlnqjUC-IwtifEIrEj21AQyr933PTEad5sb7mDxIC9PUJ9hw59BzUk1wxFkVVVJUSLMk_KIi15sF5hSZUSYkNJUuCmKHMhq1au8kxUos1zajFVWSJTWEJApgRFl-e2wDyTG5iWQFfZnxVBvT8sgakpeMbQdKhNr81pq3AM5Ph9KyV531gTnO1fNA7WqOYcePM6kDuSkbevYMfHS-53JElfiNH_26c9j_QWxeL3rknXq7ljD9roEJOftFFs1wcaPV_Ntd7fAd2RAVc1aBPBk6P2L9jY2xtbnTiWH0ny7DHGRySfDnxgcODQ8E6KHC7U7Gsh0Eeb9seQiyKRSXY04Df32rJcOv0C";

const decode = (link) =>
  JSON.parse(
    inflateRawSync(Buffer.from(link.split("#s=1.")[1], "base64url")).toString()
  );

test("the link carries the recipe without its $schema", () => {
  const { $schema, ...expected } = recipe;

  assert.ok($schema);
  assert.deepEqual(decode(studioLink(recipe)), expected);
});

test("the link opens on the hosted Studio", () => {
  assert.ok(
    studioLink(recipe).startsWith(
      "https://lattice-studio-topaz.vercel.app/#s=1."
    )
  );
});

test("a link encoded by Studio itself decodes to the same recipe", () => {
  assert.deepEqual(decode(STUDIO_ENCODED), decode(studioLink(recipe)));
});
```

**Step 2: Run test to verify it fails**

Run: `yarn workspace @sh/foundry test:scripts`

Expected: FAIL. `studioLink.js` does not exist.

```text
# Error [ERR_MODULE_NOT_FOUND]: Cannot find module '<repo>/packages/foundry/scripts-js/studioLink.js' imported from <repo>/packages/foundry/scripts-js/studioLink.test.js
# fail 1
```

**Step 3: Write minimal implementation**

Create `packages/foundry/scripts-js/studioLink.js`:

```javascript
import { readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath, pathToFileURL } from "url";
import { deflateRawSync } from "zlib";

const STUDIO_URL = "https://lattice-studio-topaz.vercel.app/";

/**
 * The "Open in Lattice Studio" link for a recipe. Studio reads a recipe from the URL fragment:
 * `#s=1.` followed by the recipe JSON (minus `$schema`), raw-deflated and base64url-encoded.
 * Nothing is uploaded; the fragment never leaves the browser.
 */
export function studioLink(recipe) {
  const { $schema, ...shared } = recipe;
  const packed = deflateRawSync(Buffer.from(JSON.stringify(shared)), {
    level: 9,
  });
  return `${STUDIO_URL}#s=1.${packed.toString("base64url")}`;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const recipePath = join(
    dirname(fileURLToPath(import.meta.url)),
    "..",
    "diamond.recipe.json"
  );
  console.log(studioLink(JSON.parse(readFileSync(recipePath, "utf8"))));
}
```

Add the script to the Foundry package:

Edit `packages/foundry/package.json`.

After:

```json
    "deploy": "node scripts-js/parseArgs.js",
```

insert:

```json
    "diamond:studio": "node scripts-js/studioLink.js",
```

And its alias at the root:

Edit `package.json`.

After:

```json
  "scripts": {
```

insert:

```json
    "diamond:studio": "yarn workspace @sh/foundry diamond:studio",
```

**Step 4: Run test to verify it passes**

Run: `yarn workspace @sh/foundry test:scripts && yarn diamond:studio`

Expected: PASS. Twelve tests pass, and `yarn diamond:studio` prints one line that starts with `https://lattice-studio-topaz.vercel.app/#s=1.`. Open that link in a browser once. Studio's title should read `Hedera diamond base (shared) · No problems`, and its panel `5 facets · 24 selectors`: Studio counts the loupe and ERC-165 facets as the diamond's core, not among the facets on the sheet. This was checked against the hosted Studio on 4 October. If Studio shows an error instead, tell David before the README promises this step.

```text
# pass 12
# fail 0
```

**Step 5: Commit**

```bash
git add package.json packages/foundry
git commit -m "feat: print the Lattice Studio link for the project's recipe"
```

---

## Phase 5: Documents and CI

### Task 35: The README

**Files:**
- Modify: `README.md`

Documentation is 30 of the rubric's 100 points, and the README is what a judge reads first. It is written for a developer who has never seen a diamond: what the template does, how to run it in two commands, how to deploy, how it works, how to upgrade, how to customize in Studio, and what goes wrong. The evidence table is filled in Task 39; until then its rows say `PENDING` and the gate keeps failing on them, which is the point.

**Step 1: Write the failing test**

The check is the gate's README lines:

```bash
bash scripts/gate.sh static | grep README
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/gate.sh static | grep README`

Expected: FAIL. The scaffold command, the Studio section and the HashScan links are missing from the stock README.

```text
PASS  README.md exists
FAIL  README.md shows the scaffold command
FAIL  README.md explains the Lattice Studio seam
FAIL  README.md links testnet transactions on HashScan or the mirror node
PASS  README.md has no PENDING placeholders
```

**Step 3: Write minimal implementation**

Replace the whole of `README.md` with:

````markdown
# Lattice Hedera Template

An upgradeable HTS token sale on a [Lattice](https://github.com/dadadave80/lattice) diamond, priced by Chainlink and customizable in [Lattice Studio](https://lattice-studio-topaz.vercel.app/). A template for [Scaffold-HBAR](https://docs.hedera.com/solutions/tools/scaffold-hbar/index).

```bash
npm create scaffold-hbar@latest -- --template dadadave80/lattice-hedera-template
```

One contract address does all of this:

- **Creates an HTS token** through the Hedera Token Service and holds it as treasury.
- **Sells it for HBAR at a USD price**, converting with the Chainlink HBAR/USD feed on every purchase.
- **Upgrades while it runs.** The contract is an [EIP-2535 diamond](https://eips.ethereum.org/EIPS/eip-2535): you swap the code behind its functions with one transaction, and the address, the token and the balances stay.
- **Is composed, not hand-wired.** The diamond's base is a list of Lattice facets in one JSON file. Open that file in Lattice Studio, change it on a canvas, export it back.

## Live on Hedera testnet

The app you scaffold talks to this deployment until you deploy your own.

| What | Where |
| --- | --- |
| Diamond | PENDING |
| Deploy transaction | PENDING |
| HTS token created by the diamond | PENDING |
| A purchase priced by Chainlink | PENDING |
| The upgrade to `TokenSaleV2` (`diamondCut`) | PENDING |

## Prerequisites

- [Node.js](https://nodejs.org/) 20.18.3 or newer, [Yarn](https://yarnpkg.com/) and [Git](https://git-scm.com/)
- [Foundry](https://getfoundry.sh/) (`forge`, `cast`)
- To deploy: a Hedera testnet account with HBAR. The [Hedera Portal faucet](https://portal.hedera.com/faucet) funds any EVM address.

**Deploying needs Foundry 1.7.1 for now.** Foundry 1.8 asks Hedera's JSON-RPC relay a question the relay does not answer yet ([relay issue 5826](https://github.com/hiero-ledger/hiero-json-rpc-relay/issues/5826)), so `forge script` stops with `-32602 Invalid parameter 1`. Building and testing work on any recent Foundry. To switch:

```bash
foundryup --install v1.7.1
```

## Quick start

```bash
npm create scaffold-hbar@latest -- --template dadadave80/lattice-hedera-template
cd <your-project>
yarn foundry:test   # contracts and scripts, against mocks: no chain needed
yarn next:dev       # http://localhost:3000
```

The app opens on the sale. Connect a wallet on Hedera Testnet, get HBAR from the faucet link, then:

1. **Associate.** On Hedera an account must opt in to a token before it can receive it. The button sends that one transaction.
2. **Buy.** Type an HBAR amount, read the quote, confirm.

The **Diamond** page lists every facet behind the address and the functions each one serves. **Debug Contracts** lets you call any of them.

## Deploy your own diamond

```bash
yarn foundry:account:generate                # creates an encrypted keystore and prints its address
# fund that address at https://portal.hedera.com/faucet
yarn foundry:deploy --network hedera_testnet
```

Have about 60 testnet HBAR in the account. A first deployment sends up to 18 transactions. Lattice facets land on deterministic addresses, so a facet that is already on the network is reused and later deployments send fewer. Creating the token in the next step sends 20 HBAR to cover the network's creation fee. Hedera deducts only the fee ([HIP-358](https://hips.hedera.com/hip/hip-358)). The rest stays in the diamond, and the admin can withdraw it.

The deploy command:

1. reads `packages/foundry/diamond.recipe.json` and deploys each facet it names;
2. adds the Hedera layer, `HTSAdapter` and this project's `TokenSale`;
3. creates and initializes the diamond in one transaction, with your account as admin;
4. registers the Chainlink HBAR/USD feed;
5. rewrites `packages/nextjs/contracts/deployedContracts.ts`, so the app now points at your diamond.

Then create the token. Either import the deployer key into your wallet (`yarn foundry:account:reveal-pk`) and use the **Admin** card on the sale page, or send it from the terminal:

```bash
cast send <your diamond> \
  "launchSale(string,string,string,int32,int64,uint256)" \
  "My Token" MTK "" 8 100000000000000 50000000000000000 \
  --value 20ether --gas-limit 1000000 --legacy \
  --rpc-url https://testnet.hashio.io/api --account <your keystore>
```

That creates 1,000,000 MTK with 8 decimals, priced at $0.05 each. The token is created in its own transaction because Foundry simulates a deploy script locally first, and no local EVM can run the Hedera Token Service.

## How it works

```
                        one address
                 ┌──────────────────────┐
  buy() ───────► │       Diamond        │  every call is routed by selector
                 └──────────┬───────────┘
        ┌──────────────┬────┴─────────┬────────────────┐
        ▼              ▼              ▼                ▼
   TokenSale      HTSAdapter   ChainlinkAdapter   AccessControl, AccessControlDiamondCut,
   (this repo)    (Lattice)    (Lattice)          EmergencyStop, Receive, DiamondLoupeFacet,
        │              │              │           ERC165Facet (Lattice)
        │              ▼              ▼
        │       HTS system      Chainlink HBAR/USD
        └─────► contract 0x167  price feed
```

| File | What it is |
| --- | --- |
| `packages/foundry/diamond.recipe.json` | The Lattice base of the diamond, in Lattice Studio's recipe format. |
| `packages/foundry/script/DeployDiamond.s.sol` | Builds the diamond from the recipe and adds the Hedera layer. |
| `packages/foundry/contracts/LatticeFacets.sol` | The Lattice facets this project compiles. A facet must be imported here before a recipe can name it. |
| `packages/foundry/contracts/TokenSale.sol` | The sale facet. Stateless: it forwards to `TokenSaleLib`. |
| `packages/foundry/contracts/libraries/TokenSaleLib.sol` | The sale's logic and its storage, at a fixed [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) slot. |
| `packages/foundry/contracts/TokenSaleV2.sol` | The facet used in the upgrade walkthrough. |
| `packages/foundry/scripts-js/generateTsAbis.js` | Gives the frontend one `Diamond` contract whose ABI is the union of its facets. |
| `packages/nextjs/app/page.tsx` | The sale page. |
| `packages/nextjs/app/diamond/page.tsx` | The facet table and the upgrade tool. |

A facet holds no state. Each Lattice module is three files: an interface, a library with all the logic and a storage struct at its own slot, and a facet that forwards to the library. That split is why an upgrade can replace a facet without touching what the diamond remembers.

### Hedera details this template handles

- **Two units of HBAR.** Inside the EVM, `msg.value` is in tinybars (8 decimals). Over JSON-RPC, a transaction's `value` is in weibars (18 decimals), and the relay converts. The contracts work in tinybars. The app converts in one place, `packages/nextjs/utils/sale/units.ts`.
- **HTS answers with response codes, not reverts.** `22` is success. `TokenSaleLib` checks the code after every HTS call and reverts with a named error.
- **Association.** A buyer associates with the token once, through the token's own address ([HIP-719](https://hips.hedera.com/hip/hip-719)). An unassociated buyer gets `TokenSaleBuyerNotAssociated`.
- **Token keys on a diamond.** A facet runs inside a `delegatecall`, so HTS only honours `delegatableContractId` keys for it. Lattice's `HTSAdapterLib` sets the admin and supply keys that way when the diamond creates the token.
- **Oracle freshness.** `ChainlinkAdapter` rejects an answer older than the limit set when the feed was registered. Testnet feeds are not kept on a production heartbeat, so the testnet default is 365 days. On mainnet the default is 25 hours. Set `HBAR_USD_MAX_STALENESS` (seconds) before deploying to choose your own.

## Upgrade the live diamond

`TokenSaleV2` is `TokenSale` with a 5% bonus and one new function, `bonusBps()`.

1. Deploy the facet. Nothing changes yet:
   ```bash
   yarn foundry:deploy --file DeployTokenSaleV2.s.sol --network hedera_testnet
   ```
2. Open the **Diamond** page with the admin wallet. The facet's address is already in the Upgrade box. **Preview cut** reads the facet's selectors and compares them with the diamond: six are replaced, one is added.
3. **Cut into the diamond.** One transaction.

The sale page now shows the bonus and quotes 5% more. The address, the token, the price, the totals and every holder's balance are what they were. `test/TokenSaleUpgrade.t.sol` asserts exactly that.

To ship your own change: copy `TokenSaleV2.sol`, change it, list its selectors in `exportSelectors()`, deploy it and cut it the same way. Two rules keep an upgrade safe: only add fields at the end of a storage struct, and never change the storage slot.

## Customize in Lattice Studio

The base of the diamond is not written in Solidity. It is this list in `packages/foundry/diamond.recipe.json`:

```json
"facets": ["ChainlinkAdapter", "AccessControlDiamondCut", "EmergencyStop", "AccessControl", "Receive", "DiamondLoupeFacet", "ERC165Facet"]
```

Lattice Studio is a visual composer for Lattice diamonds. It checks selectors, storage, initializers and upgrade authority as you edit.

1. `yarn diamond:studio` prints a link. Open it: your base is on the sheet. Nothing is uploaded; the recipe travels in the link.
2. Change it. For example, replace `ChainlinkAdapter` with `PythAdapter`.
3. Export `recipe.json` from Studio and save it over `packages/foundry/diamond.recipe.json`.
4. `yarn foundry:test`, then `yarn foundry:deploy --network hedera_testnet`.

What to know:

- **Step 4 deploys a new diamond.** To change a diamond that is already live, cut it (the section above).
- **The Hedera facets are not on Studio's sheet yet.** `HTSAdapter` and `TokenSale` are added by `DeployDiamond.s.sol` after the recipe. Studio's catalog does not carry them, and it rejects a recipe that names a facet it does not know.
- **An oracle swap leaves `TokenSale` untouched, but not the setup.** The sale reads the price through the diamond's own `latestAnswer(bytes32)`, which `ChainlinkAdapter` and `PythAdapter` both serve. Registering a feed differs: Pyth's `registerFeed` takes a price id and a confidence limit, and a Pyth price must be pushed with `updatePriceFeeds` before it can be read. The deploy script registers the Chainlink feed only; the app does not push Pyth updates.
- **A facet must be compiled into the project before a recipe can name it.** `ChainlinkAdapter`, `PythAdapter`, `Pausable`, `Multicall` and the base facets are. For another one, add its import to `contracts/LatticeFacets.sol`. If its initializer takes more than an `admin`, add an encoder in `_initStep` in `DeployDiamond.s.sol`.

The deploy script stops before sending anything when a recipe cannot be built, and says what to change:

| Message | Fix |
| --- | --- |
| `X is in the recipe but not compiled into this project` | Import `X` in `contracts/LatticeFacets.sol`. |
| `X is not in FacetInventory` | `X` is not a Lattice facet. Remove it from the recipe. |
| `selector 0x… is exported by both A and B` | Give the selector one owner in Studio, or exclude it. |
| `XInit takes arguments this template cannot encode yet` | Add an encoder in `_initStep`. |
| `init.kind must be 'steps' or 'none'` | Bundle initializers are not supported. Use steps. |
| `only {"$ref": "deployer"} is supported` | Replace `{"$ref": "self"}` with an address. |

## Add your own facet

1. Write the interface, the library and the facet under `packages/foundry/contracts/`, the way `ITokenSale`, `TokenSaleLib` and `TokenSale` are written. Give the library its own storage slot.
2. Return the facet's selectors from `exportSelectors()`.
3. For a new deployment, add the facet next to `TokenSale` in `build()` in `DeployDiamond.s.sol`. For a live diamond, deploy it and cut it from the Diamond page.
4. Test it through the diamond, as `test/SaleTestBase.sol` does.

## Commands

| Command | What it does |
| --- | --- |
| `yarn foundry:test` | Forge tests against a mock HTS and a mock feed, then the Node tests for the scripts. No chain needed. |
| `yarn next:test` | Unit tests for the frontend's unit conversion and cut planning. |
| `yarn next:dev` | The app, on `http://localhost:3000`. |
| `yarn foundry:deploy --network hedera_testnet` | Deploys the diamond from the recipe and regenerates the frontend's contract file. |
| `yarn foundry:deploy --file DeployTokenSaleV2.s.sol --network hedera_testnet` | Deploys the upgrade facet. |
| `yarn diamond:studio` | Prints the Lattice Studio link for the current recipe. |
| `yarn foundry:account:generate` | Creates a deployer keystore. |
| `yarn lint` | Lints the frontend and checks Solidity and script formatting. |
| `yarn next:build` | Production build of the app. |

Environment variables are optional. `packages/foundry/.env.example` and `packages/nextjs/.env.example` list them.

## Troubleshooting

| You see | Cause and fix |
| --- | --- |
| `-32602 Invalid parameter 1` during deploy | Foundry 1.8 against Hedera's relay. `foundryup --install v1.7.1`. |
| `Requested resource not found. address '0x…'` | The deployer address does not exist on Hedera yet. Fund it from the faucet. |
| `DeployDiamond: this diamond needs Hedera` | You deployed to a local chain. This diamond needs HTS and a Chainlink feed: use `--network hedera_testnet`. |
| `TokenSaleBuyerNotAssociated` | The buyer has not associated with the token. Use the Associate button. |
| `ChainlinkStaleData` | The feed's last update is older than the registered limit. Register the feed again with a larger `maxStaleness`. |
| `HTSCallFailed` on `launchSale` | The HBAR sent did not cover the creation fee. Send more with `--value`. |
| "No diamond on Hedera Mainnet" in the app | The wallet is on a network this project has no diamond on. Switch to Hedera Testnet. |

## Limits

- Not audited. Lattice is pre-1.0 and unaudited too. Do not put real value behind this without a review.
- There is no local-chain mode. HTS and the Chainlink feed exist only on Hedera, so contract tests run against mocks and the app runs against testnet.
- The package manager is Yarn.

## Links

- [Lattice](https://github.com/dadadave80/lattice), the diamond module library, and its [Hedera guide](https://github.com/dadadave80/lattice/blob/feat/hedera-system-contract-modules/docs/guides/hedera.md)
- [Lattice Studio](https://github.com/dadadave80/lattice-studio)
- [Scaffold-HBAR docs](https://docs.hedera.com/solutions/tools/scaffold-hbar/index) and [create-scaffold-hbar](https://github.com/hedera-dev/create-scaffold-hbar)
- [Chainlink price feeds on Hedera](https://docs.chain.link/data-feeds/price-feeds/addresses?network=hedera)
- [HashScan](https://hashscan.io/testnet)

MIT licensed. See [LICENCE](LICENCE).
````

**Step 4: Run test to verify it passes**

Run: `bash scripts/gate.sh static | grep README`

Expected: PASS. Three README lines pass. `links testnet transactions on HashScan` and `has no PENDING placeholders` stay red until Task 39.

```text
PASS  README.md exists
PASS  README.md shows the scaffold command
PASS  README.md explains the Lattice Studio seam
FAIL  README.md links testnet transactions on HashScan or the mirror node
FAIL  README.md has no PENDING placeholders
```

**Step 5: Commit**

```bash
git add README.md
git commit -m "docs: write the template README"
```

Before moving on, read the README top to bottom against the project as it now stands. Every command in it must be one that exists in `package.json`, and every file it names must exist. If Task 30 found a relay limit, add its line under `## Limits`. If the deployment in Task 22 cost more than 60 HBAR in total, change `about 60` under `## Deploy your own diamond` to the measured figure, rounded up.

---

### Task 36: AGENTS.md and the package README

**Files:**
- Modify: `AGENTS.md`
- Modify: `packages/foundry/README.md`
- Modify: `packages/foundry/.env.example`

`AGENTS.md` is a gate requirement and the file a coding agent reads before it touches a scaffolded project. The stock one describes Hardhat and sample contracts that no longer exist. The new one leads with the ten rules an agent is most likely to break in this project. `CLAUDE.md` already includes it and does not change.

**Step 1: Write the failing test**

The check is that neither document still describes the stock project:

```bash
! grep -lwE 'HederaToken|HtsTokenCreator|hardhat' AGENTS.md packages/foundry/README.md
```

**Step 2: Run test to verify it fails**

Run:

```bash
! grep -lwE 'HederaToken|HtsTokenCreator|hardhat' AGENTS.md packages/foundry/README.md
```

Expected: FAIL. Both files are listed.

```text
AGENTS.md
packages/foundry/README.md
```

**Step 3: Write minimal implementation**

Replace the whole of `AGENTS.md` with:

````markdown
# Agent instructions

Briefing for coding agents in this project (Claude Code, Cursor, Codex). Claude Code loads it through `CLAUDE.md`.

This is a Scaffold-HBAR dApp built from the Lattice Hedera Template. One [Lattice](https://github.com/dadadave80/lattice) diamond (EIP-2535) on Hedera creates an HTS token, sells it for HBAR at a USD price read from Chainlink, and is upgraded with `diamondCut`. Contracts are Foundry, the app is Next.js App Router, the package manager is Yarn.

## Rules that are easy to get wrong

1. **Change the diamond's base in `packages/foundry/diamond.recipe.json`, not in Solidity.** `script/DeployDiamond.s.sol` reads that file. Never hand-write `FacetCut` arrays or selector lists for Lattice facets.
2. **A facet a recipe names must be compiled into the project.** If a build stops with `X is in the recipe but not compiled into this project`, add the import of `X` (and of `XInit`, if it has one) to `packages/foundry/contracts/LatticeFacets.sol`.
3. **`HTSAdapter` and `TokenSale` are not in the recipe.** `DeployDiamond.s.sol` appends them after the recipe's facets. Lattice Studio's catalog does not carry the Hedera facets yet, and Studio rejects a recipe that names a facet it does not know. Do not add them to the recipe.
4. **Facets hold no state.** Logic and storage live in a library with its own ERC-7201 slot (`contracts/libraries/TokenSaleLib.sol`). Append fields to a storage struct. Never reorder or remove fields, and never change a slot constant.
5. **Every facet lists its selectors in `exportSelectors()`** (ERC-8153): 4 bytes each, never `exportSelectors()` itself. Add a function, add its selector. `test/TokenSale.t.sol` fails when the list and the ABI disagree.
6. **HBAR has two units.** Contracts see tinybars (8 decimals) in `msg.value` and in every amount they take or return. A transaction's `value` over JSON-RPC is weibars (18 decimals), and the relay converts. In the app, convert only through `packages/nextjs/utils/sale/units.ts`. With `cast send`, `--value 20ether` sends 20 HBAR.
7. **HTS answers with response codes. It does not revert.** `22` is success. Check the code after every call to `0x167` and revert with a named error, as `TokenSaleLib._transferFromTreasury` does.
8. **There is no local chain.** HTS and the Chainlink feed exist only on Hedera. Contract tests run against Lattice's `MockHederaTokenService` and `test/mocks/MockAggregatorV3.sol`. The app runs against Hedera testnet. `forge script` cannot simulate an HTS call, so the token is created by a separate transaction (`launchSale`) after the deploy.
9. **Deploy with Foundry 1.7.1.** Foundry 1.8 fails against Hedera's relay with `-32602 Invalid parameter 1`. Building and testing work on any recent Foundry.
10. **The frontend knows one contract, `Diamond`.** Its ABI is the union of what the facets serve. `scripts-js/generateTsAbis.js` writes it to `packages/nextjs/contracts/deployedContracts.ts` on every deploy. Never edit that file by hand.

## Commands

```bash
yarn foundry:test      # Forge tests (mock HTS, mock feed) and the Node tests for scripts-js. No chain needed.
yarn next:test         # Vitest unit tests for packages/nextjs/utils
yarn next:dev          # the app on http://localhost:3000, against Hedera testnet
yarn lint              # next lint, forge fmt --check, prettier --check on scripts-js
yarn format            # fix what yarn lint reports
yarn next:check-types
yarn next:build

yarn foundry:account:generate                                                  # create a deployer keystore
yarn foundry:deploy --network hedera_testnet                                   # deploy the diamond from the recipe
yarn foundry:deploy --file DeployTokenSaleV2.s.sol --network hedera_testnet    # deploy the upgrade facet
yarn diamond:studio                                                            # print the Lattice Studio link for the recipe
```

Run one Forge test from `packages/foundry`: `forge test --match-test test_buy_sendsTokensToTheBuyerAndKeepsTheHbar -vvv`.

## Layout

| Path | What it is |
| --- | --- |
| `packages/foundry/diamond.recipe.json` | The Lattice base of the diamond, in Lattice Studio's recipe format. |
| `packages/foundry/script/DeployDiamond.s.sol` | Reads the recipe, appends the Hedera layer, deploys, registers the Chainlink feed, records the deployment. |
| `packages/foundry/script/Deploy.s.sol` | What `yarn foundry:deploy` runs by default. It is `DeployDiamond`. |
| `packages/foundry/script/DeployTokenSaleV2.s.sol` | Deploys the upgrade facet on its own. |
| `packages/foundry/contracts/LatticeFacets.sol` | Imports that compile Lattice facets and inits into this project. |
| `packages/foundry/contracts/interfaces/ITokenSale.sol` | The sale's functions, events and errors. |
| `packages/foundry/contracts/libraries/TokenSaleLib.sol` | The sale's logic and storage. |
| `packages/foundry/contracts/TokenSale.sol`, `TokenSaleV2.sol` | The sale facet and its upgrade. |
| `packages/foundry/contracts/TokenSaleInit.sol` | The sale's initializer, run once while the diamond is created. |
| `packages/foundry/test/SaleTestBase.sol` | Test base: builds the diamond through the deploy script, with HTS and the feed mocked. |
| `packages/foundry/test/fixtures/` | Recipes frozen for tests. Tests do not depend on the project's own recipe, except one. |
| `packages/foundry/scripts-js/diamondAbi.js` | Merges facet ABIs into the `Diamond` ABI. |
| `packages/foundry/lib/lattice` | Lattice, pinned by tag in `foundry.lock`. Do not edit. |
| `packages/nextjs/app/page.tsx` | Sale page: `components/sale/SaleCard.tsx` and `AdminCard.tsx`. |
| `packages/nextjs/app/diamond/page.tsx` | Diamond page: `components/diamond/FacetTable.tsx` and `UpgradeCard.tsx`. |
| `packages/nextjs/utils/sale/units.ts` | Tinybar and weibar conversion. |
| `packages/nextjs/utils/diamond/planCut.ts` | Turns a facet's exported selectors into Add and Replace cuts. |

## How to change things

| Goal | Do this |
| --- | --- |
| Swap or add a Lattice facet in a new deployment | Edit `diamond.recipe.json` (or export over it from Lattice Studio), run `yarn foundry:test`, deploy. |
| Use a Lattice facet that is not compiled in | Add its import to `contracts/LatticeFacets.sol`. If its init takes more than `admin`, add an encoder in `_initStep` in `DeployDiamond.s.sol`. |
| Change the sale's behaviour on a live diamond | Write a new facet (copy `TokenSaleV2.sol`), deploy it with its own script, cut it in from the Diamond page. |
| Add your own facet to new deployments | Interface, library with its own slot, facet with `exportSelectors()`. Add it next to `TokenSale` in `build()` in `DeployDiamond.s.sol` and raise `HEDERA_FACETS`. |
| Add sale storage | Append a field to `TokenSaleStorage`. |
| Change the oracle | Put `PythAdapter` in the recipe instead of `ChainlinkAdapter`. `TokenSale` does not change: it reads `latestAnswer(bytes32)` on the diamond. Registering and updating a Pyth feed is yours to add. |

## Frontend contract interaction

Use the Scaffold-HBAR hooks in `packages/nextjs/hooks/scaffold-hbar` with `contractName: "Diamond"`. Every function of every facet is on that one contract.

```typescript
const { data: saleInfo } = useScaffoldReadContract({
  contractName: "Diamond",
  functionName: "saleInfo",
});

const { writeContractAsync } = useScaffoldWriteContract({ contractName: "Diamond" });

await writeContractAsync({
  functionName: "buy",
  args: [minTokensOut(quote, 100n)],
  value: tinybarsToWeibars(tinybars), // the contract receives tinybars
});
```

The hook names are `useScaffoldReadContract` and `useScaffoldWriteContract`, not `useScaffoldContractRead` or `useScaffoldContractWrite`. Also available: `useScaffoldWatchContractEvent`, `useScaffoldEventHistory`, `useDeployedContractInfo`, `useScaffoldContract`, `useTransactor`.

An HTS token answers ERC-20 reads (`name`, `symbol`, `balanceOf`) and the HIP-719 calls `associate()` and `isAssociated()` at its own address. Call those with wagmi's `useReadContract` and `useWriteContract`, as `SaleCard.tsx` does. An account must associate with the token before it can receive it.

A function added by a cut (for example `bonusBps()` after the upgrade to `TokenSaleV2`) is not in the generated `Diamond` ABI until the next full deploy. Read it with an inline ABI, as `SaleCard.tsx` does.

UI: `HederaAddress` from `~~/components/scaffold-hbar` shows an address with its HashScan link. `HbarInput` and `HederaPortalFaucet` come from `@scaffold-hbar-ui/components`. Use DaisyUI classes (`btn btn-primary`, `badge`, `table`) before raw Tailwind.

## Tests

- Contract tests extend `SaleTestBase` and call everything through the diamond, the way a wallet does.
- Test behaviour, including the revert a caller would see. Lattice errors come from `@lattice/interfaces/...`, the sale's from `ITokenSale`.
- Script helpers in `scripts-js` are tested with the Node test runner: put a `*.test.js` beside the file and `yarn foundry:test` runs it.
- Frontend logic that can be wrong (units, cut planning) lives in `packages/nextjs/utils` with a `*.test.ts` beside it.

## Networks

- Foundry: `packages/foundry/foundry.toml` (`hedera_testnet` 296, `hedera_mainnet` 295).
- Next.js: `packages/nextjs/scaffold.config.ts`.
- Chainlink HBAR/USD feed addresses are constants in `DeployDiamond.s.sol`.

## Style

| Style | Use |
| --- | --- |
| `UpperCamelCase` | types, components, contracts |
| `lowerCamelCase` | variables, functions |
| `CONSTANT_CASE` | constants |

Solidity is formatted by `forge fmt` (120 columns, double quotes, spaces inside braces). Scripts in `scripts-js` use Prettier 2 defaults; keep that folder flat. Next.js imports use the `~~` alias. Add `"use client"` to a component that uses hooks. Prefer `type` over `interface`. Comments say what the code cannot.
````

Replace the whole of `packages/foundry/README.md` with:

````markdown
# Foundry package

The contracts, deploy scripts and tests behind the diamond. The [root README](../../README.md) is the guide; this page is the reference for working inside `packages/foundry`.

## Dependencies

Forge libraries are git submodules under `lib/`, pinned by tag in `foundry.lock`:

| Library | Why |
| --- | --- |
| `lib/lattice` | The diamond, its facets, the deploy base (`BaseDeploy`) and the HTS mock used in tests. |
| `lib/forge-std` | Forge's test and script library. |

`create-scaffold-hbar` installs them when it scaffolds the project. In a plain clone, run `git submodule update --init --recursive` from the repository root.

## Tests

```bash
yarn test            # forge test, then the Node tests for scripts-js
forge test -vvv --match-contract TokenSaleTest
yarn test:scripts    # only the Node tests
```

Tests need no chain. `test/SaleTestBase.sol` builds the diamond through the deploy script, puts Lattice's `MockHederaTokenService` at the HTS address `0x167`, and registers `test/mocks/MockAggregatorV3.sol` as the HBAR/USD feed.

| File | Covers |
| --- | --- |
| `test/TokenSale.t.sol` | Launching the sale, quoting, buying, association, slippage, HTS response codes, admin functions, the storage slot, `exportSelectors()`. |
| `test/TokenSaleUpgrade.t.sol` | Cutting `TokenSaleV2` into a diamond that is already selling. |
| `test/DeployDiamond.t.sol` | Reading recipes: the default, an oracle swap, `owners`, `exclude`, and every message a bad recipe produces. |
| `scripts-js/*.test.js` | The merged `Diamond` ABI, the Lattice Studio link, the Foundry version warning. |

`yarn test:testnet` and `yarn test:mainnet` fork a live network. The suite does not need them.

## Deploy

```bash
yarn deploy --network hedera_testnet                                   # the diamond, from diamond.recipe.json
yarn deploy --file DeployTokenSaleV2.s.sol --network hedera_testnet    # the upgrade facet
```

From the repository root the same commands are `yarn foundry:deploy ...`.

- Use Foundry 1.7.1 (`foundryup --install v1.7.1`). Foundry 1.8 cannot run `forge script` against Hedera's relay yet.
- The deployer must be an account that exists on Hedera: generate a keystore with `yarn account:generate` and fund its address from the [faucet](https://portal.hedera.com/faucet).
- The Makefile passes `--slow --legacy`: one transaction at a time, with legacy gas pricing, which is what the relay expects.
- Facets are deployed through the deterministic deployment proxy, so a facet that is already on the network at its address is reused instead of deployed again.

A deploy writes three things:

| File | Content |
| --- | --- |
| `broadcast/` | Forge's record of the transactions. Not committed. |
| `deployments/diamond/<chainId>.json` | The diamond's address, its facets, and the selectors cut for each. Not committed. |
| `../nextjs/contracts/deployedContracts.ts` | What the app reads: one `Diamond` contract with the merged ABI. Committed. |

## Environment

`.env` is created from `.env.example` on install and is never committed.

| Variable | Use |
| --- | --- |
| `HBAR_USD_MAX_STALENESS` | Seconds the diamond accepts between Chainlink updates. Read at deploy time. Defaults to 365 days on testnet and 25 hours on mainnet. |
| `LOCALHOST_KEYSTORE_ACCOUNT`, `HEDERA_RPC_URL`, `ALCHEMY_API_KEY` | Scaffold-HBAR defaults. This template does not need them changed. |
````

Document the one environment variable this template adds:

Edit `packages/foundry/.env.example`.

After:

```text
HEDERA_RPC_URL=https://testnet.hashio.io/api
```

insert:

```text

# Seconds the diamond accepts between Chainlink HBAR/USD updates. Read by `yarn foundry:deploy` when it
# registers the feed. Leave unset for the defaults: 365 days on testnet, 25 hours on mainnet.
# HBAR_USD_MAX_STALENESS=90000
```

**Step 4: Run test to verify it passes**

Run:

```bash
! grep -lwE 'HederaToken|HtsTokenCreator|hardhat' AGENTS.md packages/foundry/README.md && bash scripts/gate.sh static | grep AGENTS
```

Expected: PASS. No file is listed, and the gate prints `PASS  AGENTS.md exists`.

**Step 5: Commit**

```bash
git add AGENTS.md packages/foundry/README.md packages/foundry/.env.example
git commit -m "docs: brief coding agents on this template"
```

---

### Task 37: Continuous integration that matches the project

**Files:**
- Delete: `.github/workflows/lint.yaml`
- Create: `.github/workflows/ci.yaml`
- Modify: `.lintstagedrc.js`

The stock workflow starts a Hardhat node, which this Foundry-only project does not have, so it would fail on the first push. The replacement runs what the gate runs. It pins Foundry 1.7.1 and Node 22, the versions this plan was verified with. It is also copied into every scaffolded project, where it works unchanged because the CLI installs the libraries as submodules.

**Step 1: Write the failing test**

The check is that nothing in the repository's automation mentions Hardhat:

```bash
! grep -rnE 'hardhat' .github .lintstagedrc.js
```

**Step 2: Run test to verify it fails**

Run: `! grep -rnE 'hardhat' .github .lintstagedrc.js`

Expected: FAIL. The workflow and the lint-staged configuration both refer to Hardhat.

```text
.github/workflows/lint.yaml:37:          yarn hardhat:chain &
.github/workflows/lint.yaml:39:          yarn hardhat:deploy --network localhost
.github/workflows/lint.yaml:47:      - name: Run hardhat lint
.github/workflows/lint.yaml:48:        run: yarn hardhat:lint --max-warnings=0
.lintstagedrc.js:11:  `yarn hardhat:lint-staged --fix ${filenames
.lintstagedrc.js:12:    .map((f) => path.relative(path.join("packages", "hardhat"), f))
.lintstagedrc.js:20:  "packages/hardhat/**/*.{ts,tsx}": [buildHardhatEslintCommand],
```

**Step 3: Write minimal implementation**

```bash
git rm .github/workflows/lint.yaml
```

Create `.github/workflows/ci.yaml`:

```yaml
name: CI

on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

jobs:
  ci:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: yarn

      - name: Install Foundry
        uses: foundry-rs/foundry-toolchain@v1
        with:
          version: v1.7.1

      - name: Install dependencies
        run: yarn install --immutable

      - name: Lint the app
        run: yarn next:lint --max-warnings=0

      - name: Check Solidity and script formatting
        run: yarn foundry:lint

      - name: Contract and script tests
        run: yarn foundry:test

      - name: App unit tests
        run: yarn next:test

      - name: Type check
        run: yarn next:check-types

      - name: Build the app
        run: yarn next:build
```

Replace the whole of `.lintstagedrc.js` with:

```javascript
const path = require("path");

const buildNextEslintCommand = (filenames) =>
  `yarn next:lint --fix --file ${filenames
    .map((f) => path.relative(path.join("packages", "nextjs"), f))
    .join(" --file ")}`;

const checkTypesNextCommand = () => "yarn next:check-types";

module.exports = {
  "packages/nextjs/**/*.{ts,tsx}": [
    buildNextEslintCommand,
    checkTypesNextCommand,
  ],
};
```

**Step 4: Run test to verify it passes**

Run:

```bash
! grep -rnE 'hardhat' .github .lintstagedrc.js && node -e "require('./.lintstagedrc.js')" && yarn lint
```

Expected: PASS. No match, the lint-staged configuration loads, and `yarn lint` passes. The workflow itself runs for the first time when the repository is pushed, in Task 40.

**Step 5: Commit**

```bash
git add .github .lintstagedrc.js
git commit -m "ci: lint, test and build with Foundry and Node"
```

---

## Phase 6: Gate, evidence, publish, submit

### Task 38: Run the gate on a freshly scaffolded project

**Files:**
- None, unless a check fails.

This is the bounty's gate, run the way a judge runs it, before anything is public. `scripts/gate.sh scaffold` exports the committed tree with `git archive` (what GitHub would serve), scaffolds a project from it with the real CLI, and then lints, tests, type-checks, builds and boots that project. It takes several minutes and needs network access for `yarn install` and `forge install`. It reads commits, not the working tree, so commit first.

**Step 1: Write the failing test**

The test was written in Task 2. There is nothing new to write.

**Step 2: Run test to verify it fails**

Run: `bash scripts/gate.sh scaffold`

Expected: either result. This is the one task where a failure is not required: if every task so far was committed, all fourteen lines pass and Step 3 has nothing to do. A `FAIL` line is the failing test for Step 3.

**Step 3: Write minimal implementation**

Nothing, unless a line failed. For a failure, the script prints the last lines of the command's output. The usual causes:

| Failing line | Look at |
| --- | --- |
| `the template scaffolds and installs` | The scaffold log path the script printed. A `forge install` failure means the Lattice tag from Task 4 is not on GitHub, or `.gitmodules` and `foundry.lock` disagree with `remappings.txt`. |
| `the scaffold leaves out ...` | `.gitattributes` is not committed, or its paths are wrong. |
| `yarn lint` | Run `yarn format` in this repository, commit, rerun. |
| `yarn foundry:test`, `yarn next:test`, `yarn next:check-types`, `yarn next:build` | Run the same command here. If it passes here and fails in the scaffold, a file the project needs is not committed, or is caught by `export-ignore`. |
| `the app boots` or a `GET` line | Port 3210 is in use, or the build failed. |

Fix, commit, and rerun until the script ends with `All checks passed.`

**Step 4: Run test to verify it passes**

Run: `bash scripts/gate.sh scaffold`

Expected: PASS. Fourteen `PASS` lines, then `All checks passed.`

**Step 5: Commit**

Commit only if Step 3 changed something: `git add -A && git commit -m "fix: <what the gate found>"`.

---

### Task 39: Upgrade the reference diamond and record the evidence

**Files:**
- Modify: `README.md`
- Modify: `packages/nextjs/contracts/deployedContracts.ts` (generated: gains `TokenSaleV2`)

The gate asks for a Hedera service that is operational, with a verifiable testnet transaction and a HashScan or mirror-node link. This task produces the last transaction, the upgrade, and records five links: the diamond, the transaction that created it, the HTS token it created, a purchase priced by Chainlink, and the `diamondCut`. The cut is done from the app, because that is the walkthrough the README promises; a terminal fallback is given.

Command blocks start with the same line as in Task 22.

**Step 1: Write the failing test**

The check is the gate's two evidence lines:

```bash
bash scripts/gate.sh static | grep -E 'HashScan|PENDING'
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/gate.sh static | grep -E 'HashScan|PENDING'`

Expected: FAIL. Both lines fail.

```text
FAIL  README.md links testnet transactions on HashScan or the mirror node
FAIL  README.md has no PENDING placeholders
```

**Step 3: Write minimal implementation**

**3a. Deploy the upgrade facet.** Nothing changes on the diamond yet.

```bash
cd packages/foundry && set -a && . ./.env && set +a && RPC=https://testnet.hashio.io/api
forge script script/DeployTokenSaleV2.s.sol --rpc-url $RPC --private-key "$HEDERA_TESTNET_PK" \
  --broadcast --ffi --slow --legacy > deployments/deploy-v2.log 2>&1; tail -n 12 deployments/deploy-v2.log
node scripts-js/generateTsAbis.js
grep -c 'TokenSaleV2: {' ../nextjs/contracts/deployedContracts.ts
```

Expected: `ONCHAIN EXECUTION COMPLETE & SUCCESSFUL.`, the generator's line, then `1`. The generated file must still contain `Diamond: {`: the generator rebuilds it from `deployments/diamond/296.json`, which is why that folder must not be deleted between the two deployments.

**3b. Cut it in from the app.** With `yarn next:dev` running and the admin connected (see step 8 of the walkthrough in Task 30):

1. Open `/diamond`. The Upgrade box holds the `TokenSaleV2` address.
2. Click `Preview cut`. It shows `Replace buy, launchSale, quote, saleInfo, setSalePrice, withdrawProceeds` and `Add bonusBps`.
3. Click `Cut into the diamond` and confirm. In the facet table the six sale functions move to the new address, with `bonusBps` beside them.
4. Open `/`. The card shows `+5% bonus` and quotes 5% more than before.

If no browser or wallet is available, send the same cut from the terminal. Action `1` is Replace, `0` is Add:

```bash
cd packages/foundry && set -a && . ./.env && set +a && RPC=https://testnet.hashio.io/api
DIAMOND=$(node -p "require('./deployments/diamond/296.json').address")
V2=$(node -p "Object.entries(require('./deployments/296.json')).find(([, name]) => name === 'TokenSaleV2')[0]")
cast send "$DIAMOND" "diamondCut((address,uint8,bytes4[])[],address,bytes)" \
  "[($V2,1,[0x08bf598d,0xdf1d74ae,0xed1bd76c,0x8e3695b8,0x1919fed7,0x970ea83e]),($V2,0,[0x404f21a5])]" \
  0x0000000000000000000000000000000000000000 0x \
  --gas-limit 1000000 --legacy --rpc-url $RPC --private-key "$HEDERA_TESTNET_PK" --json > deployments/cut.json
```

**3c. Confirm the upgrade on chain and collect the values.**

```bash
cd packages/foundry && set -a && . ./.env && set +a && RPC=https://testnet.hashio.io/api
MIRROR=https://testnet.mirrornode.hedera.com/api/v1
DIAMOND=$(node -p "require('./deployments/diamond/296.json').address")
cast call "$DIAMOND" "bonusBps()(uint256)" --rpc-url $RPC
TOKEN=$(cast call "$DIAMOND" "saleInfo()(address,int32,uint256,bytes32,int64,uint256)" --rpc-url $RPC | head -n 1)
DEPLOY_TX=$(node -p "require('./broadcast/Deploy.s.sol/296/run-latest.json').transactions.find(t => t.transactionType === 'CALL' && t.contractName === 'LatticeFactory').hash")
echo "DIAMOND=$DIAMOND TOKEN=$TOKEN DEPLOY_TX=$DEPLOY_TX"
curl -s "$MIRROR/contracts/$DIAMOND/results?limit=25&order=desc" > deployments/results.json
node -p "require('./deployments/results.json').results.map(r => r.function_parameters.slice(0, 10) + ' ' + (r.error_message ? 'FAILED' : 'ok') + ' ' + r.hash).join('\n')"
```

Expected: `500`, then the three values, then one line per call the diamond has received, newest first. Selector `0x1f931c1c` is `diamondCut`, `0x08bf598d` is `buy`, `0xdf1d74ae` is `launchSale`. The mirror node's list carries no status, only an `error_message` that is empty for a call that succeeded, so the line says `ok` or `FAILED`. Take the hash of an `ok` `diamondCut` as `CUT_TX` and of an `ok` `buy` as `BUY_TX`.

Check each of the three hashes before it goes into the README. Each line must print `SUCCESS`:

```bash
MIRROR=https://testnet.mirrornode.hedera.com/api/v1
for tx in <DEPLOY_TX> <BUY_TX> <CUT_TX>; do
  curl -s "$MIRROR/contracts/results/$tx" | node -p "JSON.parse(require('fs').readFileSync(0, 'utf8')).result"
done
```

**3d. Fill the README's evidence table** with the five real values in place of the placeholders in angle brackets.

Edit `README.md`.

Replace:

```markdown
| Diamond | PENDING |
| Deploy transaction | PENDING |
| HTS token created by the diamond | PENDING |
| A purchase priced by Chainlink | PENDING |
| The upgrade to `TokenSaleV2` (`diamondCut`) | PENDING |
```

with:

```markdown
| Diamond | [`<DIAMOND>`](https://hashscan.io/testnet/contract/<DIAMOND>) |
| Deploy transaction | [`<DEPLOY_TX>`](https://hashscan.io/testnet/transaction/<DEPLOY_TX>) |
| HTS token created by the diamond | [`<TOKEN>`](https://hashscan.io/testnet/token/<TOKEN>) |
| A purchase priced by Chainlink | [`<BUY_TX>`](https://hashscan.io/testnet/transaction/<BUY_TX>) |
| The upgrade to `TokenSaleV2` (`diamondCut`) | [`<CUT_TX>`](https://hashscan.io/testnet/transaction/<CUT_TX>) |

This diamond has already been through the upgrade described below, so it runs `TokenSaleV2`.
```

Open the five links in a browser. All three link forms were checked on 4 October with the addresses of Lattice's probe, so each should resolve; HashScan can lag the network by a few seconds. If a `/transaction/0x...` link still does not resolve, use `https://testnet.mirrornode.hedera.com/api/v1/contracts/results/0x...` for that row instead; the gate accepts either form.

Then check what this task changed:

```bash
git status --short
```

Expected: ` M README.md` and ` M packages/nextjs/contracts/deployedContracts.ts`, nothing else.

**Step 4: Run test to verify it passes**

Run: `bash scripts/gate.sh static`

Expected: PASS. Twelve `PASS` lines and `All checks passed.`

```text
PASS  template.json is a valid create-scaffold-hbar manifest for this template
PASS  README.md exists
PASS  AGENTS.md exists
PASS  LICENCE is MIT
PASS  README.md shows the scaffold command
PASS  README.md explains the Lattice Studio seam
PASS  README.md links testnet transactions on HashScan or the mirror node
PASS  README.md has no PENDING placeholders
PASS  no .env file is tracked
PASS  no private key is tracked
PASS  every Forge library in remappings.txt is pinned in .gitmodules and foundry.lock
PASS  the app points at a diamond on Hedera testnet
All checks passed.
```

**Step 5: Commit**

```bash
git add README.md packages/nextjs/contracts/deployedContracts.ts
git commit -m "docs: record the testnet evidence"
```

**Optional, if there is time** (about fifteen minutes and 25 HBAR). Two paths have not been run on testnet by this plan: the documented keystore deploy, and launching a sale from the Admin card. To exercise both, David runs `yarn foundry:account:import` and then `yarn foundry:deploy --network hedera_testnet` in his own terminal, reloads the app, connects as the deployer and uses `Create the token and open the sale`. Afterwards discard the result, so the template still points at the reference diamond: `git checkout packages/nextjs/contracts/deployedContracts.ts`. Do not run the generator again after this, because the deployment record now describes the second diamond. If either path misbehaves, fix it before Task 40.

---

### Task 40: Publish the repository and run the gate as a judge would

**Files:**
- None, unless a check fails.

**Needs David's go-ahead:** this makes the repository public. Before asking, rerun `bash scripts/gate.sh scaffold` if anything was committed since Task 38.

The CLI downloads `main`, so `build` is fast-forwarded into it first.

**Step 1: Write the failing test**

The check is that the public repository exists:

```bash
gh repo view dadadave80/lattice-hedera-template --json visibility -q .visibility
```

**Step 2: Run test to verify it fails**

Run:

```bash
gh repo view dadadave80/lattice-hedera-template --json visibility -q .visibility
```

Expected: FAIL. `GraphQL: Could not resolve to a Repository with the name 'dadadave80/lattice-hedera-template'.`

**Step 3: Write minimal implementation**

```bash
git switch main
git merge --ff-only build
gh repo create dadadave80/lattice-hedera-template --public --source . --remote origin --push \
  --description "Upgradeable HTS token sale on a Lattice diamond, priced by Chainlink, customizable in Lattice Studio. A Scaffold-HBAR template."
gh repo edit dadadave80/lattice-hedera-template --add-topic hedera --add-topic scaffold-hbar \
  --add-topic eip-2535 --add-topic chainlink --add-topic foundry
sleep 20
gh run watch --exit-status "$(gh run list --limit 1 --json databaseId -q '.[0].databaseId')"
```

Expected: the push succeeds and the CI run ends green. This is the workflow's first run. If it fails, read `gh run view --log-failed`, fix on `build`, then `git switch main && git merge --ff-only build && git push`. If it cannot be made green in fifteen minutes, remove `.github/workflows/ci.yaml` rather than submit with a red check, and say so to David.

Then run the gate against the published template. This is the command a judge runs, followed by the same lint, test, build and boot checks as before:

```bash
bash scripts/gate.sh published
```

If `the scaffold leaves out template.json, docs and scripts` is the only failing line, GitHub's archive did not apply `export-ignore`. That is harmless to a judge: the scaffolded project carries a few extra files. Tell David and move on.

**Step 4: Run test to verify it passes**

Run:

```bash
bash scripts/gate.sh published && gh repo view dadadave80/lattice-hedera-template --json licenseInfo -q .licenseInfo.spdxId
```

Expected: PASS. `All checks passed.`, then `MIT`. If the second command prints nothing, GitHub has not finished detecting the licence; that does not affect the gate.

**Step 5: Commit**

Nothing to commit unless Step 3 needed a fix.

---

### Task 41: Prepare the submission

**Files:**
- Create: `docs/plans/2026-10-04-submission.md`

The submission is three things: the public repository link, a HashScan or mirror link, and the developer experience survey. Claude Code prepares the first two and the raw notes for the third. **David submits**, and answers the survey in his own words. The file lives in `docs/plans`, which is left out of scaffolded projects.

**Step 1: Write the failing test**

The check is that the submission notes exist:

```bash
test -s docs/plans/2026-10-04-submission.md
```

**Step 2: Run test to verify it fails**

Run: `test -s docs/plans/2026-10-04-submission.md`

Expected: FAIL. The command exits 1: there is no such file.

**Step 3: Write minimal implementation**

Create `docs/plans/2026-10-04-submission.md`:

```markdown
# Submission: Lattice Hedera Template

Bounty: Scaffold-HBAR Template Bounty. Submissions close Sunday 4 October 2026, 23:59 ET.

## What to submit

| Field | Value |
| --- | --- |
| Public GitHub repository | https://github.com/dadadave80/lattice-hedera-template |
| HashScan link | the `diamondCut` transaction from the README's evidence table |
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
| Code quality (20) | 43 Forge tests, 12 Node tests, 17 Vitest tests, CI, `forge fmt` and ESLint clean, `scripts/gate.sh`. |
| Hedera service depth (15) | Token creation with the diamond as treasury and `delegatableContractId` keys, treasury transfers with response-code handling, association, tinybar and weibar handling, a live upgrade on testnet. |

## Notes for the developer experience survey

Raw material from building this template. Keep what matches your own experience.

- Foundry 1.8 cannot run `forge script` against the Hedera relay (`-32602 Invalid parameter 1`, relay issue
  5826). Foundry 1.7.1 can. Nothing in the scaffolded project says so.
- The CLI reinstalls Forge libraries from `remappings.txt`, the root `.gitmodules` and the tags in
  `foundry.lock`. A template author only learns this from the CLI's source. A library pinned to a commit
  rather than a tag cannot be expressed.
- `forge remove` leaves the removed libraries in `foundry.lock` and adds a `packages/foundry/lib/...` key
  when the Foundry project is a subdirectory of the git repository.
- The shape of `template.json` is only documented by the CLI's validation code.
- A Foundry-only scaffold still ships a CI workflow, a lint-staged configuration and an `AGENTS.md` that
  refer to Hardhat.
- The frontend generator only sees contracts that appear as a creation in Forge's broadcast file. A contract
  created by a factory, such as a diamond or a proxy, is invisible to it.
- `forge script` cannot simulate a call to an HTS system contract, so anything that creates a token must be a
  separate transaction after the deploy.
- `yarn foundry:deploy` asks for the keystore password on a terminal, so a coding agent cannot run it against
  a live network.
- Without `--skip-hedera-skills` or `--ci` the CLI stops at a prompt, which blocks non-interactive use.
- `packages/foundry/.prettier.json` is not a file name Prettier reads, so the scripts are formatted with
  Prettier's defaults.
```

Replace the HashScan row with the real `diamondCut` link from the README. Then correct the survey notes against what actually happened during this build: delete any line that did not occur, and add what did. They are observations from planning, not a script.

**Step 4: Run test to verify it passes**

Run:

```bash
test -s docs/plans/2026-10-04-submission.md && bash scripts/gate.sh static | tail -n 1
```

Expected: PASS. `All checks passed.` Hand David the three items, with the deadline: Sunday 4 October 2026, 23:59 ET (Monday 03:59 UTC).

**Step 5: Commit**

```bash
git add docs/plans/2026-10-04-submission.md
git commit -m "docs: add the submission notes"
```

After the commit, fast-forward `main` and push, so the repository a judge sees is the final one:

```bash
git switch main && git merge --ff-only build && git push
```

Last, tell David that this build left Foundry 1.7.1 active on his machine, and that `foundryup --use <the version noted in Task 1>` puts his usual one back. Lattice's own builds and tests expect 1.8.1.
