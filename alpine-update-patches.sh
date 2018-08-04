#!/bin/bash

TREE=${1:-/media/src}

SRC=$(realpath $(cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))

set -e

mkdir -p $SRC/alpine

if [ ! -d $TREE/aports ]; then
  pushd $TREE &> /dev/null
  git clone git://git.alpinelinux.org/aports.git aports
  popd &> /dev/null
fi

pushd $TREE/aports/community/chromium &> /dev/null

# get latest sources
git reset --hard
git pull

# copy patch files
cp APKBUILD *.patch $SRC/alpine

# get patch order from APKBUILD
sed -ne 's/^\t\([^\.]\+\.patch\)$/\1/p' $SRC/alpine/APKBUILD > $SRC/alpine/patch-order.txt

echo "headless-shell.patch" >> $SRC/alpine/patch-order.txt

popd &> /dev/null
