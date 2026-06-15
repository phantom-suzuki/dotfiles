#!/usr/bin/env bash
# gh-cache: TTL disk cache + ETag conditional-request wrapper for read-only `gh` commands.
#
# Why: redundant GitHub API calls are the #1 cause of rate-limit exhaustion in ad-hoc
# work. Re-running the SAME read within TTL is served from disk with ZERO API cost.
# For REST GET, an expired entry is revalidated with a conditional request; a 304
# response does NOT count against the primary rate limit.
#
# Usage:
#   gh-cache.sh <gh args...>
#     gh-cache.sh api rate_limit
#     gh-cache.sh project item-list 35 --owner mationinc --format json > /tmp/board.json
#     GH_CACHE_TTL=60 gh-cache.sh issue list --repo o/r --json number,title
#     GH_CACHE_BYPASS=1 gh-cache.sh ...        # force fresh fetch (still re-caches)
#
# Env:
#   GH_CACHE_DIR     cache dir (default: ${XDG_CACHE_HOME:-~/.cache}/gh-api-cache)
#   GH_CACHE_TTL     seconds an entry stays fresh (default: 300)
#   GH_CACHE_BYPASS  =1 to ignore existing cache freshness (still writes/revalidates)
#
# Writes (mutations, --method POST/PUT/PATCH/DELETE, create/edit/close/merge/...) and
# unrecognised subcommands are passed through to `gh` untouched and never cached, so
# this wrapper is safe to use as a universal prefix.
#
# Cache key = hash of the FULL argument vector. So calls that differ only in a
# client-side `--jq`/`--template` re-fetch instead of reusing one cache entry. For
# maximum reuse, fetch the RAW response once (no --jq) into a file, then run jq/python
# against that file locally:
#   gh-cache.sh project item-list 35 --owner o --format json > /tmp/board.json
#   jq '...' /tmp/board.json   # repeat freely, zero API cost

set -euo pipefail

CACHE_DIR="${GH_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/gh-api-cache}"
TTL="${GH_CACHE_TTL:-300}"
BYPASS="${GH_CACHE_BYPASS:-0}"
SCHEMA="v1"
WARN_REMAINING=200

if [[ $# -eq 0 ]]; then
  printf 'usage: gh-cache.sh <gh args...>\n' >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  printf 'gh-cache: ERROR: gh CLI not found in PATH\n' >&2
  exit 127
fi

now() { date +%s; }

sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

argv=("$@")
n=$#
sub="${argv[0]}"
verb="${argv[1]:-}"

# --- classify the command -------------------------------------------------
method="GET"
is_graphql=0
has_mutation=0
for ((i = 0; i < n; i++)); do
  tok="${argv[i]}"
  case "$tok" in
    -X | --method)
      j=$((i + 1))
      [[ $j -lt $n ]] && method="${argv[j]}"
      ;;
    --method=*) method="${tok#--method=}" ;;
    graphql) is_graphql=1 ;;
  esac
  case "$tok" in
    *mutation*) has_mutation=1 ;;
  esac
done

method_uc="$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')"
method_read=0
case "$method_uc" in GET | HEAD | "") method_read=1 ;; esac

# read-only subcommand allowlist
sub_ok=0
case "$sub" in
  api | issue | pr | project | label | search | repo | release) sub_ok=1 ;;
esac

# for subcommands that have read/write verbs, require a read verb
read_verb=1
case "$sub" in
  issue | pr | project | label | release)
    case "$verb" in
      list | view | status | diff | checks | field-list | item-list) read_verb=1 ;;
      *) read_verb=0 ;;
    esac
    ;;
esac

cacheable=1
if [[ $has_mutation -eq 1 || $method_read -eq 0 || $sub_ok -eq 0 || $read_verb -eq 0 ]]; then
  cacheable=0
fi

# --- pass-through for writes / unknown ------------------------------------
if [[ $cacheable -eq 0 ]]; then
  exec gh "$@"
fi

# --- cache bookkeeping ----------------------------------------------------
mkdir -p "$CACHE_DIR"
key="$SCHEMA-$(printf '%s\0' "$@" | sha)"
body_file="$CACHE_DIR/$key.body"
meta_file="$CACHE_DIR/$key.meta"

