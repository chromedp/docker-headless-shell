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

# order channels low -> high
CHANNELS_ORDER=$(
  for i in ${!VERSIONS[@]}; do
    echo "${VERSIONS[$i]}:::$i"
  done | sort -V | awk -F::: '{print $2}'
)
echo -n "BUILD ORDER:"
i=0
for CHANNEL in $CHANNELS_ORDER; do
  if [ "$i" != "0" ]; then
    echo -n ","
  fi
  echo -n " $CHANNEL (${VERSIONS[$CHANNEL]})"
  i=$((i+1))
done
echo

echo "CLEANUP ($(date))"
./cleanup.sh -c "${CHANNELS[@]}" -v "${VERSIONS[@]}"
echo "ENDED CLEANUP ($(date))"

# attempt to build the channels
for CHANNEL in $CHANNELS_ORDER; do
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
  PARAMS=(-t $CHANNEL)
  if [ "$CHANNEL" = "stable" ]; then
    PARAMS+=(-t latest)
  fi
  ./build-docker.sh \
    -v $VERSION \
    ${PARAMS[@]}
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
    (set -x;
      docker push chromedp/headless-shell:$TAG
    )
  done
  touch $ARCHIVE.docker_push_done

  # notify slack
  HASH=$(docker inspect --format='{{index .RepoDigests 0}}' chromedp/headless-shell:$VERSION|awk -F: '{print $2}')
  LINK=$(printf "https://hub.docker.com/layers/chromedp/headless-shell/%s/images/sha256-%s?context=explore" $VERSION $HASH)
  TEXT="Pushed headless-shell (${TAGS[@]}) to Docker hub: <$LINK|chromedp/headless-shell:$VERSION>"
  curl \
    -s \
    -X POST \
    -H "Authorization: Bearer $(cat $HOME/.slack-token)" \
    -H "Content-Type: application/json" \
    -d "{\"channel\": \"CGEV595RP\", \"text\": \"$TEXT\", \"as_user\": true}" \
    https://slack.com/api/chat.postMessage
  echo -e "\nENDED DOCKER PUSH FOR CHANNEL $CHANNEL $VERSION ($(date))"
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
