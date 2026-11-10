#!/bin/sh
# Token Donation UserPromptSubmit hook (D10, LIFE-14).
# After a release, block new prompts on the released task branch, including
# Claude Code's automatic continuation when a usage limit resets. Exit 2 blocks
# the prompt and shows the reason to the user.
root=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}
claimf="$root/.td/local/claim"
[ -f "$claimf" ] || exit 0
[ "$(sed -n 's/^state=//p' "$claimf")" = released ] || exit 0
branch=$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)
[ "$(sed -n 's/^branch=//p' "$claimf")" = "$branch" ] || exit 0
n=$(sed -n 's/^issue=//p' "$claimf")
echo "Token Donation: your claim on task #$n was released (your session ended or tokens ran out), so someone else may be working on it now. Run 'td pick' to claim a task, or switch off branch $branch to keep chatting." >&2
exit 2
