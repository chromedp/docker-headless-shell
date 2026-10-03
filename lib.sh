#!/bin/bash
# shared helpers, sourced by the other scripts (not meant to be run directly)

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# join_by ',' ${A[@]} ${B[@]}
join_by() {
  local d=${1-} f=${2-}
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}

# args_for ARRAY --opt a b c  ->  ARRAY=(--opt a --opt b --opt c)
args_for() {
  local -n _out=$1
  local opt=$2
  shift 2
  _out=()
  local v
  for v in "$@"; do
    _out+=("$opt" "$v")
  done
}

# need cmd...: fail if any command is missing
need() {
  local c
  for c in "$@"; do
    command -v "$c" &> /dev/null || die "required command '$c' not found"
  done
}

# default_srcdir OUT: where the chromium checkout lives
default_srcdir() {
  if [ -d /media/src ]; then
    echo /media/src
  else
    echo "$1"
  fi
}

# latest_version CHANNEL
latest_version() {
  verhist -platform win64 -channel "$1" -latest
}

# latest_archive_version OUT: version of the newest headless-shell archive
latest_archive_version() {
  ls "$1"/headless-shell-*.tar.bz2 \
    |sort -r -V \
    |head -1 \
    |sed -e 's/.*headless-shell-\([0-9.]\+\)-[a-z0-9]\+\.tar\.bz2$/\1/'
}

# Option parsing. A script declares its options and calls parse_opts "$@":
#
#   DESC='what the script does'
#   OPTS=(
#     'name|VAR|val|meta|description'   # --name <meta>        sets VAR to the value
#     'name|VAR|list|meta|description'  # --name <meta>        appends to array VAR (repeatable)
#     'name|VAR|flag|value|description' # --name               sets VAR to value
#   )
#
# Both '--name value' and '--name=value' are accepted. -h/--help prints usage
# generated from OPTS, showing each option's current value as its default.
usage() {
  local spec name var kind meta desc left cur
  echo "usage: $(basename "$0") [options]"
  if [ -n "${DESC:-}" ]; then
    printf '\n%s\n' "$DESC"
  fi
  printf '\noptions:\n'
  for spec in "${OPTS[@]}"; do
    IFS='|' read -r name var kind meta desc <<< "$spec"
    left="--$name"
    if [ "$kind" != flag ]; then
      left+=" <$meta>"
    fi
    cur=
    case "$kind" in
      val) cur=${!var} ;;
      list) local -n _ref=$var; cur="${_ref[*]}"; unset -n _ref ;;
    esac
    if [ -n "$cur" ]; then
      desc+=" (default: $cur)"
    fi
    printf '  %-28s %s\n' "$left" "$desc"
  done
  printf '  %-28s %s\n' '-h, --help' 'show this help'
}

parse_opts() {
  local a spec name var kind meta desc found
  for a in "$@"; do
    case "$a" in
      -h|--help) usage; exit 0 ;;
    esac
  done
  while [ $# -gt 0 ]; do
    case "$1" in
      --*=*) set -- "${1%%=*}" "${1#*=}" "${@:2}"; continue ;;
    esac
    found=
    for spec in "${OPTS[@]}"; do
      IFS='|' read -r name var kind meta desc <<< "$spec"
      [ "--$name" = "$1" ] || continue
      found=1
      case "$kind" in
        flag)
          printf -v "$var" %s "$meta"
          shift
          ;;
        val|list)
          [ $# -ge 2 ] || die "missing value for $1"
          if [ "$kind" = val ]; then
            printf -v "$var" %s "$2"
          else
            local -n _ref=$var
            _ref+=("$2")
            unset -n _ref
          fi
          shift 2
          ;;
      esac
      break
    done
    [ -n "$found" ] || die "unknown option: $1 (see --help)"
  done
}
