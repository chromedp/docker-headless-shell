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
docker pull blitznote/debase:18.04
./build-docker.sh
pushd $SRC/out &> /dev/null
VER=$(ls *.bz2|sort -r -V|head -1|sed -e 's/^headless-shell-//' -e 's/\.tar\.bz2$//')
popd &> /dev/null
docker push chromedp/headless-shell:$VER
docker push chromedp/headless-shell:latest

IMAGES=$(docker images|egrep '^chromedp/headless-shell\s+'|grep -v latest|grep -v $VER|awk '{print $3}')
if [ ! -z "$IMAGES" ]; then
  docker rmi $IMAGES
fi
echo ">>>>> ENDED DOCKER ($(date)) <<<<<"

echo ">>>>> PUBLISH SLACK ($(date)) <<<<<"
curl \
  -F file=@./out/headless-shell-$VER.tar.bz2 \
  -F channels=CGEV595RP \
  -H "Authorization: Bearer $(cat $HOME/.slack-token)" \
  https://slack.com/api/files.upload
echo -e "\n>>>>> END SLACK ($(date)) <<<<<"

popd &> /dev/null
