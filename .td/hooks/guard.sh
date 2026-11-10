#!/bin/sh
# Token Donation guardrail: a Claude Code PreToolUse hook.
# Enforces SEC-07 (push only to your own task branch), SEC-08 (protected paths)
# and GIT-03 (no history rewriting), but only while HEAD is on a td/* branch (D9).
# Input: hook JSON on stdin. To block: exit 2, with the reason on stderr.
# Uses only POSIX sh, git and jq (jq ships with macOS 15+ and most Linux distros).

input=$(cat)

command -v jq >/dev/null 2>&1 || { echo "td-guard: jq not found; guard inactive" >&2; exit 0; }

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

case "$branch" in
  td/*) ;;          # on a task branch: enforce
  *) exit 0 ;;      # D9: maintainers on other branches are not restricted
esac

block() { echo "td-guard: BLOCKED ($1). $2" >&2; exit 2; }

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')

# LIFE-14: once this machine's claim on the branch is released (e.g. tokens ran
# out), this session must not keep working on it: someone else may hold it now.
claimf="$root/.td/local/claim"
if [ -f "$claimf" ] && [ "$(sed -n 's/^state=//p' "$claimf")" = released ] &&
   [ "$(sed -n 's/^branch=//p' "$claimf")" = "$branch" ]; then
  msg="Your claim on this task was released. Run 'td pick' to claim it again before working."
  case "$tool" in
    Edit|Write|MultiEdit|NotebookEdit) block LIFE-14 "$msg" ;;
    Bash)
      case "$(printf '%s' "$input" | jq -r '.tool_input.command // empty')" in
        *"git commit"*|*"git push"*|*"git merge"*) block LIFE-14 "$msg" ;;
      esac ;;
  esac
fi

case "$tool" in
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
    # Squash runs of whitespace so the patterns below are simpler.
    c=$(printf '%s' "$cmd" | tr -s ' \t\n' '   ')

    # GIT-03: never rewrite pushed history on a task branch.
    case "$c" in
      *"git rebase"*)            block GIT-03 "Merge instead of rebasing (GIT-05)." ;;
      *"git commit --amend"*|*"git commit "*"--amend"*) block GIT-03 "Make a new commit instead of amending." ;;
      *"git reset --hard"*)      block GIT-03 "Don't reset a task branch. Undo with a new commit." ;;
    esac

    # SEC-07: the only allowed push is a plain push of the current task branch.
    case "$c" in
      *"git push"*)
        case "$c" in
          *" -f"*|*"--force"*|*"--delete"*|*" -d "*|*"--mirror"*|*"--all"*|*"--tags"*|*" +"*)
            block SEC-07 "Force, delete and bulk pushes are not allowed on task branches." ;;
        esac
        # Everything after "git push": the remote and refspec arguments.
        args=$(printf '%s' "$c" | sed 's/.*git push//; s/[;&|].*//')
        set -- $args
        for a in "$@"; do
          case "$a" in
            -u|--set-upstream|origin) ;;
            HEAD|"$branch"|"HEAD:$branch"|"HEAD:refs/heads/$branch"|"$branch:$branch") ;;
            *--orphan-*) ;;   # GIT-06 lost-claim safety valve
            -*) block SEC-07 "Push option '$a' is not allowed on task branches." ;;
            *)  block SEC-07 "You may only push '$branch' (or an --orphan- branch), not '$a'." ;;
          esac
        done
        ;;
    esac

    # SEC-08: catch obvious shell writes to protected paths. The Edit/Write checks
    # below are the main guard; CI backs both up on the server.
    case "$c" in
      *">"*".github/"*|*">"*".claude/"*|*">"*"CLAUDE.md"*|*">"*".td/hooks/"*|*">"*".td/bin/"*|*">"*".gitignore"*|\
      *"rm "*".github"*|*"rm "*".claude"*|*"rm "*".td/hooks"*|*"rm "*".td/bin"*|*"rm "*"CLAUDE.md"*)
        block SEC-08 "That command writes to a protected path." ;;
    esac
    ;;

  Edit|Write|MultiEdit|NotebookEdit)
    f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
    # Resolve symlinks (e.g. macOS /var -> /private/var) on the part of the path
    # that already exists, so it compares equal to git's physical repo root.
    p=$f; tail=""
    while [ -n "$p" ] && [ "$p" != "/" ] && [ ! -d "$p" ]; do
      tail="/$(basename "$p")$tail"; p=$(dirname "$p")
    done
    f=$(cd "$p" 2>/dev/null && pwd -P)$tail
    rel=${f#"$root"/}
    case "$rel" in
      .td/HANDOFF.md|.td/local/*) exit 0 ;;   # allowed: checkpoints and scratch
      .github/*|.claude/*|CLAUDE.md|.td/hooks/*|.td/bin/*|.td/config.yml|.gitignore|.gitleaks.toml|CODEOWNERS|.github)
        block SEC-08 "'$rel' is a protected path. Escalate to the owner with needs-owner (AGT-12)." ;;
    esac
    ;;
esac

exit 0
