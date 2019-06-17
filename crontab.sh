#!/bin/bash
set -e

SRC=$(realpath $(cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))

pushd $SRC &> /dev/null

./build-headless-shell.sh
./build-docker.sh

pushd $SRC/out &> /dev/null

VER=$(ls *.bz2|sort -r -V|head -1|sed -e 's/^headless-shell-//' -e 's/\.tar\.bz2$//')

popd &> /dev/null

docker push chromedp/headless-shell:$VER
docker push chromedp/headless-shell:latest

popd &> /dev/null
