#!/bin/bash

# add the following via `crontab -e`:
# SHELL=/bin/bash
# 05 */3 * * * $HOME/src/docker/headless-shell/crontab.sh >> /var/log/headless/headless.log 2>&1

set -e

SRC=$(realpath $(cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))

TREE=/media/src
CHANNELS="stable beta dev"
BUILDATTEMPTS=15

export PATH=$PATH:$HOME/src/misc/chrome/depot_tools
export CHROMIUM_BUILDTOOLS_PATH=/media/src/chromium/src/buildtools

# join_by ',' "${ARRAY[@]}"
function join_by {
  local IFS="$1"; shift; echo "$*";
}

mkdir -p $SRC/out

pushd $SRC &> /dev/null

echo "------------------------------------------------------------"
echo ">>>>> STARTING ($(date)) <<<<<"

# retrieve channel versions
declare -A VERSIONS
for CHANNEL in $CHANNELS; do
  VER=$($TREE/chromium/src/tools/omahaproxy.py --os=linux --channel=$CHANNEL)
  VERSIONS[$CHANNEL]=$VER
  echo ">>>>> CHANNEL $(tr '[:lower:]' '[:upper:]' <<< "$CHANNEL"): $VER <<<<<"
done

echo ">>>>> CLEAN UP ($(date)) <<<<<"
rm -f .last

# remove docker containers
CONTAINERS=$(docker container ls \
  --filter=ancestor=chromedp/headless-shell \
  --filter=status=exited \
  --filter=status=dead \
  --filter=status=created \
  --quiet
)
if [ ! -z "$CONTAINERS" ]; then
  echo ">>>>> REMOVING DOCKER CONTAINERS ($(date)) <<<<<"
  (set -x;
    docker container rm --force $CONTAINERS
  )
fi

# remove docker images
IMAGES=$(docker images \
  --filter=reference=chromedp/headless-shell \
  |sed 1d \
  |egrep -v "($(join_by '|' "${!VERSIONS[@]}"))" \
  |egrep -v "(latest|$(join_by '|' "${VERSIONS[@]}"))" \
  |awk '{print $3}'
)
if [ ! -z "$IMAGES" ]; then
  echo ">>>>> REMOVING DOCKER IMAGES ($(date)) <<<<<"
  (set -x;
    docker rmi --force $IMAGES
  )
fi

# cleanup old directories and archives
pushd $SRC/out &> /dev/null
DIRS=$(find . -maxdepth 1 -type d -printf "%f\n"|egrep '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'|egrep -v "($(join_by '|' "${VERSIONS[@]}"))"||:)
if [ ! -z "$DIRS" ]; then
  (set -x;
    rm -rf $DIRS
  )
fi
ARCHIVES=$(find . -maxdepth 1 -type f -printf "%f\n"|egrep '^headless-shell-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.tar\.bz2'|egrep -v "($(join_by '|' "${VERSIONS[@]}"))"||:)
if [ ! -z "$ARCHIVES" ]; then
  (set -x;
    rm -rf $ARCHIVES
  )
fi
popd &> /dev/null

echo ">>>>> ENDED CLEAN UP ($(date)) <<<<<"

# attempt to build the channels
for CHANNEL in $CHANNELS; do
  VER=${VERSIONS[$CHANNEL]}
  BINARY=$SRC/out/headless-shell-$VER.tar.bz2
  if [ -f $BINARY ]; then
    echo ">>>>> SKIPPPING BUILD FOR CHANNEL $CHANNEL $VER <<<<<"
    continue;
  fi
  echo ">>>>> STARTING BUILD FOR CHANNEL $CHANNEL $VER ($(date)) <<<<<"
  RET=1
  ./build-headless-shell.sh $TREE $VER $BUILDATTEMPTS && RET=$?
  if [ $RET -ne 0 ]; then
    echo ">>>>> COULD NOT BUILD $CHANNEL $VER ($(date)) <<<<<"
    rm -f $BINARY
  fi
  echo ">>>>> ENDED BUILD FOR $CHANNEL $VER ($(date)) <<<<<"
