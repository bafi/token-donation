#!/bin/sh
# Token Donation release hook: StopFailure (rate_limit|billing_error) and SessionEnd.
# "Tokens ran out -> task back on the list." No LLM; at most one run (state=released).
# Order follows GIT-15: push, then mirror, then release marker, then labels.
# See HOOKS.md "Release sequence". Always exits 0 (SEC-13: the session fails open).

. "$(dirname "$0")/lib.sh"
td_read_input
td_ctx || exit 0
cd "$TD_ROOT" || exit 0

event=$(td_field hook_event_name)
reason=$(td_field reason)
err=$(td_field error)
n=$(td_claim issue); b=$(td_claim branch); claim_id=$(td_claim claim_id); login=$(td_claim login)

push_only() { # sync without releasing: push committed work if it's clean
  td_lock || return 0
  if [ -n "$(git rev-list HEAD --not --remotes 2>/dev/null | head -1)" ] &&
     git log -p --format= HEAD --not --remotes | td_scan; then
    with_timeout 20 git push -q origin "HEAD:refs/heads/$b" >/dev/null 2>&1
    td_log release push-only $?
  fi
  td_unlock
}

# Decide whether this event is a real release (D8, D10).
case "$event" in
  SessionEnd)
    [ "$reason" = clear ] && { push_only; exit 0; }
    reason=${reason:-other} ;;
  StopFailure)
    case "$err" in
      billing_error) ;;
      rate_limit) td_usage_low && { push_only; td_log release throttle-not-release 0; exit 0; } ;;
      *) push_only; exit 0 ;;
    esac
    reason=$err ;;
  *) exit 0 ;;
esac

td_lock || exit 0
trap td_unlock EXIT

pending() { printf 'reason=%s step=%s at=%s\n' "$reason" "$1" "$(date -u +%s)" > "$TD_LOCAL/pending-release"; td_log release "pending-$1" 1; exit 0; }
released() { td_claim_set state released; rm -f "$TD_LOCAL/pending-release"; }
# Work from the task branch's commit even if HEAD has moved elsewhere (D9).
cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
on_branch=0; [ "$cur" = "$b" ] && on_branch=1
src=HEAD; [ "$on_branch" = 1 ] || src="refs/heads/$b"
git rev-parse -q --verify "$src" >/dev/null || { td_log release no-task-branch 1; exit 0; }
short=$(git rev-parse --short "$src")
orphan="$b--orphan-$login-$short"
unpushed() { git rev-list "$src" --not --remotes 2>/dev/null | head -1; }
unpushed_diff() { git log -p --format= "$src" --not --remotes; }

# 1. Check: collaborator, not paused, task still open, and our claim still wins.
perm=$(with_timeout 8 gh repo view --json viewerPermission --jq .viewerPermission 2>/dev/null) || pending check
case "$perm" in WRITE|MAINTAIN|ADMIN) ;; *) td_log release not-collaborator 1; exit 0 ;; esac   # SEC-05
paused=$(with_timeout 8 gh label list --search td-paused --json name --jq 'map(select(.name=="td-paused"))|length' 2>/dev/null) || pending check
[ "$paused" = 0 ] || { td_log release paused 0; exit 0; }                       # SEC-14
state=$(with_timeout 8 gh issue view "$n" --json state --jq .state 2>/dev/null) || pending check
winner=$(with_timeout 8 td_winner "$n" 2>/dev/null) || pending check

# 2. Claim lost or task finished: save our work on an orphan branch (GIT-06), no release marker.
if [ "$state" != OPEN ] || [ "$winner" != "$claim_id" ]; then
  if [ -n "$(unpushed)" ] && unpushed_diff | td_scan &&
     with_timeout 20 git push -q origin "$src:refs/heads/$orphan" >/dev/null 2>&1; then
    gh issue comment "$n" --body "Claim no longer held by @$login when the session ended. Unsaved work pushed to \`$orphan\` (GIT-06)." >/dev/null 2>&1
  fi
  released; td_log release claim-lost 0; exit 0
fi

