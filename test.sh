#!/bin/bash
#
SRC=$(realpath $(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd))

OUT=$SRC/out
TARGET=amd64
PORT=5000
VERSION=
IMAGE=docker.io/chromedp/headless-shell

OPTIND=1
while getopts "o:t:p:v:i:" opt; do
case "$opt" in
  o) OUT=$OPTARG ;;
  t) TARGET=$OPTARG ;;
  p) PORT=$OPTARG ;;
  v) VERSION=$OPTARG ;;
  i) IMAGE=$OPTARG ;;
esac
done

# determine version
if [ -z "$VERSION" ]; then
  VERSION=$(ls $OUT/*.bz2|sort -r -V|head -1|sed -e 's/.*headless-shell-\([0-9\.]\+\).*/\1/')
fi

NAME=$(basename $IMAGE)-$VERSION-$TARGET
(set -x;
  podman run \
    --name $NAME \
    --arch $TARGET \
    --rm \
    --detach \
    --publish $PORT:9222 \
    $IMAGE:$VERSION
)

sleep 3

curl -v --connect-timeout 20 --max-time 30 http://localhost:5000/json/version

(set -x;
  podman stop $NAME
)
