#!/bin/sh
# Token Donation secret scanner (SEC-02, D6). Plain shell, no dependencies.
# Usage: scan.sh <file>|-   Exit: 0 clean, 1 secret found, 2 could not run.
# CI and GitHub push protection back this up; this is the local first line.

src=${1:--}
if [ "$src" = - ]; then input=$(cat) || exit 2
else [ -r "$src" ] || exit 2; input=$(cat "$src") || exit 2; fi

printf '%s' "$input" | grep -E -q \
  -e 'AKIA[0-9A-Z]{16}' \
  -e 'gh[pousr]_[A-Za-z0-9]{30,}' \
  -e 'github_pat_[A-Za-z0-9_]{40,}' \
  -e 'sk-ant-[A-Za-z0-9_-]{20,}' \
  -e 'sk-[A-Za-z0-9]{32,}' \
  -e 'xox[baprs]-[A-Za-z0-9-]{10,}' \
  -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' \
  -e '(password|passwd|secret|api[_-]?key)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"' ]{16,}["'"'"']'
rc=$?
case $rc in
  0) exit 1 ;;   # a pattern matched: secret found
  1) exit 0 ;;   # no match: clean
  *) exit 2 ;;
esac
