#!/bin/bash

# add via `crontab -e`:
#
#   05 */3 * * * /usr/bin/flock -w 0 $HOME/src/headless-shell/.lock $HOME/src/headless-shell/build.sh -j <JOBS> 2>&1 >> /var/log/build/headless-shell.log

SRC=$(realpath $(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd))

ATTEMPTS=10
BASE=/media/src
CHANNELS=
CLEANUP=1
JOBS=$((`nproc` + 2))

OPTIND=1
while getopts "a:b:c:Cj:" opt; do
case "$opt" in
  a) ATTEMPTS=$OPTARG ;;
  b) BASE=$OPTARG ;;
  c) CHANNELS=$OPTARG ;;
  C) CLEANUP=0 ;;
  j) JOBS=$OPTARG ;;
esac
done

NOTIFY_TEAM=dev
NOTIFY_CHANNEL=town-square

HOST=$(jq -r '.["headless-shell"].instanceUrl' $HOME/.config/mmctl)
TOKEN=$(jq -r '.["headless-shell"].authToken' $HOME/.config/mmctl)

mmcurl() {
  local method=$1
  local url=$HOST/api/v4/$2
  if [ ! -z "$3" ]; then
    body="-d"
  fi
  curl \
    -s \
    -m 30 \
    -X $method \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    $body "$3" \
    $url
}

NOTIFY_TEAMID=$(mmcurl GET teams/name/$NOTIFY_TEAM|jq -r '.id')
NOTIFY_CHANNELID=$(mmcurl GET teams/$NOTIFY_TEAMID/channels/name/$NOTIFY_CHANNEL|jq -r '.id')

mmfile() {
  local url=$HOST/api/v4/files
  curl \
    -s \
    -H "Authorization: Bearer $TOKEN" \
    -F "channel_id=$NOTIFY_CHANNELID" \
    -F "files=@$1" \
    $url
}

mmpost() {
  local message="$1"
  shift
  local files=''
  while (( "$#" )); do
    files+="\"$1\", "
    shift
  done
  if [ ! -z "$files" ]; then
    files=$(echo -e ',\n  "file_ids": ['$(sed -e 's/, $//' <<< "$files")']')
  fi
  POST=$(cat << END
{
  "channel_id": "$NOTIFY_CHANNELID",
  "message": "$message"$files
}
END
)
  mmcurl POST posts "$POST"
}

if [[ -z "$NOTIFY_TEAMID" || -z "$NOTIFY_CHANNELID" ]]; then
  echo "ERROR: unable to determine NOTIFY_TEAMID or NOTIFY_CHANNELID, exiting ($(date))"
  exit 1
fi

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

for CHANNEL in $CHANNELS_ORDER; do
  echo "CHANNEL: $CHANNEL (${VERSIONS[$CHANNEL]})"
done

if [ "$CLEANUP" = "1" ]; then
  echo "CLEANUP ($(date))"
  ./cleanup.sh -c "${CHANNELS[@]}" -v "${VERSIONS[@]}"
  echo "ENDED CLEANUP ($(date))"
fi

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

# publish binary (stable only)
ARCHIVE=$SRC/out/headless-shell-${VERSIONS[stable]}.tar.bz2
if [ ! -f $ARCHIVE ]; then
  echo "MISSING ARCHIVE FOR CHANNEL stable, SKIPPING PUBLISH"
else
  if [ -f $ARCHIVE.publish_done ]; then
    echo "SKIPPING PUBLISH $ARCHIVE"
  else
    echo "STARTING PUBLISH ($(date))"
    ID=$(mmfile "$ARCHIVE"|jq -r '.file_infos[0].id')
    mmpost 'Built headless-shell `stable` (`'${VERSIONS[stable]}'`)' "$ID"
    touch $ARCHIVE.publish_done
    echo -e "\nENDED PUBLISH ($(date))"
  fi
fi

# build docker images
BASEIMAGE=$(grep 'FROM' Dockerfile|awk '{print $2}')
(set -x;
  docker pull $BASEIMAGE
)
for CHANNEL in $CHANNELS_ORDER; do
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
for CHANNEL in $CHANNELS_ORDER; do
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

  # notify
  HASH=$(docker inspect --format='{{index .RepoDigests 0}}' chromedp/headless-shell:$VERSION|awk -F: '{print $2}')
  LINK=$(printf 'https://hub.docker.com/layers/chromedp/headless-shell/%s/images/sha256-%s?context=explore' $VERSION $HASH)
  TAGTEXT=""
  for TAG in ${TAGS[@]}; do
    TAGTEXT+='`'$TAG'`, '
  done
  mmpost "Pushed chromedp/headless-shell ($(sed -e 's/, $//' <<< "$TAGTEXT")) to Docker hub: [chromedp/headless-shell:$VERSION]($LINK)"

  echo -e "\nENDED DOCKER PUSH FOR CHANNEL $CHANNEL $VERSION ($(date))"
done

echo "DONE ($(date))"

popd &> /dev/null
