#!/bin/sh
# Tests for .td/hooks/release.sh against a bare origin and a fake gh (HOOKS.md "Tests").
# Each test is named after the policy ID it proves (B-02).
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "ok   $1"; }
bad()  { fail=$((fail+1)); echo "FAIL $1: $2"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "$2"; fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# Fake gh: logs each call, answers from GH_MODE (ok | fail | hang | lost | closed | paused).
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'EOF'
#!/bin/sh
echo "$*" >> "$GH_LOG"
case "${GH_MODE:-ok}" in fail) exit 1 ;; hang) sleep 30; exit 1 ;; esac
case "$*" in
  "repo view"*)        [ "$GH_MODE" = reader ] && echo READ || echo WRITE ;;
  "label list"*)       [ "$GH_MODE" = paused ] && echo 1 || echo 0 ;;
  "issue view"*state*) [ "$GH_MODE" = closed ] && echo CLOSED || echo OPEN ;;
  "issue view"*comments*) [ "$GH_MODE" = lost ] && echo "claim c0" || echo "claim c1" ;;
  *) : ;;
esac
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"

setup() { # fresh origin + work clone on td/42-x with an active claim
  rm -rf "$T/origin.git" "$T/w"; : > "$T/gh.log"; export GH_LOG="$T/gh.log" GH_MODE=ok
  git init -q --bare -b main "$T/origin.git"
  git clone -q "$T/origin.git" "$T/w" 2>/dev/null
  cd "$T/w" || exit 1
  git config user.email h@t; git config user.name helper
  mkdir -p .td/hooks .td/local; cp "$HERE"/.td/hooks/*.sh .td/hooks/
  printf '.td/local/\n' > .gitignore
  git add -A; git commit -q -m init; git push -q origin main 2>/dev/null
  git switch -q -c td/42-x; git push -q origin td/42-x 2>/dev/null
  printf 'issue=42\nbranch=td/42-x\nclaim_id=c1\nlogin=bob\nsession_id=s1\nstate=active\n' > .td/local/claim
  export CLAUDE_PROJECT_DIR="$T/w"
}
fire() { # fire <json>
  printf '%s' "$1" | sh "$T/w/.td/hooks/release.sh"
}
END='{"hook_event_name":"SessionEnd","session_id":"s1","reason":"prompt_input_exit"}'
remote() { git -C "$T/origin.git" rev-parse "$1" 2>/dev/null; }
calls() { grep -c "$1" "$T/gh.log"; }

# --- GIT-15: order is push, then marker, then labels; remote tip == local HEAD
setup; echo "change" > feature.txt
fire "$END"
check test_GIT_09_wip_commit_made         '[ "$(git log -1 --format=%s)" = "wip(td-42): session ended (prompt_input_exit) [tests not run]" ]'
check test_GIT_15_pushed_before_release   '[ "$(remote td/42-x)" = "$(git rev-parse HEAD)" ]'
check test_GIT_15_marker_then_labels      '[ "$(grep -n "td:release" "$T/gh.log" | cut -d: -f1)" -lt "$(grep -n "issue edit" "$T/gh.log" | cut -d: -f1)" ]'
check test_SEC_12_marker_fields           'grep -q "td:release id=c1 login=@bob reason=prompt_input_exit head=$(git rev-parse HEAD) at=" "$T/gh.log"'
check test_GIT_15_labels_back_on_list     'grep -q "issue edit 42 --remove-label td:claimed --add-label td:available --remove-assignee bob" "$T/gh.log"'
check test_D8_state_released              'grep -q "^state=released" .td/local/claim'

# --- D8: StopFailure then SessionEnd releases exactly once
fire "$END"
check test_D8_release_idempotent          '[ "$(calls td:release)" = 1 ]'

# --- D8 / D10: transient errors and throttles never release
setup
fire '{"hook_event_name":"StopFailure","session_id":"s1","error":"server_error"}'
check test_D8_server_error_does_not_release '[ "$(calls td:release)" = 0 ] && grep -q "^state=active" .td/local/claim'
printf '{"rate_limits":{"five_hour":{"used_percentage":40},"seven_day":{"used_percentage":20}}}' > .td/local/usage.json
fire '{"hook_event_name":"StopFailure","session_id":"s1","error":"rate_limit"}'
check test_D10_throttle_with_low_usage_does_not_release '[ "$(calls td:release)" = 0 ]'
printf '{"rate_limits":{"five_hour":{"used_percentage":40},"seven_day":{"used_percentage":97}}}' > .td/local/usage.json
fire '{"hook_event_name":"StopFailure","session_id":"s1","error":"rate_limit"}'
check test_D10_weekly_limit_releases      '[ "$(calls td:release)" = 1 ]'
setup
fire '{"hook_event_name":"StopFailure","session_id":"s1","error":"rate_limit"}'
check test_D10_unknown_usage_releases     '[ "$(calls td:release)" = 1 ]'

# --- D8: /clear only syncs
setup
fire '{"hook_event_name":"SessionEnd","session_id":"s1","reason":"clear"}'
check test_D8_clear_does_not_release      '[ "$(calls td:release)" = 0 ] && grep -q "^state=active" .td/local/claim'

# --- HOOKS: another session can't release this claim; no claim = no-op
setup
fire '{"hook_event_name":"SessionEnd","session_id":"OTHER","reason":"logout"}'
check test_LIFE_11_other_session_cannot_release '[ ! -s "$T/gh.log" ]'
rm .td/local/claim; fire "$END"
check test_D9_hooks_noop_without_claim    '[ ! -s "$T/gh.log" ]'

# --- GIT-09 / SEC-08: protected and secret files are never committed
setup; echo x > .env; mkdir -p .github; echo y > .github/ci.yml; echo ok > app.txt
fire "$END"
check test_GIT_09_skips_protected_and_env_files '! git log -1 --name-only --format= | grep -qE "^(\.env|\.github/)" && git log -1 --name-only --format= | grep -q app.txt'
check test_GIT_09_skipped_files_reported  'grep -q "Not committed.*\.env" "$T/gh.log"'

# --- SEC-02 / SEC-13: a secret in the work is not pushed, but the claim is still released
setup; k="AKIA"; echo "aws_key = ${k}ABCDEFGHIJKLMNOP" > config.txt   # built at runtime so scanners do not flag the repo
fire "$END"
check test_SEC_02_secret_in_wip_not_pushed '[ "$(remote td/42-x)" = "$(git rev-parse origin/main)" ]'
check test_SEC_13_secret_reports_not_saved 'grep -q "progress not saved: check failed" "$T/gh.log" && [ "$(calls td:release)" = 1 ]'

# --- SEC-13: gh down -> publish nothing, exit fast, leave a pending release
setup; echo change > f.txt; export GH_MODE=hang
s=$(date +%s); fire "$END"; e=$(( $(date +%s) - s ))
check test_SEC_13_gh_down_exits_within_10s '[ "$e" -le 10 ]'
check test_SEC_13_gh_down_pending_release  '[ -f .td/local/pending-release ] && grep -q "^state=active" .td/local/claim'
export GH_MODE=ok

# --- GIT-15: no release if the push fails (origin unreachable)
setup; echo change > f.txt; git remote set-url origin "$T/missing.git"
fire "$END"
check test_GIT_15_no_release_without_push  '[ "$(calls td:release)" = 0 ] && [ -f .td/local/pending-release ]'

# --- GIT-06: branch moved under us -> orphan branch, still released
setup
git clone -q "$T/origin.git" "$T/other" 2>/dev/null
( cd "$T/other" && git config user.email o@t && git config user.name other && git switch -q td/42-x &&
  echo theirs > t.txt && git add t.txt && git commit -q -m theirs && git push -q origin td/42-x 2>/dev/null )
rm -rf "$T/other"; echo mine > m.txt
fire "$END"
check test_GIT_06_rejected_push_goes_to_orphan '[ -n "$(remote td/42-x--orphan-bob-$(git rev-parse --short HEAD))" ]'

# --- LIFE-14: claim lost -> orphan push, no release marker
setup; echo mine > m.txt; git add m.txt; git commit -q -m mine; export GH_MODE=lost
fire "$END"
check test_LIFE_14_lost_claim_no_release_marker '[ "$(calls td:release)" = 0 ] && grep -q "^state=released" .td/local/claim'
check test_LIFE_14_lost_claim_work_saved   'git ls-remote "$T/origin.git" | grep -q orphan-bob'
export GH_MODE=ok

# --- SEC-14: paused -> nothing happens
setup; echo c > c.txt; export GH_MODE=paused
fire "$END"
check test_SEC_14_paused_no_release        '[ "$(calls td:release)" = 0 ] && grep -q "^state=active" .td/local/claim && ! git ls-remote "$T/origin.git" | grep -q orphan'
export GH_MODE=ok

# --- D9: HEAD moved off the task branch -> no wip commit on main, task branch still pushed
setup; echo t > t.txt; git add t.txt; git commit -q -m "task work"; git switch -q main; echo stray > stray.txt
fire "$END"
check test_D9_off_branch_no_wip_on_main    '[ "$(git rev-list --count main)" = 1 ] && [ "$(remote td/42-x)" = "$(git rev-parse td/42-x)" ] && [ "$(calls td:release)" = 1 ]'

# --- run from a subdirectory; filenames with spaces are committed
setup; mkdir -p src; echo a > "src/my file.txt"; cd src
fire "$END"; cd ..
check test_GIT_09_subdir_and_spaces        'git log -1 --name-only --format= | grep -q "src/my file.txt"'

# --- SEC-02: ordinary code is not a secret (no false positive)
check test_SEC_02_no_false_positive_on_code 'printf "token = someIdentifierName\nconst apiKey = process.env.API_KEY\n" | sh "$HERE/.td/hooks/scan.sh" -'
check test_SEC_02_detects_quoted_secret     '! printf "api_key = \"abcd1234efgh5678ijkl\"\n" | sh "$HERE/.td/hooks/scan.sh" -'

# --- SEC-05: someone without write access can't release (or publish anything)
setup; echo c > c.txt; export GH_MODE=reader
fire "$END"
check test_SEC_05_non_collaborator_refused '[ "$(calls td:release)" = 0 ] && [ "$(calls "issue comment")" = 0 ]'
export GH_MODE=ok

echo "---"; echo "release: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
