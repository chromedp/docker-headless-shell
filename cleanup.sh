#!/bin/bash

SRC=$(realpath $(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd))

# join_by ',' "${ARRAY[@]}"
function join_by {
  local IFS="$1"; shift; echo "$*";
}

CHANNELS=
VERSIONS=

OPTIND=1
while getopts "c:v:" opt; do
case "$opt" in
  c) CHANNELS=$OPTARG ;;
  j) VERSIONS=$OPTARG ;;
esac
done

set -e

if [ -z "$CHANNELS" ]; then
  OMAHA="$(curl -s https://omahaproxy.appspot.com/all.json)"
  if [ -z "$CHANNELS" ]; then
    CHANNELS=$(jq -r '.[] | select(.os == "win64") | .versions[] | .channel' <<< "$OMAHA")
  fi
fi
if [ -z "$VERSIONS" ]; then
  if [ -z "$OMAHA" ]; then
    OMAHA="$(curl -s https://omahaproxy.appspot.com/all.json)"
  fi
  for CHANNEL in $CHANNELS; do
    VERSIONS+="$(jq -r '.[] | select(.os == "win64") | .versions[] | select(.channel == "'$CHANNEL'") | .current_version' <<< "$OMAHA") "
  done
fi

pushd $SRC &> /dev/null

# cleanup old directories and archives
pushd $SRC/out &> /dev/null
DIRS=$(find . -maxdepth 1 -type d -printf "%f\n"|egrep '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'|egrep -v "($(join_by '|' $VERSIONS))"||:)
if [ ! -z "$DIRS" ]; then
  (set -x;
    rm -rf $DIRS
  )
fi
ARCHIVES=$(find . -maxdepth 1 -type f -printf "%f\n"|egrep '^headless-shell-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.tar\.bz2'|egrep -v "($(join_by '|' $VERSIONS))"||:)
if [ ! -z "$ARCHIVES" ]; then
  (set -x;
    rm -rf $ARCHIVES
  )
fi
popd &> /dev/null

# remove docker containers
CONTAINERS=$(docker container ls \
  --filter=ancestor=chromedp/headless-shell \
  --filter=status=exited \
  --filter=status=dead \
  --filter=status=created \
  --quiet
)
if [ ! -z "$CONTAINERS" ]; then
  (set -x;
    docker container rm --force $CONTAINERS
  )
fi

# remove docker images
IMAGES=$(docker images \
  --filter=reference=chromedp/headless-shell \
  |sed 1d \
  |egrep -v "($(join_by '|' $CHANNELS))" \
  |egrep -v "(latest|$(join_by '|' $VERSIONS))" \
  |awk '{print $3}'
)
if [ ! -z "$IMAGES" ]; then
  (set -x;
    docker rmi --force $IMAGES
  )
fi
