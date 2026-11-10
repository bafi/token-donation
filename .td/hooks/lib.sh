# Token Donation shared hook library. Source it; don't run it.
# POSIX sh + git + gh only. The release path needs no jq (HOOKS.md).

TD_ROOT=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}
TD_LOCAL="$TD_ROOT/.td/local"
TD_CLAIM="$TD_LOCAL/claim"
TD_HOOKS="$TD_ROOT/.td/hooks"

td_log() { # td_log <hook> <step> <rc>  (no environment, no bodies)
  mkdir -p "$TD_LOCAL" 2>/dev/null
  printf '%s %s session=%s issue=%s claim=%s step=%s rc=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${TD_SESSION:-}" \
    "$(td_claim issue)" "$(td_claim claim_id)" "$2" "$3" >> "$TD_LOCAL/hooks.log" 2>/dev/null
}

# --- hook input -------------------------------------------------------------
td_read_input() { TD_INPUT=$(cat); TD_SESSION=$(td_field session_id); }
td_field() { # flat string field from the hook JSON
  printf '%s' "$TD_INPUT" | tr '\n' ' ' | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

# --- claim file (key=value lines, read with sed, never sourced) ------------
td_claim() { [ -f "$TD_CLAIM" ] && sed -n "s/^$1=//p" "$TD_CLAIM" | head -1; }
td_claim_set() {
  tmp="$TD_CLAIM.tmp.$$"
  { grep -v "^$1=" "$TD_CLAIM" 2>/dev/null; printf '%s=%s\n' "$1" "$2"; } > "$tmp" && mv "$tmp" "$TD_CLAIM"
}

# Active-task check, cheapest first (HOOKS.md). Returns 1 = do nothing.
td_ctx() {
  [ -f "$TD_CLAIM" ] || return 1
  [ "$(td_claim state)" = active ] || return 1
  sid=$(td_claim session_id)
  if [ -n "$sid" ] && [ -n "$TD_SESSION" ] && [ "$sid" != "$TD_SESSION" ]; then return 1; fi
  return 0
}

# --- utilities --------------------------------------------------------------
with_timeout() { # with_timeout <secs> cmd...  (macOS has no timeout(1))
  # Output goes through temp files so a hung child can't hold the caller's pipe open.
  s=$1; shift
  o=$(mktemp) e=$(mktemp)
  "$@" >"$o" 2>"$e" & pid=$!
  ( sleep "$s"; pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 & w=$!
  wait "$pid"; rc=$?
  kill "$w" 2>/dev/null
  cat "$o"; cat "$e" >&2; rm -f "$o" "$e"
  return $rc
}

td_lock() {
  mkdir "$TD_LOCAL/lock" 2>/dev/null && return 0
  # Take over a lock older than 2 minutes.
  if [ -n "$(find "$TD_LOCAL/lock" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
    rmdir "$TD_LOCAL/lock" 2>/dev/null; mkdir "$TD_LOCAL/lock" 2>/dev/null && return 0
  fi
  return 1
}
td_unlock() { rmdir "$TD_LOCAL/lock" 2>/dev/null; }

# --- usage cache written by statusline.sh (D10) -----------------------------
td_usage_low() { # 0 only if a FRESH cache (<10 min) shows both windows below 90%.
  # Unknown or stale usage (API-key users, no status line) counts as "not low",
  # so a rate_limit then releases: a false release only costs a re-pick.
  f="$TD_LOCAL/usage.json"; [ -f "$f" ] || return 1
  [ -n "$(find "$f" -mmin -10 2>/dev/null)" ] || return 1
  j=$(tr '\n' ' ' < "$f")
  p5=$(printf '%s' "$j" | sed -n 's/.*"five_hour"[^}]*"used_percentage"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
  p7=$(printf '%s' "$j" | sed -n 's/.*"seven_day"[^}]*"used_percentage"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
  [ -n "$p5" ] || return 1
  [ "$p5" -lt 90 ] || return 1
  [ -z "$p7" ] || [ "$p7" -lt 90 ] || return 1
  return 0
}

# --- GitHub state -----------------------------------------------------------
# Winning claim id (LIFE-11): the earliest claim after the last valid release.
td_winner() {
  gh issue view "$1" --json comments \
    --jq '.comments[].body | capture("<!-- td:(?<t>claim|release|reap) id=(?<id>[^ ]+)") | "\(.t) \(.id)"' \
  | awk '$1=="claim" && w=="" {w=$2} ($1=="release"||$1=="reap") && $2==w {w=""} END {print w}'
}

# Secret scan of stdin (SEC-02). 0 = clean, 1 = hit, 2 = cannot run.
td_scan() { sh "$TD_HOOKS/scan.sh" -; }
