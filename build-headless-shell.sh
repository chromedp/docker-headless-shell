#!/bin/bash

# setup:
#
# 1. install icecc + cccahe, and enable scheduler:
#
#   sudo aptitude install icecc ccache
#   sudo systemctl enable icecc-scheduler.service
#   sudo systemctl start icecc-scheduler.service
#
# 2. manually add custom_hooks to /media/src/chromium/.gclient:
#
#   "custom_hooks": [ {"pattern": ".", "action": ["icecc-create-env.py"] } ]
#
# for full instructions, see: https://github.com/lilles/icecc-chromium

SRC=$(realpath $(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd))

ATTEMPTS=10
BASE=/media/src
JOBS=$((`nproc` + 2))
TTL=86400
UPDATE=0
VERSION=
ARCH='amd64'

OPTIND=1
while getopts "a:b:j:t:uv:p:" opt; do
case "$opt" in
  a) ATTEMPTS=$OPTARG ;;
  b) BASE=$OPTARG ;;
  j) JOBS=$OPTARG ;;
  t) TTL=$OPTARG ;;
  u) UPDATE=1 ;;
  v) VERSION=$OPTARG ;;
  p) ARCH=$OPTARG ;;
esac
done

set -e

# determine last update state
LAST=0
if [ -e $SRC/.last ]; then
  LAST=$(cat $SRC/.last)
fi
if [ "$((`date +%s` - $LAST))" -gt $TTL ]; then
  UPDATE=1
fi

# determine version
if [ -z "$VERSION" ]; then
  SRC_URL="https://versionhistory.googleapis.com/v1/chrome/platforms/linux/channels/stable/versions/"
  VERSION=$(curl -s "${SRC_URL}" | \
    jq -r '.versions[0] | .version'
  )
fi

echo "ATTEMPTS: $ATTEMPTS"
echo "BASE:     $BASE"
echo "JOBS:     $JOBS"
echo "UPDATE:   $UPDATE"
echo "VERSION:  $VERSION"
echo "ARCH:     $ARCH"

mkdir -p $SRC/out
TMPDIR=$(mktemp -d -p /tmp headless-shell-$VERSION-$ARCH.XXXXX)
ARCHIVE=$SRC/out/headless-shell-$VERSION-$ARCH.tar.bz2
echo "TMPDIR:   $TMPDIR"
echo "ARCHIVE:  $ARCHIVE"

# grab depot_tools
if [ ! -d $SRC/depot_tools ]; then
  pushd $SRC &> /dev/null
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
  popd &> /dev/null
fi

# grab icecc-chromium
#if [ ! -d $SRC/icecc-chromium ]; then
#  pushd $SRC &> /dev/null
#  git clone https://github.com/lilles/icecc-chromium.git
#  popd &> /dev/null
#fi

# update to latest depot_tools and icecc-chromium
if [ "$UPDATE" -eq "1" ]; then
  echo "UPDATING $SRC/depot_tools ($(date))"
  pushd $SRC/depot_tools &> /dev/null
  git reset --hard
  git checkout main
  git pull
  popd &> /dev/null

#  echo "UPDATING $SRC/icecc-chromium ($(date))"
#  pushd $SRC/icecc-chromium
#  git reset --hard
#  git checkout master
#  git pull
#  popd &> /dev/null
fi

export PATH=$SRC/depot_tools:$PATH
#export PATH=$SRC/depot_tools:$SRC/icecc-chromium:$PATH
#source $SRC/icecc-chromium/ccache-env

mkdir -p $BASE/chromium

# retrieve chromium source tree
if [ ! -d $BASE/chromium/src ]; then
  echo "RETRIEVING $BASE/chromium/src ($(date))"
  # retrieve
  pushd $BASE/chromium &> /dev/null
  fetch --nohooks chromium
  popd &> /dev/null

  # run hooks
  echo "RUNNING GCLIENT HOOKS $BASE/chromium/src ($(date))"
  pushd $BASE/chromium/src &> /dev/null
  gclient runhooks
  popd &> /dev/null
fi

if [ "$ARCH" =  "arm64" ]; then
 # install build deps
 echo "INSTALLING BUILD DEPS (arm64)"
 pushd $BASE/chromium/src &> /dev/null
 ./build/install-build-deps.sh --arm --no-nacl
 popd &> /dev/null
else
 echo "INSTALLING BUILD DEPS"
 pushd $BASE/chromium/src &> /dev/null
 ./build/install-build-deps.sh
 popd &> /dev/null
fi


pushd $BASE/chromium/src &> /dev/null

