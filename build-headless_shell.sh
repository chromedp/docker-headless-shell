#!/bin/bash

TREE=${1:-/media/src}
VER=$2

SRC=$(realpath $(cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))

set -e

DEPOT_TOOLS_DIR=$(dirname $(which gclient))
if [ -z "$DEPOT_TOOLS_DIR" ]; then
  echo "cannot find gclient"
  exit 1
fi

# update to latest depot_tools
pushd $DEPOT_TOOLS_DIR &> /dev/null
git reset --hard && git pull
popd &> /dev/null

FILES="headless/lib/headless_crash_reporter_client.cc headless/lib/browser/headless_url_request_context_getter.cc headless/public/headless_browser.cc"

if [ ! -d $TREE/chromium ]; then
  mkdir -p $TREE/chromium
fi

# retrieve chromium source tree if it doesn't exist
if [ ! -d $TREE/chromium/src ]; then
  # retrieve
  pushd $TREE/chromium &> /dev/null
  fetch --nohooks chromium
  popd &> /dev/null

  # run hooks
  pushd $TREE/chromium/src &> /dev/null
  gclient runhooks
  popd &> /dev/null
fi

pushd $TREE/chromium/src &> /dev/null

# reset the changed files (to avoid a reset --hard)
for f in $FILES; do
  if [ -f "$f" ]; then
    git checkout $f
  fi
done

# retrieve updates
git checkout master && git rebase-update

# determine latest version
if [ -z "$VER" ]; then
  VER=$(git tag -l|grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'|sort -r -V|head -1)
fi

TMP=$(mktemp -d -p /tmp headless_shell-$VER.XXXXX)
OUT=$SRC/out/headless_shell-$VER.tar.bz2

echo "VER: $VER"
echo "TMP: $TMP"
echo "OUT: $OUT"

PROJECT=out/headless_shell

# checkout and sync third-party dependencies
git checkout $VER
gclient sync

# change user-agent
for f in $FILES; do
  if [ -f "$f" ]; then
    perl -pi -e 's/"HeadlessChrome"/"Chrome"/' $f
  fi
done

# ensure build directory exists
mkdir -p $PROJECT

# gn build args
echo 'import("//build/args/headless.gn")
is_debug=false
symbol_level=0
enable_nacl=false
use_jumbo_build=true
remove_webcore_debug_symbols=true' > $PROJECT/args.gn

# generate build files
gn gen $PROJECT

# build
ninja -C $PROJECT headless_shell chrome_sandbox libosmesa.so

# build stamp
echo $VER > $PROJECT/.stamp

# copy files
mkdir -p $TMP/headless_shell
cp -a $PROJECT/{headless_shell,headless_lib.pak,libosmesa.so,chrome_sandbox,.stamp} $TMP/headless_shell

popd &> /dev/null

# rename chrome_sandbox and strip
pushd $TMP/headless_shell &> /dev/null
mv chrome_sandbox chrome-sandbox
strip headless_shell chrome-sandbox *.so
popd &> /dev/null

# remove previous
rm -f $OUT

# package tar
pushd $TMP &> /dev/null
tar -cjf $OUT headless_shell
popd &> /dev/null