done

# update base docker image
echo ">>>>> STARTING DOCKER PULL ($(date)) <<<<<"
(set -x;
  docker pull debian:stable-slim
)
echo ">>>>> ENDED DOCKER PULL ($(date)) <<<<<"

# build docker images
for CHANNEL in $CHANNELS; do
  VER=${VERSIONS[$CHANNEL]}
  BINARY=$SRC/out/headless-shell-$VER.tar.bz2
  if [ ! -f $BINARY ]; then
    echo ">>>>> MISSING BINARY FOR CHANNEL $CHANNEL $VER, SKIPPING DOCKER BUILD <<<<<"
    continue
  fi
  if [ -f $BINARY.docker_build_done ]; then
    echo ">>>>> SKIPPPING DOCKER BUILD FOR CHANNEL $CHANNEL $VER <<<<<"
    continue
  fi
  rm -rf $SRC/out/$VER
  mkdir -p  $SRC/out/$VER
  tar -jxf $BINARY -C $SRC/out/$VER/
  TAGS=(--tag chromedp/headless-shell:$VER --tag chromedp/headless-shell:$CHANNEL)
  if [ "$CHANNEL" = "stable" ]; then
    TAGS+=(--tag chromedp/headless-shell:latest)
  fi
  echo ">>>>> STARTING DOCKER BUILD FOR CHANNEL $CHANNEL $VER ($(date)) <<<<<"
  (set -x;
    docker build --build-arg VER=$VER ${TAGS[@]} --quiet .
  )
  touch $BINARY.docker_build_done
  echo ">>>>> ENDED DOCKER BUILD FOR CHANNEL $CHANNEL $VER ($(date)) <<<<<"
done

# push docker images
for CHANNEL in $CHANNELS; do
  VER=${VERSIONS[$CHANNEL]}
  BINARY=$SRC/out/headless-shell-$VER.tar.bz2
  TAGS=($VER $CHANNEL)
  if [ "$CHANNEL" = "stable" ]; then
    TAGS+=(latest)
  fi
  if [ ! -f $BINARY ]; then
    echo ">>>>> MISSING BINARY FOR CHANNEL $CHANNEL $VER, SKIPPING DOCKER PUSH <<<<<"
    continue
  fi
  if [ -f $BINARY.docker_push_done ]; then
    echo ">>>>> SKIPPPING DOCKER PUSH FOR CHANNEL $CHANNEL $VER <<<<<"
    continue
  fi
  echo ">>>>> STARTING DOCKER PUSH FOR CHANNEL $CHANNEL $VER ($(date)) <<<<<"
  for TAG in ${TAGS[@]}; do
    echo ">>>>> DOCKER PUSH CHANNEL $CHANNEL $VER $TAG ($(date)) <<<<<"
    (set -x;
      docker push chromedp/headless-shell:$TAG
    )
  done
  touch $BINARY.docker_push_done
  echo ">>>>> ENDED DOCKER PUSH FOR CHANNEL $CHANNEL $VER ($(date)) <<<<<"
done

# publish stable binary to slack
BINARY=$SRC/out/headless-shell-${VERSIONS[stable]}.tar.bz2
if [ ! -f $BINARY ]; then
  echo ">>>>> MISSING BINARY FOR CHANNEL stable ${VERSIONS[stable]}, SKIPPING SLACK PUBLISH <<<<<"
else
  if [ -f $BINARY.slack_done ]; then
    echo ">>>>> SKIPPING PUBLISH SLACK $BINARY <<<<<"
  else
    echo ">>>>> PUBLISH SLACK ($(date)) <<<<<"
    curl \
      -s \
      -F file=@$BINARY \
      -F channels=CGEV595RP \
      -H "Authorization: Bearer $(cat $HOME/.slack-token)" \
      https://slack.com/api/files.upload
    touch $BINARY.slack_done
    echo -e "\n>>>>> END SLACK ($(date)) <<<<<"
  fi
fi

popd &> /dev/null

echo ">>>>> DONE ($(date)) <<<<<"
