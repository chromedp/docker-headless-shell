#!/bin/bash

# add via `crontab -e`:
#
#   05 */3 * * * $HOME/src/docker/headless-shell/crontab.sh -j <JOBS> 2>&1 >> /var/log/headless/headless.log

SRC=$(realpath $(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd))

ATTEMPTS=10
BASE=/media/src
CHANNELS=
JOBS=$((`nproc` + 2))

OPTIND=1
while getopts "a:b:c:j:" opt; do
case "$opt" in
  a) ATTEMPTS=$OPTARG ;;
  b) BASE=$OPTARG ;;
  c) CHANNELS=$OPTARG ;;
  j) JOBS=$OPTARG ;;
esac
done

set -e

OMAHA="$(curl -s https://omahaproxy.appspot.com/all.json)"
if [ -z "$CHANNELS" ]; then
  CHANNELS=$(jq -r '.[] | select(.os == "win64") | .versions[] | .channel' <<< "$OMAHA"|grep -v 'canary'|tr '\r\n' ' '|sed -e 's/ $//')
fi

export PATH=$PATH:$HOME/src/misc/chrome/depot_tools
export CHROMIUM_BUILDTOOLS_PATH=/media/src/chromium/src/buildtools

pushd $SRC &> /dev/null

echo "------------------------------------------------------------"
echo "STARTING ($(date))"

# retrieve channel versions
declare -A VERSIONS
for CHANNEL in $CHANNELS; do
  VERSION=$(jq -r '.[] | select(.os == "win64") | .versions[] | select(.channel == "'$CHANNEL'") | .current_version' <<< "$OMAHA")
  VERSIONS[$CHANNEL]=$VERSION
  echo "CHANNEL $(tr '[:lower:]' '[:upper:]' <<< "$CHANNEL"): $VERSION"
done

echo "CLEAN UP ($(date))"
./cleanup.sh -c "${CHANNELS[@]}" -v "${VERSIONS[@]}"
echo "ENDED CLEAN UP ($(date))"

# attempt to build the channels
for CHANNEL in $CHANNELS; do
  VERSION=${VERSIONS[$CHANNEL]}
  ARCHIVE=$SRC/out/headless-shell-$VERSION.tar.bz2
  if [ -f $ARCHIVE ]; then
    echo "SKIPPPING BUILD FOR CHANNEL $CHANNEL $VERSION"
    continue;
  fi
  echo "STARTING BUILD FOR CHANNEL $CHANNEL $VERSION ($(date))"
  RET=1
  ./build-headless-shell.sh \
    -a $ATTEMPTS \
    -b $BASE \
    -j $JOBS \
    -u \
    -v $VERSION \
  && RET=$?
  if [ $RET -ne 0 ]; then
    echo "COULD NOT BUILD $CHANNEL $VERSION ($(date))"
    rm -f $ARCHIVE
  fi
  echo "ENDED BUILD FOR $CHANNEL $VERSION ($(date))"
done

# build docker images
BASEIMAGE=$(grep 'FROM' Dockerfile|awk '{print $2}')
(set -x;
  docker pull $BASEIMAGE
)
for CHANNEL in $CHANNELS; do
  VERSION=${VERSIONS[$CHANNEL]}
  ARCHIVE=$SRC/out/headless-shell-$VERSION.tar.bz2
  if [ ! -f $ARCHIVE ]; then
    echo "MISSING ARCHIVE FOR CHANNEL $CHANNEL $VERSION, SKIPPING DOCKER BUILD"
    continue
  fi
  if [ -f $ARCHIVE.docker_build_done ]; then
    echo "SKIPPPING DOCKER BUILD FOR CHANNEL $CHANNEL $VERSION"
    continue
  fi
  TAGS=($CHANNEL)
  if [ "$CHANNEL" = "stable" ]; then
    TAGS+=(latest)
  fi
  ./build-docker.sh \
    -v $VERSION \
    -t "${TAGS[@]}"
  touch $ARCHIVE.docker_build_done
  echo "ENDED DOCKER BUILD FOR CHANNEL $CHANNEL $VERSION ($(date))"
done

# push docker images
for CHANNEL in $CHANNELS; do
  VERSION=${VERSIONS[$CHANNEL]}
  ARCHIVE=$SRC/out/headless-shell-$VERSION.tar.bz2
  TAGS=($VERSION $CHANNEL)
  if [ "$CHANNEL" = "stable" ]; then
    TAGS+=(latest)
  fi
  if [ ! -f $ARCHIVE ]; then
    echo "MISSING ARCHIVE FOR CHANNEL $CHANNEL $VERSION, SKIPPING DOCKER PUSH"
    continue
  fi
  if [ -f $ARCHIVE.docker_push_done ]; then
    echo "SKIPPPING DOCKER PUSH FOR CHANNEL $CHANNEL $VERSION"
    continue
  fi
  echo "STARTING DOCKER PUSH FOR CHANNEL $CHANNEL $VERSION ($(date))"
  for TAG in ${TAGS[@]}; do
    echo "DOCKER PUSH CHANNEL $CHANNEL $VERSION $TAG ($(date))"
    (set -x;
      docker push chromedp/headless-shell:$TAG
    )
  done
  touch $ARCHIVE.docker_push_done
  echo "ENDED DOCKER PUSH FOR CHANNEL $CHANNEL $VERSION ($(date))"
done

# publish stable binary to slack
ARCHIVE=$SRC/out/headless-shell-${VERSIONS[stable]}.tar.bz2
if [ ! -f $ARCHIVE ]; then
  echo "MISSING ARCHIVE FOR CHANNEL stable, SKIPPING SLACK PUBLISH"
else
  if [ -f $ARCHIVE.slack_done ]; then
    echo "SKIPPING PUBLISH SLACK $ARCHIVE"
  else
    echo "PUBLISH SLACK ($(date))"
    curl \
      -s \
      -F file=@$ARCHIVE \
      -F channels=CGEV595RP \
      -H "Authorization: Bearer $(cat $HOME/.slack-token)" \
      https://slack.com/api/files.upload
    touch $ARCHIVE.slack_done
    echo -e "\nENDED PUBLISH SLACK ($(date))"
  fi
fi

popd &> /dev/null

echo "DONE ($(date))"
