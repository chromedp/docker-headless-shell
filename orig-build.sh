#!/bin/bash

TREE=${1:-/media/src}
VER="68.0.3440.75"

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

# checkout changed files (avoid reset --hard)
_reset_files() {
  git checkout -q $(git ls-files -m)

  local dirs="
    buildtools/third_party/libc++/trunk
    third_party/breakpad/breakpad
    third_party/ffmpeg
    third_party/lss
    third_party/skia
    third_party/swiftshader
    third_party/angle/third_party/vulkan-validation-layers/src/loader
    third_party/angle/third_party/vulkan-validation-layers
  "

  for i in $dirs; do
    pushd $i &> /dev/null
    git checkout -q $(git ls-files -m)
    popd &> /dev/null
  done
}

## apply patches
#for i in $(cat $SRC/alpine/patch-order.txt); do
# echo "APPLYING: alpine/$i"
# patch -p0 -N -r - -s -V never -i $SRC/alpine/$i
#done
_apply_patches() {
  local patches="
    default-pthread-stacksize.patch
    last-commit-position.patch
    musl-fixes.patch
    musl-fixes-breakpad.patch
    musl-hacks.patch
    musl-libc++.patch
    musl-sandbox.patch
    no-execinfo.patch
    no-mallinfo.patch
    resolver.patch
    swiftshader.patch
    secure_getenv.patch
    chromium-clang-r2.patch
    chromium-gcc-r1.patch
    chromium-skia-harmony.patch
    chromium-cors-string-r0.patch
    chromium-libjpeg-r0.patch
    chromium-libwebp-shim-r0.patch
    media-base.patch
    musl-crashpad.patch
    chromium-gcc.patch
    headless-shell.patch
  "

  for i in $patches; do
    echo "APPLYING: $i"
    patch -p0 -N -r - -s -V never -i $SRC/alpine/$i
  done
}

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

# update chromium source tree
if [ "$UPDATE" -eq "1" ]; then
  _reset_files

  # update
  git checkout -q master
  git rebase-update

  date +%s > $SRC/.last

  # checkout and sync third-party dependencies
  git checkout -q $VER
  gclient sync --with_branch_heads --with_tags
fi

TMP=$(mktemp -d -p /tmp headless-shell-$VER.XXXXX)
OUT=$SRC/out/headless-shell-$VER.tar.bz2

echo "VER: $VER"
echo "TMP: $TMP"
echo "OUT: $OUT"

PROJECT=out/headless-shell

#export AR=ar
#export CC=/usr/bin/clang-6.0
#export CXX=/usr/bin/clang++-6.0
#export LD=ld

_reset_files

# change user-agent
find ./headless/ -type f -iname \*.h -or -iname \*.cc -exec \
  perl -pi -e 's/"HeadlessChrome"/"Chrome"/' {} \;

_apply_patches

# ensure build directory exists
mkdir -p $PROJECT

# gn build args
echo 'import("//build/args/headless.gn")

# default
is_debug=false
symbol_level=0
enable_nacl=false
use_jumbo_build=true
remove_webcore_debug_symbols=true

treat_warnings_as_errors=false

use_allocator="tcmalloc"
use_allocator_shim=false
' > $PROJECT/args.gn

# generate build files
gn gen $PROJECT

# build
#AR=$AR CC=$CC CXX=$CXX LD=$LD \
  ninja -C $PROJECT headless_shell chrome_sandbox libosmesa.so

# build stamp
echo $VER > $PROJECT/.stamp

# copy files
mkdir -p $TMP/headless-shell
cp -a $PROJECT/{headless_shell,headless_lib.pak,libosmesa.so,chrome_sandbox,.stamp} $TMP/headless-shell

popd &> /dev/null

# rename chrome_sandbox and strip
pushd $TMP/headless-shell &> /dev/null
mv chrome_sandbox chrome-sandbox
mv headless_shell headless-shell
chmod -x *.so
strip headless-shell chrome-sandbox *.so
popd &> /dev/null

# remove previous
rm -f $OUT

# package tar
pushd $TMP &> /dev/null
tar -cjf $OUT headless-shell
popd &> /dev/null
