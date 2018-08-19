#!/bin/bash

set -e

SRC=$(realpath $(cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))

VER=$1
if [ -z "$1" ]; then
  pushd $SRC/out &> /dev/null

  VER=$(ls *.bz2|sort -r -V|head -1|sed -e 's/^headless-shell-//' -e 's/\.tar\.bz2$//')

  popd &> /dev/null
fi

pushd $SRC &> /dev/null

docker build --build-arg VER=$VER -t chromedp/headless-shell:$VER .
docker tag chromedp/headless-shell:$VER chromedp/headless-shell:latest

popd &> /dev/null
