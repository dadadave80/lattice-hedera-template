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
  for route in / /private /diamond /debug /blockexplorer; do
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
