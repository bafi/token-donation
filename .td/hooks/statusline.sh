#!/bin/sh
# Token Donation status line (D10). Claude Code passes usage data only to the
# status line, so cache it for the hooks, then print a short status.
input=$(cat)
root=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}
dir="$root/.td/local"
mkdir -p "$dir" 2>/dev/null && printf '%s' "$input" > "$dir/usage.json.tmp.$$" && mv "$dir/usage.json.tmp.$$" "$dir/usage.json"

pct=$(printf '%s' "$input" | tr '\n' ' ' | sed -n 's/.*"five_hour"[^}]*"used_percentage"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p')
task=$(sed -n 's/^issue=//p' "$dir/claim" 2>/dev/null)
st=$(sed -n 's/^state=//p' "$dir/claim" 2>/dev/null)
out="td"
[ -n "$task" ] && out="$out #$task ${st:-}"
[ -n "$pct" ] && out="$out | 5h ${pct%%.*}%"
printf '%s\n' "$out"
