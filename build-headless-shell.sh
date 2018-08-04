#!/bin/bash

TREE=${1:-/media/src/x}
VER="68.0.3440.75"

SRC=$(realpath $(cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))

TMP=$(mktemp -d -p /tmp headless-shell-$VER.XXXXX)
OUT=$SRC/out/headless-shell-$VER.tar.bz2

echo "VER: $VER"
echo "TMP: $TMP"
echo "OUT: $OUT"

PROJECT=out/headless-shell

export AR=ar
export CC=/usr/bin/clang-6.0
export CXX=/usr/bin/clang++-6.0
export LD=ld

set -e

_gn_flags() {
  echo $*
}

pushd $TREE/chromium-$VER

# change user-agent
find ./headless/ -type f -iname \*.h -or -iname \*.cc -exec \
  perl -pi -e 's/"HeadlessChrome"/"Chrome"/' {} \;

# apply patches
for i in $(cat $SRC/alpine/patch-order.txt); do
  echo "APPLYING: alpine/$i"
  set +e
  patch -p0 -N -r - -s -V never -i $SRC/alpine/$i
  set -e
done

# ensure build directory exists
mkdir -p $PROJECT

_c=$(_gn_flags is_clang=true \
  use_sysroot=false \
  treat_warnings_as_errors=false \
  fatal_linker_warnings=false \
  binutils_path=\"/usr/bin\" \
  use_gold=false \
  use_allocator=\"none\" \
  use_allocator_shim=false \
)

#AR="ar" CC="$CC" CXX="$CXX" LD="$CXX" \
#  python tools/gn/bootstrap/bootstrap.py -s -v --no-clean --build-path=out/gn --gn-gen-args "$_c"

# gn build args
echo 'import("//build/args/headless.gn")

# default
is_debug=false
symbol_level=0
enable_nacl=false
use_jumbo_build=true
remove_webcore_debug_symbols=true

# taken from APKBUILD
clang_use_chrome_plugins=false
custom_toolchain="//build/toolchain/linux/unbundle:default"
enable_extensions=false
enable_nacl_nonsfi=false
enable_precompiled_headers=false
fatal_linker_warnings=false
ffmpeg_branding="Chrome"
fieldtrial_testing_like_official_build=true
gold_path="/usr/bin/ld.gold"
host_toolchain="//build/toolchain/linux/unbundle:default"
icu_use_data_file=true
is_clang=true
linux_use_bundled_binutils=false
proprietary_codecs=true
treat_warnings_as_errors=false
use_allocator="none"
use_allocator_shim=false
use_cups=true
use_custom_libcxx=false
use_gnome_keyring=false
use_gold=false
use_lld=false
use_pulseaudio=false
use_sysroot=false
use_system_harfbuzz=true
' > $PROJECT/args.gn

# generate build files
./out/gn/gn gen $PROJECT

# build
AR=$AR CC=$CC CXX=$CXX LD=$LD \
  ninja -C $PROJECT headless_shell libosmesa.so

# build stamp
echo $VER > $PROJECT/.stamp

# copy files
mkdir -p $TMP/headless-shell
cp -a $PROJECT/{headless_shell,headless_lib.pak,libosmesa.so,.stamp} $TMP/headless-shell

popd &> /dev/null

# rename files and strip
pushd $TMP/headless-shell &> /dev/null
#mv chrome_sandbox chrome-sandbox
mv headless_shell headless-shell
strip headless-shell *.so
chmod -x *.so
popd &> /dev/null

# remove previous
rm -f $OUT

# package tar
pushd $TMP &> /dev/null
tar -cjf $OUT headless-shell
popd &> /dev/null
