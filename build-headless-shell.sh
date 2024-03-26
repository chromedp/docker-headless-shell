#!/bin/bash

SRC=$(realpath $(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd))

OUT=
SRCDIR=
CHANNEL=stable
ATTEMPTS=10
JOBS=$((`nproc` + 2))
JOBFAIL=30
DRYRUN=
TTL=86400
UPDATE=0
TARGETS="amd64"
VERSION=

OPTIND=1
while getopts "o:s:c:a:j:k:nl:ut:v:" opt; do
case "$opt" in
  o) OUT=$OPTARG ;;
  s) SRCDIR=$OPTARG ;;
  c) CHANNEL=$OPTARG ;;
  a) ATTEMPTS=$OPTARG ;;
  j) JOBS=$OPTARG ;;
  k) JOBFAIL=$OPTARG ;;
  n) DRYRUN=-n ;;
  l) TTL=$OPTARG ;;
  u) UPDATE=1 ;;
  t) TARGETS=$OPTARG ;;
  v) VERSION=$OPTARG ;;
esac
done

set -e

# determine version
if [ -z "$VERSION" ]; then
  VERSION=$(verhist -platform win64 -channel $CHANNEL -latest)
fi

# determine out dir
if [ -z "$OUT" ]; then
  OUT=$(realpath "$SRC/out")
fi

# determine source dir
if [ -z "$SRCDIR" ]; then
  if [ -d /media/src ]; then
    SRCDIR=/media/src
  else
    SRCDIR=$OUT
  fi
fi

# check source directory exists
if [ ! -d "$SRCDIR" ]; then
  echo "ERROR: $SRCDIR does not exist!"
  exit 1
fi

# create out dir
mkdir -p $OUT

# determine last update state
LAST=0
if [ -e $OUT/last ]; then
  LAST=$(cat $OUT/last)
fi
if [ "$((`date +%s` - $LAST))" -gt $TTL ]; then
  UPDATE=1
fi

echo "BUILD:    $VERSION [$TARGETS] (u:$UPDATE j:$JOBS a:$ATTEMPTS)"
echo "SOURCE:   $SRCDIR/chromium/src"

TMPDIR=$(mktemp -d -p /tmp headless-shell-$VERSION.XXXXX)
echo "TMPDIR:   $TMPDIR"

# grab depot_tools
if [ ! -d $OUT/depot_tools ]; then
  echo -e "\n\nRETRIEVING depot_tools ($(date))"
  (set -x;
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git $OUT/depot_tools
  )
fi

# update to latest depot_tools
if [ "$UPDATE" -eq "1" ]; then
  echo -e "\n\nUPDATING $OUT/depot_tools ($(date))"
  (set -x;
    git -C $OUT/depot_tools reset --hard
    git -C $OUT/depot_tools checkout main
    git -C $OUT/depot_tools pull
  )
fi

# add depot_tools to path
export PATH=$OUT/depot_tools:$PATH

CHROMESRC=$SRCDIR/chromium/src

# retrieve chromium source tree
if [ ! -d $CHROMESRC ]; then
  echo -e "\n\nRETRIEVING chromium -> $CHROMESRC ($(date))"
  pushd $SRCDIR &> /dev/null
  (set -x;
    fetch --nohooks chromium
    gclient runhooks
  )
  popd &> /dev/null
fi

useragent_files() {
  find $CHROMESRC/headless -type f -iname \*.cc -print0 \
    |xargs -r0 grep -EHi '"(Headless)?Chrome"' \
    |awk -F: '{print $1}' \
    |sed -e "s%^$CHROMESRC/%%" \
    |sort \
    |uniq
}

# update chromium source tree
if [ "$UPDATE" -eq "1" ]; then
  echo -e "\n\nREBASING ($(date))"
  (set -x;
    git -C $CHROMESRC reset --hard
    git -C $CHROMESRC clean \
      -f -x -d \
      -e build \
      -e buildtools \
      -e third_party \
      -e tools \
      -e components/zucchini \
      -e out
    git -C $CHROMESRC rebase-update
  )
  date +%s > $OUT/last
  echo "LAST: $(cat $OUT/last) ($(date))"
fi

# determine sync status
SYNC=$UPDATE
if [ "$VERSION" != "$(git name-rev --tags --name-only $(git rev-parse HEAD))" ]; then
  SYNC=1
