#!/bin/bash

SRC=$(realpath $(cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))

if [ ! -d $SRC/out ]; then
  echo "$SRC/out does not exist!"
  exit 1
fi

TAGS=
UPDATE=0
VERSION=

OPTIND=1
while getopts "t:uv:" opt; do
case "$opt" in
  t) TAGS=$OPTARG ;;
  u) UPDATE=1 ;;
  v) VERSION=$OPTARG ;;
esac
done

if [ -z "$VERSION" ]; then
  pushd $SRC/out &> /dev/null
  VERSION=$(ls *.bz2|sort -r -V|head -1|sed -e 's/^headless-shell-//' -e 's/\.tar\.bz2$//')
  popd &> /dev/null
fi

set -e

ARCHIVE=$SRC/out/headless-shell-$VERSION.tar.bz2
if [ ! -f $ARCHIVE ]; then
  echo "error: $ARCHIVE doesn't exist!"
  exit 1
fi

pushd $SRC &> /dev/null

BASEIMAGE=$(grep 'FROM' Dockerfile|awk '{print $2}')
if [ "$UPDATE" = "1" ]; then
  (set -x;
    docker pull $BASEIMAGE
  )
fi

PARAMS=(--tag chromedp/headless-shell:$VERSION)
for TAG in $TAGS; do
  PARAMS+=(--tag chromedp/headless-shell:$TAG)
done

(set -x;
  rm -rf $SRC/out/$VERSION
  mkdir -p  $SRC/out/$VERSION
  tar -jxf $SRC/out/headless-shell-$VERSION.tar.bz2 -C $SRC/out/$VERSION/
  docker build --build-arg VERSION=$VERSION ${PARAMS[@]} --quiet .
)

popd &> /dev/null
