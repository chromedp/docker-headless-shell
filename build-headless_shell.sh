#!/bin/bash

SRC=${1:-/media/src}
VER=$2

set -e

DEPOT_TOOLS_DIR=$(dirname $(which gclient))
if [ -z "$DEPOT_TOOLS_DIR" ]; then
  echo "cannot find gclient"
  exit 1
fi

pushd $DEPOT_TOOLS_DIR &> /dev/null
git reset --hard && git pull
popd &> /dev/null

FILES="headless/lib/headless_crash_reporter_client.cc headless/lib/browser/headless_url_request_context_getter.cc headless/public/headless_browser.cc"

if [ ! -d $SRC/chromium ]; then
  mkdir -p $SRC/chromium
fi

if [ ! -d $SRC/chromium/src ]; then
  # retrieve chromium source tree (> 17 gigabytes)
  pushd $SRC/chromium &> /dev/null
  fetch --nohooks chromium
  popd &> /dev/null

  # attempt to install build deps
  pushd $SRC/chromium/src &> /dev/null
  sudo ./build/install-build-deps.sh \
    --no-prompt \
    --no-arm \
    --no-nacl \
    --no-syms \
    --unsupported

  # run hooks (one-time only)
  gclient runhooks
  popd &> /dev/null
fi

pushd $SRC/chromium/src &> /dev/null

for f in $FILES; do
  if [ -f "$f" ]; then
    git checkout $f
  fi
done

set -x

git checkout master && git rebase-update

if [ -z "$VER" ]; then
  VER=$(git tag -l|grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'|sort -r -V|head -1)
fi

PROJECT=out/headless_shell-$VER

git checkout $VER

gclient sync

for f in $FILES; do
  if [ -f "$f" ]; then
    perl -pi -e 's/"HeadlessChrome"/"Chrome"/' $f
  fi
done

rm -rf $PROJECT

mkdir -p $PROJECT

echo 'import("//build/args/headless.gn")
is_debug=false
symbol_level=0
enable_nacl=false
use_jumbo_build=true
remove_webcore_debug_symbols=true' > $PROJECT/args.gn

gn gen $PROJECT

ninja -C $PROJECT headless_shell chrome_sandbox libosmesa.so

popd &> /dev/null
