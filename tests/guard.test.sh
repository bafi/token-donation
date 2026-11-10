#!/bin/sh
# Tests for .td/hooks/guard.sh. Each test is named after the policy ID it proves (B-02).
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
GUARD="$HERE/.td/hooks/guard.sh"
pass=0; fail=0

# A throwaway repo where HEAD is on a task branch.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q -b main
git -C "$tmp" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$tmp" switch -q -c td/42-csv-export

run() { # run <tool> <field> <value> -> exit code of the guard
  json=$(jq -n --arg t "$1" --arg k "$2" --arg v "$3" --arg cwd "$tmp" \
    '{tool_name:$t, cwd:$cwd, tool_input:{($k):$v}}')
  printf '%s' "$json" | sh "$GUARD" 2>/dev/null; echo $?
}
expect() { # expect <name> <expected-exit> <actual-exit>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "ok   $1"
  else fail=$((fail+1)); echo "FAIL $1 (expected $2, got $3)"; fi
}

# SEC-07: push only the current task branch.
expect test_SEC_07_allows_plain_push          0 "$(run Bash command 'git push')"
expect test_SEC_07_allows_push_own_branch     0 "$(run Bash command 'git push -u origin td/42-csv-export')"
expect test_SEC_07_allows_push_head_refspec   0 "$(run Bash command 'git push origin HEAD:td/42-csv-export')"
expect test_SEC_07_blocks_push_to_main        2 "$(run Bash command 'git push origin HEAD:main')"
expect test_SEC_07_blocks_push_main_branch    2 "$(run Bash command 'git push origin main')"
expect test_SEC_07_blocks_other_task_branch   2 "$(run Bash command 'git push origin td/43-other')"
expect test_SEC_07_blocks_force_push          2 "$(run Bash command 'git push --force origin td/42-csv-export')"
expect test_SEC_07_blocks_force_short         2 "$(run Bash command 'git push -f')"
expect test_SEC_07_blocks_plus_refspec        2 "$(run Bash command 'git push origin +td/42-csv-export')"
expect test_SEC_07_blocks_delete              2 "$(run Bash command 'git push origin --delete td/42-csv-export')"
expect test_SEC_07_blocks_chained_push        2 "$(run Bash command 'npm test && git push origin main')"
expect test_GIT_06_allows_orphan_branch       0 "$(run Bash command 'git push origin HEAD:td/42-csv-export--orphan-bob-abc123')"

# GIT-03: no history rewriting.
expect test_GIT_03_blocks_rebase              2 "$(run Bash command 'git rebase origin/main')"
expect test_GIT_03_blocks_amend               2 "$(run Bash command 'git commit --amend -m x')"
expect test_GIT_03_blocks_reset_hard          2 "$(run Bash command 'git reset --hard HEAD~1')"
expect test_GIT_03_allows_merge               0 "$(run Bash command 'git merge origin/main')"

# SEC-08: protected paths.
expect test_SEC_08_blocks_edit_workflow       2 "$(run Edit file_path "$tmp/.github/workflows/ci.yml")"
expect test_SEC_08_blocks_edit_claude_dir     2 "$(run Write file_path "$tmp/.claude/settings.json")"
expect test_SEC_08_blocks_edit_claude_md      2 "$(run Edit file_path "$tmp/CLAUDE.md")"
expect test_SEC_08_blocks_edit_hooks          2 "$(run Edit file_path "$tmp/.td/hooks/guard.sh")"
expect test_SEC_08_blocks_edit_td_bin          2 "$(run Edit file_path "$tmp/.td/bin/td")"
expect test_SEC_08_blocks_edit_gitignore      2 "$(run Edit file_path "$tmp/.gitignore")"
expect test_SEC_08_blocks_shell_redirect      2 "$(run Bash command 'echo x > .github/workflows/ci.yml')"
expect test_SEC_08_blocks_append_redirect     2 "$(run Bash command 'echo x >> CLAUDE.md')"
expect test_SEC_08_blocks_tee_to_settings      2 "$(run Bash command 'echo {} | tee .claude/settings.json')"
expect test_SEC_08_blocks_rm_hooks             2 "$(run Bash command 'rm -f .td/hooks/guard.sh')"
expect test_SEC_08_blocks_sed_inplace          2 "$(run Bash command 'sed -i "" s/a/b/ .td/bin/td')"
expect test_SEC_08_allows_running_hook_script  0 "$(run Bash command 'printf x > notes.md && sh .td/hooks/release.sh')"
expect test_SEC_08_allows_redirect_elsewhere   0 "$(run Bash command 'cat .claude/settings.json > /tmp/copy.json')"
expect test_SEC_08_allows_handoff_file        0 "$(run Write file_path "$tmp/.td/HANDOFF.md")"
expect test_SEC_08_allows_local_scratch       0 "$(run Write file_path "$tmp/.td/local/notes.md")"
expect test_SEC_08_allows_normal_code         0 "$(run Edit file_path "$tmp/src/export.js")"

# LIFE-14: after this machine's claim is released, block writes, commits and pushes.
mkdir -p "$tmp/.td/local"
printf 'issue=42\nbranch=td/42-csv-export\nstate=released\n' > "$tmp/.td/local/claim"
expect test_LIFE_14_guard_blocks_edit_after_release   2 "$(run Edit file_path "$tmp/src/export.js")"
expect test_LIFE_14_guard_blocks_commit_after_release 2 "$(run Bash command 'git commit -m x')"
expect test_LIFE_14_guard_blocks_push_after_release   2 "$(run Bash command 'git push')"
expect test_LIFE_14_guard_allows_read_after_release   0 "$(run Bash command 'git status')"
sed -i.bak 's/state=released/state=active/' "$tmp/.td/local/claim"
expect test_LIFE_14_guard_allows_edit_when_active     0 "$(run Edit file_path "$tmp/src/export.js")"
rm -rf "$tmp/.td"

# D9: no enforcement off task branches (maintainers build the tool).
git -C "$tmp" switch -q main
expect test_D9_main_allows_edit_claude_dir    0 "$(run Write file_path "$tmp/.claude/settings.json")"
expect test_D9_main_allows_push               0 "$(run Bash command 'git push origin main')"

echo "---"; echo "guard: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
