#!/bin/bash

SRC=$(realpath "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)")
. "$SRC/lib.sh"

OUT=
SRCDIR=
CHANNEL=stable
ATTEMPTS=10
JOBS=$(($(nproc) + 2))
JOBFAIL=30
DRYRUN=
TTL=64800
UPDATE=0
TARGETS=()
VERSION=

DESC='Sync the chromium tree to a version, build headless_shell for each target, and
package it into out/headless-shell-<version>-<arch>.tar.bz2.'
OPTS=(
  'out|OUT|val|dir|output directory (default: <script dir>/out)'
  'src|SRCDIR|val|dir|directory containing chromium/src (default: /media/src if present, else the output directory)'
  'channel|CHANNEL|val|name|channel to build'
  'version|VERSION|val|version|version to build (default: latest of the channel)'
  'attempts|ATTEMPTS|val|n|ninja attempts per target'
  'jobs|JOBS|val|n|ninja jobs'
  'job-fail|JOBFAIL|val|n|ninja failures to tolerate (-k)'
  'dry-run|DRYRUN|flag|-n|pass a dry run to ninja'
  'ttl|TTL|val|seconds|update depot_tools and the chromium tree if older than this'
  'update|UPDATE|flag|1|force an update of depot_tools and the chromium tree'
  'target|TARGETS|list|arch|target arch to build (repeatable; default: amd64)'
)
parse_opts "$@"

set -e

