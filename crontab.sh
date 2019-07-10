#!/bin/bash

set -e

SRC=$(realpath $(cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))

export PATH=$PATH:$HOME/src/misc/chrome/depot_tools
export CHROMIUM_BUILDTOOLS_PATH=/media/src/chromium/src/buildtools

pushd $SRC &> /dev/null

echo "------------------------------------------------------------"
echo ">>>>> STARTING BUILD ($(date)) <<<<<"
rm -f .last
./build-headless-shell.sh
echo ">>>>> ENDED BUILD ($(date)) <<<<<"

echo ">>>>> STARTING DOCKER ($(date)) <<<<<"

# read built version
pushd $SRC/out &> /dev/null
VER=$(ls *.bz2|sort -r -V|head -1|sed -e 's/^headless-shell-//' -e 's/\.tar\.bz2$//')

# remove old builds
DIRS=$(ls -d [0-9]*|egrep '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'|grep -v $VER || true)
if [ ! -z "$DIRS" ]; then
  rm -rf $DIRS
fi
ARCHIVES=$(ls headless-shell-*.tar.bz2|grep -v $VER || true)
if [ ! -z "$ARCHIVES" ]; then
  rm -rf $ARCHIVES
fi
popd &> /dev/null

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
  |sed 1d |grep -v latest |grep -v $VER \
  |awk '{print $3}'
)
if [ ! -z "$IMAGES" ]; then
  docker rmi --force $IMAGES
fi

# build docker images
docker pull blitznote/debase:18.04
./build-docker.sh
docker push chromedp/headless-shell:$VER
docker push chromedp/headless-shell:latest

echo ">>>>> ENDED DOCKER ($(date)) <<<<<"

echo ">>>>> PUBLISH SLACK ($(date)) <<<<<"
curl \
  -F file=@./out/headless-shell-$VER.tar.bz2 \
  -F channels=CGEV595RP \
  -H "Authorization: Bearer $(cat $HOME/.slack-token)" \
  https://slack.com/api/files.upload
echo -e "\n>>>>> END SLACK ($(date)) <<<<<"

popd &> /dev/null
