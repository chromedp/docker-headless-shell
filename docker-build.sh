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
  # checkout changed files (avoid reset --hard)
#  for f in $FILES; do
#    if [ -f "$f" ]; then
#      git checkout $f
#    fi
#  done

  # update
  git checkout master
  git rebase-update

  date +%s > $SRC/.last
fi

# determine latest version
if [ -z "$VER" ]; then
  VER=$(git tag -l|grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'|sort -r -V|head -1)
fi

echo "VER: $VER"

if [ "$UPDATE" -eq "1" ]; then
  # checkout and sync third-party dependencies
  git checkout $VER

  gclient sync
fi

popd &> /dev/null

perl -pi -e "s/pkgver=.*/pkgver=$VER/" APKBUILD

set -v
docker run -it \
  -e RSA_PRIVATE_KEY="$(cat ~/.abuild/kenneth.shaw@knq.io-5b9e5e63.rsa)" \
  -e RSA_PRIVATE_KEY_NAME="kenneth.shaw@knq.io-5b9e5e63.rsa" \
  -v "$PWD:/home/builder/package" \
  -v "$HOME/.abuild/packages:/packages" \
  -v "$HOME/.abuild/kenneth.shaw@knq.io-5b9e5e63.rsa.pub:/etc/apk/keys/kenneth.shaw@knq.io-5b9e5e63.rsa.pub" \
  -v "$TREE/chromium:/chromium" \
  chromedp/chromium-builder:latest
