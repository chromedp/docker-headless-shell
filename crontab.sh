#!/bin/bash

set -e

SRC=$(realpath $(cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))

TREE=/media/src
CHANNELS="stable"

export PATH=$PATH:$HOME/src/misc/chrome/depot_tools
export CHROMIUM_BUILDTOOLS_PATH=/media/src/chromium/src/buildtools

# join_by ',' "${ARRAY[@]}"
function join_by {
  local IFS="$1"; shift; echo "$*";
}

mkdir -p $SRC/out

pushd $SRC &> /dev/null

echo "------------------------------------------------------------"

declare -A VERSIONS
for CHANNEL in $CHANNELS; do
  VER=$($TREE/chromium/src/tools/omahaproxy.py --os=linux --channel=$CHANNEL)
  VERSIONS[$CHANNEL]=$VER
  echo "$(tr '[:lower:]' '[:upper:]' <<< "$CHANNEL"): $VER"
done

echo ">>>>> CLEAN UP ($(date)) <<<<<"
# remove containers
CONTAINERS=$(docker container ls \
  --filter=ancestor=chromedp/headless-shell \
  --filter=status=exited \
  --filter=status=dead \
  --filter=status=created \
  --quiet
)
if [ ! -z "$CONTAINERS" ]; then
  docker container rm --force $CONTAINERS
fi

# remove images
IMAGES=$(docker images \
  --filter=reference=chromedp/headless-shell \
  |sed 1d |egrep -v "($(join_by '|' "${VERSIONS[@]}"))" \
  |awk '{print $3}'
)
if [ ! -z "$IMAGES" ]; then
  docker rmi --force $IMAGES
fi

pushd $SRC/out &> /dev/null
# remove old builds
DIRS=$(find . -maxdepth 1 -type d -printf "%f\n"|egrep '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'|egrep -v "($(join_by '|' "${VERSIONS[@]}"))"||true)
if [ ! -z "$DIRS" ]; then
  rm -rf $DIRS
fi
ARCHIVES=$(find . -maxdepth 1 -type f -printf "%f\n"|egrep '^headless-shell-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.tar\.bz2$'|egrep -v "($(join_by '|' "${VERSIONS[@]}"))"||true)
if [ ! -z "$ARCHIVES" ]; then
  rm -rf $ARCHIVES
fi
popd &> /dev/null

echo ">>>>> ENDED CLEAN UP ($(date)) <<<<<"

for CHANNEL in $CHANNELS; do
  VER=${VERSIONS[$CHANNEL]}
  if [ -f "$SRC/out/headless-shell-$VER.tar.bz2" ]; then
    continue;
  fi

  echo ">>>>> STARTING BUILD FOR CHANNEL $CHANNEL $VER ($(date)) <<<<<"
  rm -f .last
  ./build-headless-shell.sh $TREE $VER
  echo ">>>>> ENDED BUILD FOR $CHANNEL $VER ($(date)) <<<<<"
done

echo ">>>>> STARTING DOCKER ($(date)) <<<<<"
# update base image
docker pull blitznote/debase:18.04

# build docker images
for CHANNEL in $CHANNELS; do
  rm -rf $SRC/out/$VER
  mkdir -p  $SRC/out/$VER

  tar -jxf $SRC/out/headless-shell-$VER.tar.bz2 -C $SRC/out/$VER/

  docker build --build-arg VER=$VER -t chromedp/headless-shell:$VER .
  docker push chromedp/headless-shell:$VER

  docker tag chromedp/headless-shell:$VER chromedp/headless-shell:$CHANNEL
  docker push chromedp/headless-shell:$CHANNEL
  if [ "$CHANNEL" = "stable" ]; then
    docker tag chromedp/headless-shell:$VER chromedp/headless-shell:latest
    docker push chromedp/headless-shell:latest
  fi
done
echo ">>>>> ENDED DOCKER ($(date)) <<<<<"

STABLE=$SRC/out/headless-shell-${VERSIONS[stable]}.tar.bz2
if [ ! -f $STABLE.published ]; then
  echo ">>>>> PUBLISH SLACK ($(date)) <<<<<"
  curl \
    -F file=@$STABLE \
    -F channels=CGEV595RP \
    -H "Authorization: Bearer $(cat $HOME/.slack-token)" \
    https://slack.com/api/files.upload
  touch $STABLE.published
  echo -e "\n>>>>> END SLACK ($(date)) <<<<<"
fi

popd &> /dev/null
