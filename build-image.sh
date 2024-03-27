#!/bin/bash

SRC=$(realpath $(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd))

OUT=$SRC/out
TARGETS=()
TAGS=()
VERSION=
PUSH=0
IMAGE=docker.io/chromedp/headless-shell

OPTIND=1
while getopts "o:t:g:v:pi:" opt; do
case "$opt" in
  o) OUT=$OPTARG ;;
  t) TARGETS+=($OPTARG) ;;
  g) TAGS+=($OPTARG) ;;
  v) VERSION=$OPTARG ;;
  p) PUSH=1 ;;
  i) IMAGE=$OPTARG ;;
esac
done

set -e

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
if [ ${#TARGETS[@]} -eq 0 ]; then
  TARGETS=($(ls $OUT/*-${VERSION}-*.bz2|sed -e 's/.*headless-shell-[0-9\.]\+-\([a-z0-9]\+\).*/\1/'|xargs))
fi

TAGS=($VERSION ${TAGS[@]})

echo "VERSION:  $VERSION [${TARGETS[@]}]"
echo "IMAGE:    $IMAGE [${TAGS[@]}]"

IMAGES=()
for TARGET in ${TARGETS[@]}; do
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

for TAG in ${TAGS[@]}; do
  NAME=localhost/$(basename $IMAGE):$TAG
  echo -e "\n\nCREATING MANIFEST $NAME ($(date))"
  (set -x;
    buildah manifest exists $NAME \
      && buildah manifest rm $NAME
    buildah manifest create $NAME \
      ${IMAGES[@]}
  )
  if [ $PUSH -eq 1 ]; then
    REPO=$(sed -e 's%^docker\.io/%%' <<< "$IMAGE")
    (set -x;
      buildah manifest push \
        --all \
        $NAME \
        docker://$REPO:$TAG
    )
  fi
done
