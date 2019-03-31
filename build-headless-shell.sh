#!/bin/bash

TREE=${1:-/media/src}
VER=$2

SRC=$(realpath $(cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))

# determine update state
UPDATE=0
LAST=0
if [ -e $SRC/.last ]; then
  LAST=$(cat $SRC/.last)
fi
if [ "$((`date +%s` - $LAST))" -gt 86400 ]; then
  UPDATE=1
fi

set -e

DEPOT_TOOLS_DIR=$(dirname $(which gclient))
if [ -z "$DEPOT_TOOLS_DIR" ]; then
  echo "gclient not in \$PATH"
  exit 1
fi

# update to latest depot_tools
if [ "$UPDATE" -eq "1" ]; then
  pushd $DEPOT_TOOLS_DIR &> /dev/null
  git reset --hard
  git pull
  popd &> /dev/null
fi

# chromium source tree dir
mkdir -p $TREE/chromium

# retrieve chromium source tree
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

# files in headless that contain the HeadlessChrome user-agent string
USERAGENT_FILES=$(find ./headless/ -type f -iname \*.cc -print0|xargs -r0 egrep -Hi '"(Headless)?Chrome"'|awk -F: '{print $1}'|sort|uniq)

# update chromium source tree
if [ "$UPDATE" -eq "1" ]; then
  # checkout changed files (avoid reset --hard)
  for f in $USERAGENT_FILES; do
    if [ -f "$f" ]; then
      git checkout $f
    fi
  done

  # update
  git checkout master
  git rebase-update

  date +%s > $SRC/.last
fi

# determine latest version
if [ -z "$VER" ]; then
  VER=$(git tag -l|grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'|sort -r -V|head -1)
fi

TMP=$(mktemp -d -p /tmp headless-shell-$VER.XXXXX)
OUT=$SRC/out/headless-shell-$VER.tar.bz2

echo "VER: $VER"
echo "TMP: $TMP"
echo "OUT: $OUT"

PROJECT=out/headless-shell

if [ "$UPDATE" -eq "1" ]; then
  # checkout and sync third-party dependencies
  git checkout $VER

  gclient sync

  # change user-agent
  for f in $USERAGENT_FILES; do
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
  blink_symbol_level=0
  headless_use_embedded_resources=true
  ' > $PROJECT/args.gn

  # generate build files
  gn gen $PROJECT
fi

# build
ninja -C $PROJECT headless_shell chrome_sandbox

# build stamp
echo $VER > $PROJECT/.stamp

# copy files
mkdir -p $TMP/headless-shell/swiftshader
cp -a $PROJECT/{headless_shell,chrome_sandbox,.stamp} $TMP/headless-shell
cp -a $PROJECT/swiftshader/*.so $TMP/headless-shell/swiftshader

popd &> /dev/null

# rename and strip
pushd $TMP/headless-shell &> /dev/null
mv chrome_sandbox chrome-sandbox
mv headless_shell headless-shell
strip headless-shell chrome-sandbox swiftshader/*.so
chmod -x swiftshader/*.so
popd &> /dev/null

# remove previous
rm -f $OUT

# package tar
pushd $TMP &> /dev/null
tar -cjf $OUT headless-shell
popd &> /dev/null