# 3. Commit leftover work (GIT-09): explicit paths only, never protected or secret files.
skipped=""; made_wip=0
if [ "$on_branch" = 1 ]; then
  list="$TD_LOCAL/changed.$$"
  { git diff --name-only HEAD; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u > "$list"
  while IFS= read -r f; do
    case "$f" in
      .github/*|.claude/*|CLAUDE.md|.td/hooks/*|.td/config.yml|.gitignore|.gitleaks.toml|CODEOWNERS|.env|.env.*|*.pem|*.key|*/.env|*/.env.*)
        skipped="$skipped $f" ;;
      *) git add -- "$f" 2>/dev/null ;;
    esac
  done < "$list"
  rm -f "$list"
else
  td_log release off-branch-no-wip 0
fi
if [ "$on_branch" = 1 ] && ! git diff --cached --quiet; then
  git commit -q -m "wip(td-$n): session ended ($reason) [tests not run]" -m "Refs: #$n" && made_wip=1
fi

# 4. Publish check (SEC-02/03). On failure: undo the local wip, publish nothing, still release.
saved=1
if ! { unpushed_diff; cat .td/HANDOFF.md 2>/dev/null; } | td_scan; then
  [ "$made_wip" = 1 ] && git reset -q --soft HEAD~1
  saved=0
  with_timeout 8 gh issue comment "$n" --body "progress not saved: check failed (secret-scan). The claim is released; the work stays on @$login's machine." >/dev/null 2>&1
fi

# 5. Push. Rejected -> someone else pushed, so use an orphan branch. Network -> don't release.
if [ "$saved" = 1 ] && [ -n "$(unpushed)" ]; then
  out=$(with_timeout 20 git push -q origin "$src:refs/heads/$b" 2>&1); rc=$?
  if [ $rc -ne 0 ]; then
    case "$out" in
      *rejected*|*non-fast-forward*|*fetch\ first*)
        with_timeout 20 git push -q origin "$src:refs/heads/$orphan" >/dev/null 2>&1 || pending push
        gh issue comment "$n" --body "Branch moved while @$login was working; work pushed to \`$orphan\` (GIT-06)." >/dev/null 2>&1 ;;
      *) pending push ;;
    esac
  fi
fi
head=$(git rev-parse "$src")

# 6. Mirror the checkpoint to the issue, if it changed (D1).
if [ "$saved" = 1 ] && [ -f .td/HANDOFF.md ]; then
  h=$(git hash-object .td/HANDOFF.md)
  if [ "$h" != "$(cat "$TD_LOCAL/last-mirrored" 2>/dev/null)" ]; then
    body="$TD_LOCAL/mirror.$$"
    { printf '<!-- td:checkpoint head_sha=%s -->\n**Checkpoint** by @%s\n\n```\n' "$head" "$login"
      sed -e 's#/Users/[^/ ]*#~#g' -e 's#/home/[^/ ]*#~#g' .td/HANDOFF.md   # SEC-03
      printf '```\n'; } > "$body"
    with_timeout 8 gh issue comment "$n" --body-file "$body" >/dev/null 2>&1 || { rm -f "$body"; td_log release mirror-failed 1; exit 0; }
    rm -f "$body"; printf '%s\n' "$h" > "$TD_LOCAL/last-mirrored"
  fi
fi

# 7. Release marker (SEC-12).
note=""; [ -n "$skipped" ] && note=" Not committed (protected or secret paths, still local):$skipped."
with_timeout 8 gh issue comment "$n" --body "<!-- td:release id=$claim_id login=@$login reason=$reason head=$head at=$(date -u +%Y-%m-%dT%H:%M:%SZ) -->
Released by @$login ($reason). Work is on \`$b\` at \`$(git rev-parse --short "$src")\`; the task is back on the list.$note" >/dev/null 2>&1 \
  || { td_log release marker-failed 1; exit 0; }

# 8. Labels: back on the list.
with_timeout 8 gh issue edit "$n" --remove-label td:claimed --add-label td:available --remove-assignee "$login" >/dev/null 2>&1
td_log release labels $?
released
td_log release done 0
exit 0
