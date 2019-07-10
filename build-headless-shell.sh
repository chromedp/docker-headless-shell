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

echo "UPDATE: $UPDATE"
echo "LAST: $LAST"

set -e

DEPOT_TOOLS_DIR=$(dirname $(which gclient))
if [ -z "$DEPOT_TOOLS_DIR" ]; then
  echo "gclient not in \$PATH"
  exit 1
fi

# update to latest depot_tools
if [ "$UPDATE" -eq "1" ]; then
  echo "UPDATING $DEPOT_TOOLS_DIR ($(date))"
  pushd $DEPOT_TOOLS_DIR &> /dev/null
  git reset --hard
  git pull
  popd &> /dev/null
fi

# chromium source tree dir
mkdir -p $TREE/chromium

# retrieve chromium source tree
if [ ! -d $TREE/chromium/src ]; then
  echo "RETRIEVING $TREE/chromium/src ($(date))"
  # retrieve
  pushd $TREE/chromium &> /dev/null
  fetch --nohooks chromium
  popd &> /dev/null

  # run hooks
  echo "RUNNING GCLIENT HOOKS $TREE/chromium/src ($(date))"
  pushd $TREE/chromium/src &> /dev/null
  gclient runhooks
  popd &> /dev/null
fi

pushd $TREE/chromium/src &> /dev/null

# update chromium source tree
if [ "$UPDATE" -eq "1" ]; then
  # files in headless that contain the HeadlessChrome user-agent string
  USERAGENT_FILES=$(find ./headless/ -type f -iname \*.cc -print0|xargs -r0 egrep -Hi '"(Headless)?Chrome"'|awk -F: '{print $1}'|sort|uniq)
  echo "RESETTING FILES $USERAGENT_FILES ($(date))"
  for f in $USERAGENT_FILES; do
    git checkout $f
  done

  # update
  echo "CHANGING TO master ($(date))"
  git checkout master
  echo "REBASING TREE ($(date))"
  git rebase-update

  date +%s > $SRC/.last
  echo "NEW LAST: $(cat $SRC/.last) ($(date))"
fi

# determine latest version
if [ -z "$VER" ]; then
  VER=$(git tag -l|grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'|sort -r -V|head -1)
fi

mkdir -p $SRC/out

TMP=$(mktemp -d -p /tmp headless-shell-$VER.XXXXX)
OUT=$SRC/out/headless-shell-$VER.tar.bz2

echo "VER: $VER"
echo "TMP: $TMP"
echo "OUT: $OUT"

PROJECT=out/headless-shell

SYNC=$UPDATE
if [ "$VER" != "$(git name-rev --tags --name-only $(git rev-parse HEAD))" ]; then
  SYNC=1
fi

if [ "$SYNC" -eq "1" ]; then
  # files in headless that contain the HeadlessChrome user-agent string
  USERAGENT_FILES=$(find ./headless/ -type f -iname \*.cc -print0|xargs -r0 egrep -Hi '"(Headless)?Chrome"'|awk -F: '{print $1}'|sort|uniq)
  echo "RESETTING FILES $USERAGENT_FILES ($(date))"
  for f in $USERAGENT_FILES; do
    git checkout $f
  done

  # checkout and sync third-party dependencies
  echo "CHECKING OUT $VER ($(date))"
  git checkout $VER

  echo "GCLIENT SYNC $VER ($(date))"
  gclient sync \
    --with_branch_heads \
    --with_tags \
    --delete_unversioned_trees \
    --reset

  # change user-agent
  # files in headless that contain the HeadlessChrome user-agent string
  USERAGENT_FILES=$(find ./headless/ -type f -iname \*.cc -print0|xargs -r0 egrep -Hi '"(Headless)?Chrome"'|awk -F: '{print $1}'|sort|uniq)
  for f in $USERAGENT_FILES; do
    perl -pi -e 's/"HeadlessChrome"/"Chrome"/' $f
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
echo "STARTING NINJA $VER ($(date))"
ninja -C $PROJECT headless_shell chrome_sandbox
echo "COMPLETED NINJA $VER ($(date))"

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
