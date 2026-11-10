#!/bin/sh
# Runs every test file in tests/. Exits non-zero if any test fails.
cd "$(dirname "$0")" || exit 1
status=0
for t in ./*.test.sh; do
  echo "== $t"
  sh "$t" || status=1
done
exit $status
