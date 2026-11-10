#!/bin/sh
# Tests for the decision logic used by .td/bin/td (B-02 naming).
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
check() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CLAUDE_PROJECT_DIR="$T"
. "$HERE/.td/hooks/lib.sh"

READY='## Goal
Export tasks as CSV.

## Done criteria
- [ ] `sh tests/run.sh` passes and includes test_csv_export

## Size
S

## Next step
Add a csv function to .td/bin/td.

## Pointers
- .td/bin/td'

# --- LIFE-06: Definition of Ready
check test_LIFE_06_ready_task_passes        'printf "%s" "$READY" | td_dor_check >/dev/null'
check test_LIFE_06_size_extracted           '[ "$(printf "%s" "$READY" | td_dor_size)" = S ]'
check test_LIFE_06_missing_goal_fails       '! printf "%s" "$READY" | sed "/## Goal/,+2d" | td_dor_check >/dev/null'
check test_LIFE_06_reports_what_is_missing  'printf "%s" "$READY" | sed "/## Pointers/,\$d" | td_dor_check | grep -q "missing: pointers"'
check test_LIFE_06_bad_size_fails           '! printf "%s" "$READY" | sed "s/^S\$/huge/" | td_dor_check >/dev/null'
check test_LIFE_06_no_criteria_items_fails  '! printf "%s" "$READY" | sed "s/^- \[ \] .*/tests pass/" | td_dor_check >/dev/null'
check test_LIFE_06_vague_criteria_fails     '! printf "%s" "$READY" | sed "s/^- \[ \] .*/- [ ] works well/" | td_dor_check >/dev/null'
check test_LIFE_06_empty_body_fails         '! printf "" | td_dor_check >/dev/null'

# --- LIFE-11: the earliest claim after the last valid release wins
mkdir -p "$T/bin"
printf '#!/bin/sh\ncat "$MARKERS"\n' > "$T/bin/gh"; chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" MARKERS="$T/markers"
winner() { printf "$1" > "$MARKERS"; td_winner 1; }
check test_LIFE_11_first_claim_wins          '[ "$(winner "claim a\nclaim b\n")" = a ]'
check test_LIFE_11_release_hands_to_next     '[ "$(winner "claim a\nrelease a\nclaim b\n")" = b ]'
check test_LIFE_11_invalid_release_ignored   '[ "$(winner "claim a\nrelease x\nclaim b\n")" = a ]'
check test_LIFE_11_reap_counts_as_release    '[ "$(winner "claim a\nreap a\nclaim b\n")" = b ]'
check test_LIFE_11_old_claim_before_release  '[ "$(winner "claim a\nrelease a\n")" = "" ]'

# --- CLI basics
check test_td_help_runs                      'sh "$HERE/.td/bin/td" help | grep -q "pick \[N\]"'
check test_td_syntax_ok                      'sh -n "$HERE/.td/bin/td"'

echo "---"; echo "td: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
