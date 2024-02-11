#!/bin/bash

SRC=$(realpath $(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd))

if [ ! -d $SRC/out ]; then
  echo "$SRC/out does not exist!"
  exit 1
fi

TAGS=()
UPDATE=0
VERSION=
ARCH=
IMAGE_NAME="chromedp/headless-shell"
USE_BUILDX=0

OPTIND=1
while getopts "t:uv:p:i:x" opt; do
case "$opt" in
  t) TAGS+=($OPTARG) ;;
  u) UPDATE=1 ;;
  v) VERSION=$OPTARG ;;
  p) ARCH=$OPTARG ;;
  i) IMAGE_NAME=$OPTARG ;;
  x) USE_BUILDX=1 ;;
esac
done

if [ -z "$VERSION" ]; then
  pushd $SRC/out &> /dev/null
  VERSION=$(ls *.bz2|sort -r -V|head -1|sed -e 's/^headless-shell-//' -e 's/-.*\.tar\.bz2$//')
  popd &> /dev/null
fi

if [ -z "$ARCH" ]; then
    ARCH="$(uname -m)"
    if [ "$ARCH" = "x86_64" ]; then
        ARCH="amd64"
    fi
fi

set -e

ARCHIVE=$SRC/out/headless-shell-$VERSION-$ARCH.tar.bz2
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

PARAMS=(--tag $IMAGE_NAME:$VERSION)
for TAG in ${TAGS[@]}; do
  PARAMS+=(--tag $IMAGE_NAME:$TAG)
done

if [[ $USE_BUILDX -eq 0 ]]; then
(set -x;
  rm -rf $SRC/out/$VERSION/$ARCH
  mkdir -p  $SRC/out/$VERSION/$ARCH
  tar -jxf $SRC/out/headless-shell-$VERSION-$ARCH.tar.bz2 -C $SRC/out/$VERSION/$ARCH
  docker build --build-arg VERSION=$VERSION --build-arg TARGETARCH=$ARCH ${PARAMS[@]} .
)
else
(set -x;
    rm -rf $SRC/out/$VERSION/amd64 $SRC/out/$VERSION/arm64
    mkdir -p $SRC/out/$VERSION/amd64 $SRC/out/$VERSION/arm64
    tar -jxf $SRC/out/headless-shell-$VERSION-amd64.tar.bz2 -C $SRC/out/$VERSION/amd64
    tar -jxf $SRC/out/headless-shell-$VERSION-arm64.tar.bz2 -C $SRC/out/$VERSION/arm64

    BUILDER_NAME="headless-shell-builder"
    docker buildx inspect $BUILDER_NAME &> /dev/null || ret=$?

    if [[ $ret -eq 1 ]]; then
        echo "Creating builder instance..."
        docker buildx create --name $BUILDER_NAME --driver=docker-container
    else
        echo "Builder instance '$BUILDER_NAME' already exists. Using existing builder..."
   fi

    echo "Running the build..."
    docker buildx build --push --platform linux/arm64/v8,linux/amd64 --build-arg VERSION=$VERSION --tag "${IMAGE_NAME}:${VERSION}" --builder $BUILDER_NAME .

    if [[ $ret -eq 1 ]]; then
        echo "Stopping and removing the builder instance..."
        docker buildx rm $BUILDER_NAME
    fi
)
fi

popd &> /dev/null
