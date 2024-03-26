#!/bin/bash

SRC=$(realpath $(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd))

OUT=$SRC/out
TARGETS=
TAGS=()
UPDATE=0
VERSION=
PUSH=0
IMAGE=docker.io/chromedp/headless-shell

OPTIND=1
while getopts "o:t:g:v:m:i:up" opt; do
case "$opt" in
  o) OUT=$OPTARG ;;
  t) TARGETS=$OPTARG ;;
  g) TAGS+=($OPTARG) ;;
  v) VERSION=$OPTARG ;;
  i) IMAGE=$OPTARG ;;
  u) UPDATE=1 ;;
  p) PUSH=1 ;;
esac
done

# check out dir
if [ ! -d $OUT ]; then
  echo "$OUT does not exist!"
  exit 1
fi

# determine version
if [ -z "$VERSION" ]; then
  VERSION=$(ls $OUT/*.bz2|sort -r -V|head -1|sed -e 's/.*headless-shell-\([0-9\.]\+\).*/\1/')
fi

# determine targets
if [ -z "$TARGETS" ]; then
  TARGETS=$(ls $OUT/*-${VERSION}-*.bz2|sed -e 's/.*headless-shell-[0-9\.]\+-\([a-z0-9]\+\).*/\1/'|xargs)
fi

set -e

TAGS=($VERSION ${TAGS[@]})

echo "VERSION:  $VERSION [$TARGETS]"
echo "IMAGE:    $IMAGE [${TAGS[@]}]"

if [ "$UPDATE" = "1" ]; then
  # update base image
  BASEIMAGE=$(grep 'FROM' Dockerfile|awk '{print $2}')
  echo -e "\n\nPULLING $BASEIMAGE [$TARGETS] ($(date))"
  for TARGET in $TARGETS; do
    (set -x;
      buildah pull \
        --arch $TARGET \
        $BASEIMAGE
    )
  done
fi

IMAGES=()
for TARGET in $TARGETS; do
  NAME=localhost/$(basename $IMAGE):$VERSION-$TARGET
  echo -e "\n\nBUILDING $NAME ($(date))"
  ARCHIVE=$OUT/headless-shell-$VERSION-$TARGET.tar.bz2
  if [ ! -f $ARCHIVE ]; then
    echo "ERROR: $ARCHIVE is missing!"
    exit 1
  fi
  (set -x;
    rm -rf $OUT/$VERSION-$TARGET
    mkdir -p $OUT/$VERSION-$TARGET
    tar -C $OUT/$VERSION-$TARGET -jxf $ARCHIVE

    buildah build \
      --platform linux/$TARGET \
      --build-arg VERSION="$VERSION-$TARGET" \
      --tag $NAME \
      $SRC
  )
  IMAGES+=($NAME)
done

echo -e "\n\nCREATING MANIFEST $IMAGE:$VERSION ($(date))"

for TAG in ${TAGS[@]}; do
  NAME=$IMAGE:$TAG
  (set -x;
    buildah manifest exists $NAME \
      && buildah manifest rm $NAME

    buildah manifest create $NAME \
      ${IMAGES[@]}
  )
done

if [ "$PUSH" = "1" ]; then
  for TAG in ${TAGS[@]}; do
    (set -x;
      buildah manifest push \
        --all \
        $MANIFEST \
        docker:$IMAGE:$TAG
    )
  done
fi
