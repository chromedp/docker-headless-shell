#!/bin/bash

BUILD=${1:-/media/src/chromium/src}
VER=$2

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

PROJECT=out/headless_shell-$VER

TMP=$(mktemp -d -p /tmp headless_shell-$VER.XXXXX)

OUT=$SRC/$PROJECT.tar.bz2

set -v
rm -f $OUT

rsync -a $BUILD/$PROJECT/{headless_shell,headless_lib.pak,libosmesa.so,chrome_sandbox} $TMP
mv $TMP/chrome_sandbox $TMP/chrome-sandbox

pushd $TMP &> /dev/null

strip headless_shell chrome-sandbox *.so

tar -cjvf $OUT *

popd &> /dev/null