[ ${#TARGETS[@]} -gt 0 ] || TARGETS=(amd64)
[ -n "$VERSION" ] || VERSION=$(latest_version "$CHANNEL")
[ -n "$OUT" ] || OUT=$(realpath "$SRC/out")
[ -n "$SRCDIR" ] || SRCDIR=$(default_srcdir "$OUT")

# check source directory exists
[ -d "$SRCDIR" ] || die "$SRCDIR does not exist!"

# create out dir
mkdir -p "$OUT"

# determine last update state
LAST=0
if [ -e "$OUT/last" ]; then
  LAST=$(cat "$OUT/last")
fi
if [ "$(($(date +%s) - LAST))" -gt "$TTL" ]; then
  UPDATE=1
fi

echo "BUILD:    $VERSION [${TARGETS[*]}] (u:$UPDATE j:$JOBS a:$ATTEMPTS)"
echo "SOURCE:   $SRCDIR/chromium/src"

# staging area, removed on exit
WORKROOT=$(mktemp -d -p /tmp "headless-shell-$VERSION.XXXXX")
trap 'rm -rf "$WORKROOT"' EXIT
echo "WORKROOT: $WORKROOT"

# grab depot_tools
if [ ! -d "$OUT/depot_tools" ]; then
  echo -e "\n\nRETRIEVING depot_tools ($(date))"
  (set -x;
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$OUT/depot_tools"
  )
fi

# update to latest depot_tools
if [ "$UPDATE" -eq "1" ]; then
  echo -e "\n\nUPDATING $OUT/depot_tools ($(date))"
  (set -x;
    git -C "$OUT/depot_tools" reset --hard
    git -C "$OUT/depot_tools" checkout main
    git -C "$OUT/depot_tools" pull
  )
fi

# add depot_tools to path
export PATH=$OUT/depot_tools:$PATH

CHROMESRC=$SRCDIR/chromium/src

# retrieve chromium source tree
if [ ! -d "$CHROMESRC" ]; then
  echo -e "\n\nRETRIEVING chromium -> $CHROMESRC ($(date))"
  pushd "$SRCDIR" &> /dev/null
  (set -x;
    fetch --nohooks chromium
    gclient runhooks
  )
  popd &> /dev/null
fi

useragent_files() {
  find "$CHROMESRC/headless" -type f -iname \*.cc -print0 \
    |xargs -r0 grep -EHi '"(Headless)?Chrome"' \
    |awk -F: '{print $1}' \
    |sed -e "s%^$CHROMESRC/%%" \
    |sort \
    |uniq
}

# update chromium source tree
if [ "$UPDATE" -eq "1" ]; then
  echo -e "\n\nREBASING ($(date))"
  USERAGENT_FILES=$(useragent_files)
  (set -x;
    git -C "$CHROMESRC" checkout $USERAGENT_FILES
    git -C "$CHROMESRC" checkout main
    git -C "$CHROMESRC" rebase-update
  )
  date +%s > "$OUT/last"
  echo "LAST: $(cat "$OUT/last") ($(date))"
fi

# determine sync status
SYNC=$UPDATE
if [ "$VERSION" != "$(git -C "$CHROMESRC" name-rev --tags --name-only "$(git -C "$CHROMESRC" rev-parse HEAD)")" ]; then
  SYNC=1
fi

if [ "$SYNC" -eq "1" ]; then
  echo -e "\n\nRESETTING $VERSION ($(date))"
  # files in headless that contain the HeadlessChrome user-agent string
  USERAGENT_FILES=$(useragent_files)
  (set -x;
    git -C "$CHROMESRC" checkout $USERAGENT_FILES
    git -C "$CHROMESRC" checkout "$VERSION"
  )
  pushd "$CHROMESRC" &> /dev/null
  (set -x;
    gclient sync \
      --with_branch_heads \
      --with_tags \
      --delete_unversioned_trees \
      --reset
    ./build/linux/sysroot_scripts/install-sysroot.py --arch=arm64
  )
  # alter the user agent string
  for f in $(useragent_files); do
    perl -pi -e 's/"HeadlessChrome"/"Chrome"/' "$f"
  done
  popd &> /dev/null
fi

# build targets
for TARGET in "${TARGETS[@]}"; do
  NAME=headless-shell-$CHANNEL-$TARGET
  PROJECT=$CHROMESRC/out/$NAME
  mkdir -p "$PROJECT"

  # generate build files
  echo -e "\n\nGENERATING $NAME ($VERSION/$TARGET) -> $PROJECT ($(date))"

  EXTRA=
  if [ "$TARGET" = "arm64" ]; then
    EXTRA="target_cpu = \"arm64\""
  fi
  echo "import(\"//build/args/headless.gn\")
is_debug = false
is_official_build = true
symbol_level = 0
blink_symbol_level = 0
headless_use_prefs = true
chrome_pgo_phase = 0
use_dbus = false
use_bluez = false
$EXTRA
" > "$PROJECT/args.gn"

  pushd "$CHROMESRC" &> /dev/null
  (set -x;
    gn gen "./out/$NAME"
  )
  popd &> /dev/null

  # build
  RET=1
  for i in $(seq 1 "$ATTEMPTS"); do
    echo -e "\n\nSTARTING BUILD ATTEMPT $i FOR $NAME ($VERSION/$TARGET) ($(date))"

    RET=1
    "$OUT/depot_tools/ninja" \
      -j "$JOBS" \
      -k "$JOBFAIL" \
      $DRYRUN \
      -C "$PROJECT" \
      headless_shell && RET=$?

    if [ $RET -eq 0 ]; then
      echo "COMPLETED BUILD ATTEMPT $i FOR $NAME ($VERSION/$TARGET) ($(date))"
      break
    fi
    echo "BUILD ATTEMPT $i FOR $NAME ($VERSION/$TARGET) FAILED ($(date))"
  done

  if [ $RET -ne 0 ]; then
    echo -e "\n\nERROR: COULD NOT COMPLETE BUILD FOR $NAME ($VERSION/$TARGET), BUILD ATTEMPTS HAVE BEEN EXHAUSTED ($(date))"
    exit 1
  fi

  # build stamp
  echo "$VERSION" > "$PROJECT/.stamp"
done

# package
for TARGET in "${TARGETS[@]}"; do
  NAME=headless-shell-$CHANNEL-$TARGET
  PROJECT=$CHROMESRC/out/$NAME
  WORKDIR=$WORKROOT/headless-shell

  # strip
  STRIP=strip
  if [ "$TARGET" = "arm64" ]; then
    STRIP=aarch64-linux-gnu-strip
  fi

  # stage files
  mkdir -p "$WORKDIR"
  echo "STAGING $NAME ($VERSION/$TARGET) -> $WORKDIR ($(date))"
  (set -x;
    cp -a "$PROJECT/.stamp" "$WORKDIR"
    cp -a "$PROJECT"/*.json "$WORKDIR"
    cp -a "$PROJECT"/headless*.pak "$WORKDIR"
    cp -a "$PROJECT/headless_shell" "$WORKDIR/headless-shell"
    cp -a "$PROJECT"/*.so{,.1} "$WORKDIR"
    $STRIP "$WORKDIR/headless-shell" "$WORKDIR"/*.so{,.1}
    chmod -x "$WORKDIR"/*.so{,.1}
    du -s "$WORKDIR"/*
    file "$WORKDIR/headless-shell"
  )

  if [ "$TARGET" = "amd64" ]; then
    echo "VERIFYING $NAME ($VERSION/$TARGET) ($(date))"

    # verify headless-shell runs and reports correct version
    PORT=$(shuf -i 20000-40000 -n 1)
    "$WORKDIR/headless-shell" --remote-debugging-port="$PORT" &> /dev/null & PID=$!
    UA=
    for _ in $(seq 1 30); do
      UA=$(curl --silent --connect-timeout 5 "http://localhost:$PORT/json/version"|jq -r '.Browser') || true
      if [ -n "$UA" ] && [ "$UA" != "null" ]; then
        break
      fi
      sleep 1
    done
    kill -s SIGTERM $PID || true
    set +e
    wait $PID 2>/dev/null
    set -e
    if [ "$UA" != "Chrome/$VERSION" ]; then
      echo -e "\n\nERROR: $NAME ($VERSION/$TARGET) REPORTED VERSION '$UA', NOT 'Chrome/$VERSION'! ($(date))"
      exit 1
    else
      echo -e "\n\n$NAME ($VERSION/$TARGET) REPORTED VERSION '$UA' ($(date))"
    fi
  fi

  ARCHIVE=$OUT/headless-shell-$VERSION-$TARGET.tar.bz2
  echo -e "\n\nPACKAGING $NAME ($VERSION/$TARGET) -> $ARCHIVE ($(date))"
  (set -x;
    rm -f "$ARCHIVE"
    tar -C "$WORKROOT" -cjf "$ARCHIVE" headless-shell
    du -s "$ARCHIVE"
  )

  # next target stages into a clean directory
  rm -rf "$WORKDIR"
done
