#!/bin/bash

VER=$1
BUILD=${2:-/media/src/chromium/src/out/Headless}

# to build headless_shell see build-chrome.sh

set -e

SRC=$(realpath $(cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))

if [ -z "$VER" ]; then
  pushd $BUILD &> /dev/null
  VER=$(git symbolic-ref -q --short HEAD || git describe --tags --exact-match)
  popd &> /dev/null
fi

if [ -z "$VER" ]; then
  echo "no version specified"
  exit 1
fi

TMP=$(mktemp -d -p /tmp headless_shell.XXXXX)

OUT=$SRC/out/headless_shell-$VER.tar.bz2

set -v
rm -f $OUT

rsync -a $BUILD/{headless_shell,headless_lib.pak,libosmesa.so,natives_blob.bin,snapshot_blob.bin,locales,chrome_sandbox} $TMP
mv $TMP/chrome_sandbox $TMP/chrome-sandbox

pushd $TMP &> /dev/null

strip headless_shell chrome-sandbox *.so

tar -cjvf $OUT *

popd &> /dev/null
