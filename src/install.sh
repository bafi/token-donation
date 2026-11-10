#!/bin/sh
# Install the Token Donation source (src/) into the live, protected copy
# (.td/hooks, .td/bin, .claude/settings.json). Maintainer only, on main, after
# merging a PR (POLICIES.md D12). Donors edit src/; the hooks that guard their
# sessions only change through this reviewed step.
set -eu
ROOT=$(git rev-parse --show-toplevel); cd "$ROOT"
case "$(git rev-parse --abbrev-ref HEAD)" in
  td/*) echo "install: not on a task branch. Run this on main after merging." >&2; exit 1 ;;
esac
sh tests/run.sh >/dev/null || { echo "install: tests fail; fix src/ first (sh tests/run.sh)." >&2; exit 1; }
mkdir -p .td/hooks .td/bin .claude
cp src/hooks/*.sh .td/hooks/
cp src/bin/td .td/bin/td
cp src/claude-settings.json .claude/settings.json
chmod +x .td/hooks/*.sh .td/bin/td
jq empty .claude/settings.json
echo "Installed. Review and commit:"
git status --short .td/hooks .td/bin .claude