# update chromium source tree
if [ "$UPDATE" -eq "1" ]; then
  # files in headless that contain the HeadlessChrome user-agent string
  USERAGENT_FILES=$(find ./headless/ -type f -iname \*.cc -print0|xargs -r0 egrep -Hi '"(Headless)?Chrome"'|awk -F: '{print $1}'|sort|uniq)
  echo "RESETTING FILES $USERAGENT_FILES ($(date))"
  for f in $USERAGENT_FILES; do
    git checkout $f
  done

  # update
  echo "CHANGING TO main ($(date))"
  git checkout main
  echo "REBASING TREE ($(date))"
  git rebase-update

  # mark last
  date +%s > $SRC/.last
  echo "NEW LAST: $(cat $SRC/.last) ($(date))"
fi

PROJECT=out/headless-shell

# determine sync status
SYNC=$UPDATE
if [ "$VERSION" != "$(git name-rev --tags --name-only $(git rev-parse HEAD))" ]; then
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
  echo "CHECKING OUT $VERSION ($(date))"
  git checkout $VERSION

  echo "GCLIENT SYNC $VERSION ($(date))"
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
#  import(\"$SRC/icecc-chromium/icecc.gni\") # icecc parameters (removed)
  echo "import(\"//build/args/headless.gn\")
  is_debug=false
  is_official_build=true
  symbol_level=0
  blink_symbol_level=0
  enable_nacl=false
  headless_use_embedded_resources=true
  headless_use_prefs=true
  chrome_pgo_phase=0
  " > $PROJECT/args.gn


  if [ "$ARCH" = "arm64" ]; then
    echo "ADD target_cpu to args.gn (ARM64)"
    echo "target_cpu=\"arm64\"" >> $PROJECT/args.gn
    # install sysroot
    echo "INSTALL SYSROOT (ARM64)"
    ./build/linux/sysroot_scripts/install-sysroot.py --arch=arm64
  fi


  # generate build files
  gn gen $PROJECT
fi

# build
RET=1
for i in $(seq 1 $ATTEMPTS); do
  RET=1
  echo "STARTING BUILD ATTEMPT $i FOR $VERSION ($(date))"
  #$SRC/icecc-chromium/icecc-ninja -j $JOBS -C $PROJECT headless_shell chrome_sandbox && RET=$?
  $SRC/depot_tools/ninja -j $JOBS -C $PROJECT headless_shell && RET=$?
  if [ $RET -eq 0 ]; then
    echo "COMPLETED BUILD ATTEMPT $i FOR $VERSION ($(date))"
    break
  fi
  echo "BUILD ATTEMPT $i FOR $VERSION FAILED ($(date))"
done
if [ $RET -ne 0 ]; then
  echo "ERROR: COULD NOT COMPLETE BUILD FOR $VERSION ($(date))"
  exit 1
fi

# build stamp
echo $VERSION > $PROJECT/.stamp

# copy files
mkdir -p $TMPDIR/headless-shell
cp -a $PROJECT/{headless_shell,.stamp} $TMPDIR/headless-shell
cp -a $PROJECT/{libEGL.so,libGLESv2.so,libvk_swiftshader.so,libvulkan.so.1,vk_swiftshader_icd.json} $TMPDIR/headless-shell

popd &> /dev/null

pushd $TMPDIR/headless-shell &> /dev/null

# rename and strip
mv headless_shell headless-shell
if [ "$ARCH" = "arm64" ]; then
  aarch64-linux-gnu-strip headless-shell *.so *.so.1
else
  strip headless-shell *.so *.so.1
fi
chmod -x *.so *.so.1

if [ "$ARCH" = "amd64" ]; then
  # verify headless-shell runs and reports correct version
  ./headless-shell --remote-debugging-port=5000 &> /dev/null & PID=$!
  sleep 1
  BROWSER=$(curl --silent --connect-timeout 5 http://localhost:5000/json/version|jq -r '.Browser')
  kill -s SIGTERM $PID
  set +e
  wait $PID 2>/dev/null
  set -e
  if [ "$BROWSER" != "Chrome/$VERSION" ]; then
    echo "ERROR: HEADLESS-SHELL REPORTED VERSION '$BROWSER', NOT 'Chrome/$VERSION'!"
    exit 1
  else
    echo "HEADLESS SHELL REPORTED VERSION '$BROWSER'"
  fi
fi

popd &> /dev/null

# remove previous
rm -f $ARCHIVE

# package tar
pushd $TMPDIR &> /dev/null
tar -cjf $ARCHIVE headless-shell
popd &> /dev/null