fi

if [ "$SYNC" -eq "1" ]; then
  echo -e "\n\nRESETTING $VERSION ($(date))"
  # files in headless that contain the HeadlessChrome user-agent string
  USERAGENT_FILES=$(useragent_files)
  (set -x;
    git -C $CHROMESRC checkout $USERAGENT_FILES
    git -C $CHROMESRC checkout $VERSION
  )
  pushd $CHROMESRC &> /dev/null
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
    perl -pi -e 's/"HeadlessChrome"/"Chrome"/' $f
  done
  popd &> /dev/null
fi

# build targets
for TARGET in $TARGETS; do
  NAME=headless-shell-$CHANNEL-$TARGET
  PROJECT=$CHROMESRC/out/$NAME
  mkdir -p $PROJECT

  # generate build files
  echo -e "\n\nGENERATING $TARGET $VERSION -> $PROJECT ($(date))"

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
$EXTRA
" > $PROJECT/args.gn

  pushd $CHROMESRC &> /dev/null
  (set -x;
    gn gen ./out/$NAME
  )
  popd &> /dev/null

  # build
  RET=1
  for i in $(seq 1 $ATTEMPTS); do
    echo -e "\n\nSTARTING BUILD ATTEMPT $i FOR $TARGET $VERSION ($(date))"

    RET=1
    $OUT/depot_tools/ninja \
      -j $JOBS \
      -k $JOBFAIL \
      $DRYRUN \
      -C $PROJECT \
      headless_shell && RET=$?

    if [ $RET -eq 0 ]; then
      echo "COMPLETED BUILD ATTEMPT $i FOR $TARGET $VERSION ($(date))"
      break
    fi
    echo "BUILD ATTEMPT $i FOR $TARGET $VERSION FAILED ($(date))"
  done

  if [ $RET -ne 0 ]; then
    echo -e "\n\nERROR: COULD NOT COMPLETE BUILD FOR $TARGET $VERSION, BUILD ATTEMPTS HAVE BEEN EXHAUSTED ($(date))"
    exit 1
  fi

  # build stamp
  echo $VERSION > $PROJECT/.stamp
done

# package
for TARGET in $TARGETS; do
  PROJECT=$CHROMESRC/out/headless-shell-$CHANNEL-$TARGET
  WORKDIR=$TMPDIR/headless-shell

  # strip
  STRIP=strip
  if [ "$TARGET" = "arm64" ]; then
    STRIP=aarch64-linux-gnu-strip
  fi

  # copy files
  mkdir -p $WORKDIR
  (set -x;
    cp -a $PROJECT/headless_shell $WORKDIR/headless-shell
    cp -a $PROJECT/{.stamp,libEGL.so,libGLESv2.so,libvk_swiftshader.so,libvulkan.so.1,vk_swiftshader_icd.json} $WORKDIR
    $STRIP $WORKDIR/headless-shell $WORKDIR/*.so{,.1}
    chmod -x $WORKDIR/*.so{,.1}
    du -s $WORKDIR/*
    file $WORKDIR/headless-shell
  )

  if [ "$TARGET" = "amd64" ]; then
    # verify headless-shell runs and reports correct version
    $WORKDIR/headless-shell --remote-debugging-port=5000 &> /dev/null & PID=$!
    sleep 1
    UA=$(curl --silent --connect-timeout 5 http://localhost:5000/json/version|jq -r '.Browser')
    kill -s SIGTERM $PID
    set +e
    wait $PID 2>/dev/null
    set -e
    if [ "$UA" != "Chrome/$VERSION" ]; then
      echo -e "\n\nERROR: HEADLESS-SHELL REPORTED VERSION '$UA', NOT 'Chrome/$VERSION'! ($(date))"
      exit 1
    else
      echo -e "\n\nHEADLESS SHELL REPORTED VERSION '$UA' ($(date))"
    fi
  fi

  ARCHIVE=$OUT/headless-shell-$VERSION-$TARGET.tar.bz2
  echo -e "\n\nPACKAGING $ARCHIVE ($(date))"
  (set -x;
    rm -f $ARCHIVE
    tar -C $TMPDIR -cjf $ARCHIVE headless-shell
    du -s $ARCHIVE
  )
done
