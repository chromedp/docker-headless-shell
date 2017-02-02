#!/bin/bash

BUILD=${1:-/media/src/chromium/src/out/Headless}

# to build headless_shell:
# cd $BUILD
# ninja headless_shell chrome_sandbox

SRC=$(realpath $(cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))

OUT=$SRC/headless_shell.tar.bz2

TMP=$(mktemp -d -p /tmp headless_shell.XXXXX)

set -ve
rm -f $OUT

rsync -a $BUILD/{headless_shell,headless_lib.pak,libosmesa.so,natives_blob.bin,snapshot_blob.bin,locales} $TMP

pushd $TMP &> /dev/null

strip headless_shell libosmesa.so

tar -cjvf $OUT *

popd &> /dev/null
