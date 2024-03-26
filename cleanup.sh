#!/bin/bash

SRC=$(realpath $(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd))

OUT=$SRC/out
IMAGE=docker.io/chromedp/headless-shell

CHANNELS="stable beta dev"
VERSIONS=

OPTIND=1
while getopts "o:i:" opt; do
case "$opt" in
  o) OUT=$OPTARG ;;
  i) IMAGE=$OPTARG ;;
esac
done

set -e

echo "CLEANUP KEEP: latest ${CHANNELS[@]} ${VERSIONS[@]}"

# cleanup old directories and files
#if [ -d $SRC/out ]; then
#  pushd $SRC/out &> /dev/null
#  DIRS=$(find . -maxdepth 1 -type d -printf "%f\n"|egrep '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'|egrep -v "($(join_by '|' $VERSIONS))"||:)
#  if [ ! -z "$DIRS" ]; then
#    (set -x;
#      rm -rf $DIRS
#    )
#  fi
#  FILES=$(find . -maxdepth 1 -type f -printf "%f\n"|egrep '^headless-shell-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.tar\.bz2'|egrep -v "($(join_by '|' $VERSIONS))"||:)
#  if [ ! -z "$FILES" ]; then
#    (set -x;
#      rm -rf $FILES
#    )
#  fi
#  popd &> /dev/null
#fi

# remove containers
CONTAINERS=$(podman container ls \
  --filter=ancestor=$IMAGE \
  --filter=status=exited \
  --filter=status=dead \
  --filter=status=created \
  --quiet)
if [ ! -z "$CONTAINERS" ]; then
  (set -x;
    podman container rm --force $CONTAINERS
  )
fi

# remove images
IMAGES=$(podman images \
  --filter=reference=$IMAGE \
  |sed 1d \
  |egrep -v "($(join_by '|' latest $CHANNELS $VERSIONS))" \
  |awk '{print $3}')
if [ ! -z "$IMAGES" ]; then
  (set -x;
    podman rmi --force $IMAGES
  )
fi
