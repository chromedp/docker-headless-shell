#!/bin/bash

TREE=${1:-/media/src}

SRC=$(realpath $(cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))

set -e

rm -f $SRC/*.patch

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
cp *.patch $SRC/

popd &> /dev/null