ce_ts=0
ce_etag=""
if [[ -f "$meta_file" ]]; then
  while IFS='=' read -r k v; do
    case "$k" in
      ts) ce_ts="$v" ;;
      etag) ce_etag="$v" ;;
    esac
  done <"$meta_file"
fi
[[ "$ce_ts" =~ ^[0-9]+$ ]] || ce_ts=0

write_meta() { # $1=ts $2=etag
  printf 'ts=%s\netag=%s\ncmd=%s\n' "$1" "$2" "${argv[*]}" >"$meta_file"
}

budget_note() { # $1=header-or-mixed file
  local rem res
  rem="$(grep -i '^x-ratelimit-remaining:' "$1" 2>/dev/null | head -n1 | tr -d '\r' | awk -F': ' '{print $2}')"
  res="$(grep -i '^x-ratelimit-resource:' "$1" 2>/dev/null | head -n1 | tr -d '\r' | awk -F': ' '{print $2}')"
  if [[ "$rem" =~ ^[0-9]+$ ]] && ((rem < WARN_REMAINING)); then
    printf 'gh-cache: WARN rate budget low (resource=%s remaining=%s)\n' "${res:-unknown}" "$rem" >&2
  fi
}

strip_headers() { # stdin: `gh api -i` output -> stdout: body only
  awk 'b{sub(/\r$/,"");print;next} /^[[:space:]]*$/{b=1}'
}

# --- fresh cache hit ------------------------------------------------------
age=$(($(now) - ce_ts))
if [[ "$BYPASS" != "1" && -f "$body_file" && $ce_ts -gt 0 && $age -lt $TTL ]]; then
  printf 'gh-cache: HIT (age=%ss ttl=%ss) %s %s\n' "$age" "$TTL" "$sub" "$verb" >&2
  cat "$body_file"
  exit 0
fi

# --- REST GET path: use -i to capture ETag, revalidate when possible ------
if [[ "$sub" == "api" && $is_graphql -eq 0 && $method_read -eq 1 ]]; then
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  cond=()
  if [[ -n "$ce_etag" && -f "$body_file" ]]; then
    cond=(-H "If-None-Match: $ce_etag")
  fi
  if gh api -i "${cond[@]}" "${argv[@]:1}" >"$tmp" 2>/dev/null; then
    rc=0
  else
    rc=$?
  fi
  status="$(head -n1 "$tmp" | tr -d '\r' | awk '{print $2}')"

  if [[ "$status" == "304" && -f "$body_file" ]]; then
    write_meta "$(now)" "$ce_etag"
    printf 'gh-cache: 304 revalidated free (was %ss old) api\n' "$age" >&2
    budget_note "$tmp"
    cat "$body_file"
    exit 0
  fi

  if [[ "$status" == "200" ]]; then
    new_etag="$(grep -i '^etag:' "$tmp" | head -n1 | tr -d '\r' | awk -F': ' '{print $2}')"
    strip_headers <"$tmp" >"$body_file"
    write_meta "$(now)" "$new_etag"
    printf 'gh-cache: MISS stored (api)\n' >&2
    budget_note "$tmp"
    cat "$body_file"
    exit 0
  fi

  # unexpected status (or 304 with no body on disk): fall back to a plain call
  # so the real error/output surfaces to the caller. rm tmp explicitly because
  # `exec` replaces the process and the EXIT trap would not fire.
  printf 'gh-cache: passthrough (api status=%s)\n' "${status:-?}" >&2
  rm -f "$tmp"
  exec gh "$@"
fi

# --- GraphQL / gh subcommand path: plain fetch + TTL cache (no ETag) -------
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
if gh "$@" >"$tmp"; then
  rc=0
else
  rc=$?
fi

if [[ $rc -eq 0 && -s "$tmp" ]]; then
  cp "$tmp" "$body_file"
  write_meta "$(now)" "$ce_etag"
  printf 'gh-cache: MISS stored (%s %s)\n' "$sub" "$verb" >&2
else
  printf 'gh-cache: not cached (rc=%s, empty=%s)\n' "$rc" "$([[ -s "$tmp" ]] && echo no || echo yes)" >&2
fi

cat "$tmp"
exit "$rc"
